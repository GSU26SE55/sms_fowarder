import 'dart:async';

import 'package:signalr_netcore/signalr_client.dart';

/// Trạng thái kết nối SignalR ở mức ứng dụng — đơn giản hơn enum gốc của package.
enum RealtimeConnectionState {
  /// Chưa từng connect hoặc đã stop() chủ động.
  disconnected,

  /// Đang gọi `start()` lần đầu.
  connecting,

  /// Đã connect, đang nhận event realtime.
  connected,

  /// Bị disconnect ngoài ý muốn, package đang tự reconnect.
  reconnecting,

  /// Hub không khả dụng (backend chưa expose, sai URL, sai token, …) — caller
  /// sẽ rơi xuống polling-only.
  failed,
}

typedef RealtimeStateCallback = void Function(RealtimeConnectionState state, String? detail);
typedef RealtimePayloadCallback = void Function(Map<String, dynamic>? payload);

/// Wrapper cho [HubConnection] gắn với gateway `/hubs/sms-gateway`.
///
/// Trách nhiệm:
///  - Build [HubConnection] với access token (Bearer).
///  - Auto reconnect theo dãy [0, 2s, 5s, 10s, 30s].
///  - Forward 2 event server→client:
///    * `NewPendingSms` — backend báo có SMS mới được queue.
///    * `BatchRevoked`  — backend báo SMS đã bị admin huỷ (caller có thể clear local queue).
///  - Expose state machine để UI/log hiển thị.
///
/// **Không** chứa logic gọi `/pending` — chỉ "đánh thức" controller; controller
/// chủ động gọi REST như trước.
class SmsGatewayRealtimeDatasource {
  final String backendUrl;
  final String hubPath;
  final String accessToken;
  final String deviceCode;

  HubConnection? _connection;
  RealtimePayloadCallback? _onNewPendingSms;
  RealtimePayloadCallback? _onBatchRevoked;
  RealtimeStateCallback? _onStateChange;

  SmsGatewayRealtimeDatasource({
    required this.backendUrl,
    required this.hubPath,
    required this.accessToken,
    required this.deviceCode,
  });

  /// Kết nối Hub. Throw nếu thất bại — caller phải catch và fallback sang
  /// polling.
  ///
  /// `connectTimeout` giới hạn thời gian thử kết nối lần đầu để không block
  /// `start()` quá lâu khi backend không khả dụng.
  Future<void> connect({
    required RealtimePayloadCallback onNewPendingSms,
    required RealtimePayloadCallback onBatchRevoked,
    required RealtimeStateCallback onStateChange,
    Duration connectTimeout = const Duration(seconds: 8),
  }) async {
    _onNewPendingSms = onNewPendingSms;
    _onBatchRevoked = onBatchRevoked;
    _onStateChange = onStateChange;

    onStateChange(RealtimeConnectionState.connecting, null);

    // Backend mount Hub tại `${backendUrl}${hubPath}`. Device code đi qua
    // query để handler đọc được kể cả khi WebSocket không có header tuỳ chỉnh.
    final base = backendUrl.replaceAll(RegExp(r'/+$'), '');
    final url =
        '$base$hubPath?deviceCode=${Uri.encodeQueryComponent(deviceCode)}';

    _connection = HubConnectionBuilder()
        .withUrl(
          url,
          options: HttpConnectionOptions(
            accessTokenFactory: () async => accessToken,
            // Không skip negotiation → support cả WebSocket + Server-Sent Events
            // + Long Polling tuỳ điều kiện mạng.
          ),
        )
        .withAutomaticReconnect(
          retryDelays: [0, 2000, 5000, 10000, 30000],
        )
        .build();

    _connection!.on('NewPendingSms', _handleNewPendingSms);
    _connection!.on('BatchRevoked', _handleBatchRevoked);

    _connection!.onclose(({Exception? error}) {
      final msg = error?.toString();
      _emitState(RealtimeConnectionState.disconnected, msg);
    });

    _connection!.onreconnecting(({Exception? error}) {
      _emitState(RealtimeConnectionState.reconnecting, error?.toString());
    });

    _connection!.onreconnected(({String? connectionId}) {
      _emitState(RealtimeConnectionState.connected, 'reconnected · $connectionId');
      // Khi reconnect, có thể đã miss vài event lúc offline → gọi
      // onNewPendingSms để controller chủ động poll một lần cho chắc.
      _onNewPendingSms?.call(null);
    });

    try {
      final startFuture = _connection!.start();
      if (startFuture == null) {
        throw StateError(
            'HubConnection.start() returned null — connection is in unexpected state');
      }
      await startFuture.timeout(connectTimeout);
      _emitState(RealtimeConnectionState.connected, null);
    } catch (e) {
      _emitState(RealtimeConnectionState.failed, e.toString());
      // Dọn dẹp connection nửa vời để không leak.
      try {
        await _connection?.stop();
      } catch (_) {/* ignore */}
      _connection = null;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    // Null callbacks TRƯỚC khi gọi stop() để:
    //  1. Không double-emit khi onclose của package fire.
    //  2. Không log "Realtime reconnecting/trigger" sau khi user đã Stop.
    _onNewPendingSms = null;
    _onBatchRevoked = null;
    final notifyState = _onStateChange;
    _onStateChange = null;

    final c = _connection;
    _connection = null;
    if (c != null) {
      try {
        await c.stop();
      } catch (_) {/* ignore */}
    }

    // Emit final state cho caller (controller) biết đã disconnect xong.
    notifyState?.call(RealtimeConnectionState.disconnected, 'stopped');
  }

  bool get isConnected =>
      _connection?.state == HubConnectionState.Connected;

  // --- internals ---

  void _handleNewPendingSms(List<Object?>? args) {
    final payload = _asMap(args);
    _onNewPendingSms?.call(payload);
  }

  void _handleBatchRevoked(List<Object?>? args) {
    final payload = _asMap(args);
    _onBatchRevoked?.call(payload);
  }

  void _emitState(RealtimeConnectionState state, String? detail) {
    _onStateChange?.call(state, detail);
  }

  Map<String, dynamic>? _asMap(List<Object?>? args) {
    if (args == null || args.isEmpty) return null;
    final first = args.first;
    if (first is Map<String, dynamic>) return first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
  }
}
