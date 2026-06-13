import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/permissions/sms_permission_service.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../data/datasources/sms_gateway_realtime_datasource.dart';
import '../../data/datasources/sms_gateway_remote_datasource.dart';
import '../../data/repositories/sms_gateway_repository_impl.dart';
import '../../domain/entities/pending_sms.dart';
import '../../domain/entities/sms_log_entry.dart';
import '../../domain/repositories/sms_gateway_repository.dart';
import '../../domain/usecases/send_sms_usecase.dart';
import '../../native/native_sms_sender.dart';

enum GatewayStatus { stopped, starting, running, errored }

class SmsGatewayController extends ChangeNotifier {
  final SmsPermissionService permissionService;
  final NativeSmsSender nativeSmsSender;
  final LocalStorageService storageService;

  SmsGatewayController({
    required this.permissionService,
    required this.nativeSmsSender,
    required this.storageService,
  });

  // --- state ---
  GatewayStatus _status = GatewayStatus.stopped;
  String _statusMessage = 'Gateway stopped';
  final List<SmsLogEntry> _logs = [];
  static const int _maxLogs = 300;

  int _sentCount = 0;
  int _failedCount = 0;
  DateTime? _lastPollAt;

  Timer? _timer;
  Timer? _heartbeatTimer;
  Timer? _realtimeRetryTimer;
  bool _isProcessing = false;
  bool _disposed = false;

  /// Cờ đánh dấu có trigger realtime tới khi đang chạy poll → finally
  /// re-run để không miss SMS trong burst.
  bool _triggerWhileProcessing = false;

  SmsGatewayRepository? _repository;
  SendSmsUsecase? _sendUsecase;
  SmsGatewayRealtimeDatasource? _realtimeDs;
  GatewayConfig? _activeConfig;

  RealtimeConnectionState _realtimeState = RealtimeConnectionState.disconnected;
  String? _realtimeDetail;
  Duration _activePollInterval = const Duration(seconds: 10);

  static const Duration _realtimeRetryInterval = Duration(minutes: 5);
  static const int _batchLimit = 5;

  /// Số vòng drain liên tiếp tối đa (mỗi vòng = 1 fetch). Sau giới hạn này,
  /// trả về timer-driven polling để không spin CPU/UI khi backend liên tục
  /// nhồi queue đầy. Periodic timer + realtime trigger sẽ tự gọi tiếp.
  static const int _maxDrainRounds = 3;
  int _drainRounds = 0;

  // --- getters ---
  GatewayStatus get status => _status;
  String get statusMessage => _statusMessage;
  List<SmsLogEntry> get logs => List.unmodifiable(_logs);
  int get sentCount => _sentCount;
  int get failedCount => _failedCount;
  DateTime? get lastPollAt => _lastPollAt;
  bool get isRunning => _status == GatewayStatus.running;

  RealtimeConnectionState get realtimeState => _realtimeState;
  String? get realtimeDetail => _realtimeDetail;
  bool get isRealtimeActive => _realtimeState == RealtimeConnectionState.connected;
  Duration get activePollInterval => _activePollInterval;

  // --- lifecycle ---
  Future<void> start() async {
    if (_status == GatewayStatus.running || _status == GatewayStatus.starting) {
      return;
    }

    _setStatus(GatewayStatus.starting, 'Starting gateway...');

    final config = await storageService.readConfig();
    if (!config.isComplete) {
      _setStatus(GatewayStatus.errored,
          'Backend URL / token / device code is missing');
      _log(SmsLogEntry.error('Cannot start: gateway configuration is incomplete'));
      return;
    }
    final hasPermission = await permissionService.hasSmsPermission() ||
        await permissionService.requestSmsPermission();
    if (!hasPermission) {
      _setStatus(GatewayStatus.errored, 'SEND_SMS permission denied');
      _log(SmsLogEntry.error('SEND_SMS permission denied'));
      return;
    }

    if (!await permissionService.hasNotificationPermission()) {
      await permissionService.requestNotificationPermission();
    }

    final apiClient = ApiClient(
      baseUrl: config.backendUrl,
      gatewayToken: config.gatewayToken,
      deviceCode: config.deviceCode,
    );
    final remoteDs = SmsGatewayRemoteDatasource(apiClient);
    _repository = SmsGatewayRepositoryImpl(remoteDs);
    _sendUsecase = SendSmsUsecase(nativeSmsSender);
    _activeConfig = config;

    try {
      await nativeSmsSender.startForegroundService();
    } catch (e) {
      _log(SmsLogEntry.warning('Foreground service unavailable: $e'));
    }

    // ---- Try realtime first; gracefully fall back to polling-only ----
    await _tryStartRealtime(config);

    final pollSeconds = config.pollingIntervalSeconds.clamp(5, 600);
    // Khi realtime active, polling là safety net (max 60s) — không gọi nhiều
    // hơn user setting, nhưng cũng không nhanh hơn 60s.
    _activePollInterval = isRealtimeActive
        ? Duration(
            seconds: pollSeconds > ApiConstants.realtimeFallbackPollInterval.inSeconds
                ? pollSeconds
                : ApiConstants.realtimeFallbackPollInterval.inSeconds,
          )
        : Duration(seconds: pollSeconds);

    _timer = Timer.periodic(
      _activePollInterval,
      (_) => unawaited(processPendingMessages()),
    );
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_sendHeartbeat()),
    );
    // Re-try realtime mỗi 5 phút nếu đang ở trạng thái failed/disconnected
    // (vd backend mới online lại, token được rotate đúng, mạng hồi phục
    // sau khi SignalR đã hết retry-policy).
    _realtimeRetryTimer = Timer.periodic(
      _realtimeRetryInterval,
      (_) => unawaited(_retryRealtimeIfNeeded()),
    );

    final mode = isRealtimeActive
        ? 'realtime + poll ${_activePollInterval.inSeconds}s'
        : 'poll every ${_activePollInterval.inSeconds}s';
    _setStatus(GatewayStatus.running, 'Gateway running · $mode');
    _log(SmsLogEntry.success('Gateway started for ${config.deviceCode}'));

    unawaited(processPendingMessages());
    unawaited(_sendHeartbeat());
  }

  Future<void> _retryRealtimeIfNeeded() async {
    if (_disposed || !isRunning) return;
    if (_realtimeState == RealtimeConnectionState.connected ||
        _realtimeState == RealtimeConnectionState.connecting ||
        _realtimeState == RealtimeConnectionState.reconnecting) {
      return;
    }
    final config = _activeConfig;
    if (config == null) return;
    _log(SmsLogEntry.info('Retrying realtime connection…'));
    await _tryStartRealtime(config);
    // Re-check sau await: user có thể đã Stop trong lúc 8s connect.
    if (_disposed || !isRunning) return;
    if (isRealtimeActive) {
      _restartPollTimerForCurrentMode(config);
    }
  }

  void _restartPollTimerForCurrentMode(GatewayConfig config) {
    // Guard: chỉ tái tạo timer khi gateway VẪN đang running.
    if (_disposed || !isRunning) return;
    _timer?.cancel();
    final pollSeconds = config.pollingIntervalSeconds.clamp(5, 600);
    _activePollInterval = isRealtimeActive
        ? Duration(
            seconds: pollSeconds >
                    ApiConstants.realtimeFallbackPollInterval.inSeconds
                ? pollSeconds
                : ApiConstants.realtimeFallbackPollInterval.inSeconds,
          )
        : Duration(seconds: pollSeconds);
    _timer = Timer.periodic(
      _activePollInterval,
      (_) => unawaited(processPendingMessages()),
    );
    final mode = isRealtimeActive
        ? 'realtime + poll ${_activePollInterval.inSeconds}s'
        : 'poll every ${_activePollInterval.inSeconds}s';
    _setStatus(GatewayStatus.running, 'Gateway running · $mode');
  }

  Future<void> _tryStartRealtime(GatewayConfig config) async {
    // Defensive: nếu vì lý do nào đó còn instance cũ, dọn trước rồi mới
    // tạo mới — tránh leak WebSocket connection.
    final previous = _realtimeDs;
    _realtimeDs = null;
    if (previous != null) {
      try {
        await previous.disconnect();
      } catch (_) {/* ignore */}
    }

    _realtimeDs = SmsGatewayRealtimeDatasource(
      backendUrl: config.backendUrl,
      hubPath: ApiConstants.hubPath,
      accessToken: config.gatewayToken,
      deviceCode: config.deviceCode,
    );
    try {
      await _realtimeDs!.connect(
        onNewPendingSms: (_) {
          if (_disposed || !isRunning) return;
          _log(SmsLogEntry.info('🔔 Realtime trigger received'));
          unawaited(processPendingMessages());
        },
        onBatchRevoked: (_) {
          if (_disposed || !isRunning) return;
          _log(SmsLogEntry.warning('Batch revoked by backend'));
        },
        onStateChange: (state, detail) {
          if (_disposed) return;
          _realtimeState = state;
          _realtimeDetail = detail;
          // Log entry sẽ tự notify thông qua _log → _safeNotify. Ta chỉ cần
          // _safeNotify thêm cho case 'connecting' (không log).
          switch (state) {
            case RealtimeConnectionState.connected:
              _log(SmsLogEntry.success('Realtime connected'));
              break;
            case RealtimeConnectionState.reconnecting:
              _log(SmsLogEntry.warning(
                  'Realtime reconnecting${detail == null ? '' : ' · $detail'}'));
              break;
            case RealtimeConnectionState.disconnected:
              _log(SmsLogEntry.warning('Realtime disconnected'));
              break;
            case RealtimeConnectionState.failed:
              _log(SmsLogEntry.error(
                  'Realtime failed${detail == null ? '' : ' · $detail'}'));
              break;
            case RealtimeConnectionState.connecting:
              _safeNotify();
              break;
          }
        },
      );
    } catch (e) {
      // Realtime không khả dụng — log một dòng và tiếp tục với polling.
      _log(SmsLogEntry.warning(
          'Realtime unavailable — polling only. Reason: $e'));
      try {
        await _realtimeDs?.disconnect();
      } catch (_) {/* ignore */}
      _realtimeDs = null;
    }
  }

  /// Public stop — luôn kết thúc với status `stopped`.
  Future<void> stop() => _stopInternal(
        finalStatus: GatewayStatus.stopped,
        finalMessage: 'Gateway stopped',
        finalLogMessage: 'Gateway stopped',
      );

  /// Teardown nội bộ — cho phép caller chỉ định status cuối (ví dụ errored
  /// khi mất quyền SMS hoặc 401 từ backend). Đảm bảo log/status chỉ set
  /// **một lần** ở cuối, không bao giờ thấy log "Gateway stopped" rồi liền
  /// "Gateway errored" gây hiểu lầm.
  Future<void> _stopInternal({
    required GatewayStatus finalStatus,
    required String finalMessage,
    required String finalLogMessage,
  }) async {
    _timer?.cancel();
    _timer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _realtimeRetryTimer?.cancel();
    _realtimeRetryTimer = null;
    _isProcessing = false;
    _triggerWhileProcessing = false;
    _drainRounds = 0;
    _repository = null;
    _sendUsecase = null;
    _activeConfig = null;

    final rt = _realtimeDs;
    _realtimeDs = null;
    if (rt != null) {
      try {
        await rt.disconnect();
      } catch (_) {/* ignore */}
    }
    _realtimeState = RealtimeConnectionState.disconnected;
    _realtimeDetail = null;

    try {
      await nativeSmsSender.stopForegroundService();
    } catch (_) {/* ignore */}

    _setStatus(finalStatus, finalMessage);
    final level = finalStatus == GatewayStatus.errored
        ? SmsLogLevel.error
        : SmsLogLevel.info;
    _log(SmsLogEntry(
        timestamp: DateTime.now(), level: level, message: finalLogMessage));
  }

  Future<void> processPendingMessages() async {
    if (_disposed || !isRunning) return;
    if (_isProcessing) {
      // Có trigger tới khi đang chạy → đánh dấu để re-run đúng 1 lần ở finally,
      // không gọi đệ quy ngay (tránh stack growth).
      _triggerWhileProcessing = true;
      return;
    }
    final repository = _repository;
    final usecase = _sendUsecase;
    if (repository == null || usecase == null) return;

    // Lock _isProcessing TRƯỚC khi await permission → tránh race khi 2 caller
    // (timer + realtime trigger) cùng pass guard rồi cùng gọi stop().
    _isProcessing = true;
    _triggerWhileProcessing = false;

    try {
      // Per-tick guard: nếu user revoke quyền SEND_SMS giữa chừng, dừng hẳn
      // gateway thay vì burn retry count trên backend.
      if (!await permissionService.hasSmsPermission()) {
        await _stopInternal(
          finalStatus: GatewayStatus.errored,
          finalMessage:
              'SEND_SMS permission revoked. Please re-grant in system Settings.',
          finalLogMessage:
              'SEND_SMS permission revoked — gateway stopped to avoid burning retries',
        );
        return;
      }

      final messages =
          await repository.fetchPendingMessages(limit: _batchLimit);
      _lastPollAt = DateTime.now();
      if (messages.isEmpty) {
        _log(SmsLogEntry.info('No pending SMS'));
        _drainRounds = 0;
        return;
      }
      _log(SmsLogEntry.info('Fetched ${messages.length} pending SMS'));

      for (final sms in messages) {
        if (_disposed || !isRunning) return;
        await _processOne(sms, repository, usecase);
      }

      // Catch-up: nếu lấy đúng `_batchLimit` SMS VÀ chưa drain quá `_maxDrainRounds`
      // → có thể còn nữa trong queue, re-fetch để drain. Có cap để khỏi spin
      // khi backend liên tục bơm vào (timer / realtime sẽ tự gọi lại tiếp).
      if (messages.length == _batchLimit && _drainRounds < _maxDrainRounds) {
        _drainRounds++;
        _triggerWhileProcessing = true;
      } else {
        _drainRounds = 0;
      }
    } on NetworkException catch (e) {
      // 401/403 = auth failed (token bị revoke / sai). Polling tiếp sẽ chỉ
      // tốn battery và sinh log rác → set errored + stop.
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _stopInternal(
          finalStatus: GatewayStatus.errored,
          finalMessage:
              'Gateway token rejected by backend (HTTP ${e.statusCode}).',
          finalLogMessage:
              'Authentication failed (HTTP ${e.statusCode}). Check gateway token / device code.',
        );
        return;
      }
      _log(SmsLogEntry.error('Network error: ${e.message}'));
    } catch (e) {
      _log(SmsLogEntry.error('Polling error: $e'));
    } finally {
      _isProcessing = false;
      _safeNotify();

      // Drain mode: chỉ rerun nếu trigger thật sự arrived hoặc batch full chưa
      // hết cap. Kiểm tra _activeConfig != null (chưa bị _stopInternal nuke)
      // để chắc chắn gateway vẫn đang ở trạng thái sống.
      if (_triggerWhileProcessing &&
          !_disposed &&
          isRunning &&
          _activeConfig != null) {
        _triggerWhileProcessing = false;
        unawaited(processPendingMessages());
      }
    }
  }

  Future<void> _processOne(
    PendingSms sms,
    SmsGatewayRepository repository,
    SendSmsUsecase usecase,
  ) async {
    _log(SmsLogEntry.info('Sending SMS to ${sms.phoneNumber}', smsId: sms.id));
    try {
      await usecase(phoneNumber: sms.phoneNumber, message: sms.message);
      await repository.reportSent(sms.id);
      _sentCount++;
      _log(SmsLogEntry.success('Sent SMS id=${sms.id}', smsId: sms.id));
    } on NativeSendException catch (e) {
      _failedCount++;
      final reason = '${e.code}: ${e.message}';
      _log(SmsLogEntry.error('Failed: $reason', smsId: sms.id));
      await _safeReportFailed(repository, sms.id, reason);
    } catch (e) {
      _failedCount++;
      final reason = e.toString();
      _log(SmsLogEntry.error('Failed: $reason', smsId: sms.id));
      await _safeReportFailed(repository, sms.id, reason);
    }
  }

  Future<void> _safeReportFailed(
    SmsGatewayRepository repository,
    String smsId,
    String reason,
  ) async {
    try {
      await repository.reportFailed(smsId, reason);
    } catch (e) {
      _log(SmsLogEntry.warning('Could not report failure for $smsId: $e'));
    }
  }

  Future<void> _sendHeartbeat() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.heartbeat();
    } catch (_) {
      // Best-effort.
    }
  }

  // --- internals ---
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setStatus(GatewayStatus status, String message) {
    if (_disposed) return;
    _status = status;
    _statusMessage = message;
    _safeNotify();
  }

  void _log(SmsLogEntry entry) {
    if (_disposed) return;
    _logs.insert(0, entry);
    if (_logs.length > _maxLogs) {
      _logs.removeRange(_maxLogs, _logs.length);
    }
    _safeNotify();
  }

  void clearLogs() {
    if (_disposed) return;
    _logs.clear();
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    _realtimeRetryTimer?.cancel();
    final rt = _realtimeDs;
    _realtimeDs = null;
    if (rt != null) {
      // Fire-and-forget, không await trong dispose. Nhưng dùng unawaited để
      // không bị "unhandled async error" nếu stop() throw.
      unawaited(rt.disconnect().catchError((_) {/* ignore */}));
    }
    _repository = null;
    _sendUsecase = null;
    super.dispose();
  }
}
