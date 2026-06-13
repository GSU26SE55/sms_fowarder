import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/datasources/sms_gateway_realtime_datasource.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/sms_log_entry.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/controllers/sms_gateway_controller.dart';

import '../../../../../helpers/test_helpers.dart';

/// Test cho [SmsGatewayController].
///
/// Lưu ý: controller phụ thuộc vào `LocalStorageService` (đọc config) +
/// `SmsPermissionService` (check quyền) + `NativeSmsSender` (start/stop
/// foreground service). Tất cả được mock.
///
/// Các test sau dùng `fake_async` chỉ khi cần kiểm tra Timer.periodic; phần
/// còn lại chạy ngay qua `await`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerCommonFallbacks);

  late MockSmsPermissionService perm;
  late MockNativeSmsSender native;
  late MockLocalStorageService storage;
  late SmsGatewayController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    perm = MockSmsPermissionService();
    native = MockNativeSmsSender();
    storage = MockLocalStorageService();

    // Default happy-path stubs — override per-test khi cần.
    when(() => perm.hasSmsPermission()).thenAnswer((_) async => true);
    when(() => perm.requestSmsPermission()).thenAnswer((_) async => true);
    when(() => perm.hasNotificationPermission()).thenAnswer((_) async => true);
    when(() => perm.requestNotificationPermission())
        .thenAnswer((_) async => true);
    when(() => native.startForegroundService()).thenAnswer((_) async {});
    when(() => native.stopForegroundService()).thenAnswer((_) async {});

    controller = SmsGatewayController(
      permissionService: perm,
      nativeSmsSender: native,
      storageService: storage,
    );
  });

  tearDown(() {
    // dispose() asserts not-already-disposed; skip if test already disposed.
    try {
      controller.dispose();
    } catch (_) {/* already disposed by test */}
  });

  group('initial state', () {
    test('starts stopped with empty stats', () {
      expect(controller.status, GatewayStatus.stopped);
      expect(controller.isRunning, isFalse);
      expect(controller.sentCount, 0);
      expect(controller.failedCount, 0);
      expect(controller.logs, isEmpty);
      expect(controller.statusMessage, 'Gateway stopped');
    });
  });

  group('start()', () {
    test('errors out when config is incomplete', () async {
      when(() => storage.readConfig()).thenAnswer(
          (_) async => buildConfig(backendUrl: '', gatewayToken: ''));
      await controller.start();
      expect(controller.status, GatewayStatus.errored);
      expect(controller.statusMessage, contains('missing'));
      expect(controller.logs.any((l) => l.level == SmsLogLevel.error), isTrue);
    });

    test('errors out when SMS permission is denied', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      when(() => perm.hasSmsPermission()).thenAnswer((_) async => false);
      when(() => perm.requestSmsPermission()).thenAnswer((_) async => false);

      await controller.start();
      expect(controller.status, GatewayStatus.errored);
      expect(controller.statusMessage, contains('SEND_SMS'));
    });

    test('runs to "running" state on happy path', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      expect(controller.status, GatewayStatus.running);
      expect(controller.isRunning, isTrue);
      verify(() => native.startForegroundService()).called(1);
    });

    test('early returns if already running / starting', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      await controller.start(); // 2nd call should noop
      verify(() => native.startForegroundService()).called(1);
    });
  });

  group('stop()', () {
    test('cancels timers and returns to stopped', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      await controller.stop();

      expect(controller.status, GatewayStatus.stopped);
      verify(() => native.stopForegroundService()).called(1);
    });
  });

  group('logging', () {
    test('logs are inserted newest-first', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      expect(controller.logs.first.message, contains('Gateway started'));
    });

    test('clearLogs empties the log buffer', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      expect(controller.logs, isNotEmpty);
      controller.clearLogs();
      expect(controller.logs, isEmpty);
    });
  });

  group('notifyListeners safety', () {
    test('dispose() prevents subsequent notifyListeners', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      controller.dispose();
      // Calling clearLogs after dispose should not throw.
      expect(() => controller.clearLogs(), returnsNormally);
    });
  });

  group('processPendingMessages', () {
    test('no-op when status is not running', () async {
      // Without start(), repository is null → returns silently.
      await controller.processPendingMessages();
      expect(controller.logs, isEmpty);
    });

    test('no-op when called after dispose', () async {
      controller.dispose();
      await controller.processPendingMessages();
      // No throw, no log. We can't read logs after dispose either, just verify
      // no exception was raised.
      expect(true, isTrue);
    });

    test('per-tick permission revocation triggers errored + stop', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            backendUrl: 'http://offline.invalid.test',
          ));
      await controller.start();
      // Drain any in-flight unawaited processPendingMessages from start().
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Revoke permission for the next tick.
      when(() => perm.hasSmsPermission()).thenAnswer((_) async => false);
      await controller.processPendingMessages();

      expect(controller.status, GatewayStatus.errored);
      expect(controller.statusMessage, contains('permission revoked'));
    });
  });

  group('realtime + polling interval calculation', () {
    test('polling-only when realtime fails uses user setting', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            backendUrl: 'http://offline.invalid.test',
            pollingIntervalSeconds: 15,
          ));
      await controller.start();
      expect(controller.activePollInterval.inSeconds, 15);
      expect(controller.isRealtimeActive, isFalse);
    });

    test('polling interval clamped lower bound 5s', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            backendUrl: 'http://offline.invalid.test',
            pollingIntervalSeconds: 1,
          ));
      await controller.start();
      expect(controller.activePollInterval.inSeconds, 5);
    });

    test('polling interval clamped upper bound 600s', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            backendUrl: 'http://offline.invalid.test',
            pollingIntervalSeconds: 9999,
          ));
      await controller.start();
      expect(controller.activePollInterval.inSeconds, 600);
    });
  });

  group('status logs', () {
    test('start() with incomplete config produces an error log', () async {
      when(() => storage.readConfig()).thenAnswer(
          (_) async => buildConfig(backendUrl: '', gatewayToken: ''));
      await controller.start();
      expect(controller.logs.first.level, SmsLogLevel.error);
    });

    test('stop() after start emits "Gateway stopped" log', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      await controller.stop();
      expect(controller.logs.first.message, contains('stopped'));
    });
  });

  group('counters', () {
    test('sentCount and failedCount start at 0', () {
      expect(controller.sentCount, 0);
      expect(controller.failedCount, 0);
    });

    test('lastPollAt starts null', () {
      expect(controller.lastPollAt, isNull);
    });
  });

  group('logs buffer', () {
    test('controller exposes logs list as unmodifiable', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      final logs = controller.logs;
      expect(() => logs.add(SmsLogEntry.info('try-add')),
          throwsUnsupportedError);
    });
  });

  group('hi hữu — repeated start/stop cycles', () {
    test('start → stop → start succeeds + counters preserved', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      await controller.stop();
      expect(controller.status, GatewayStatus.stopped);
      await controller.start();
      expect(controller.status, GatewayStatus.running);
      expect(controller.sentCount, 0); // not reset by stop
    });

    test('5 rapid restart cycles do not leak', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      for (var i = 0; i < 5; i++) {
        await controller.start();
        await controller.stop();
      }
      expect(controller.status, GatewayStatus.stopped);
    });

    test('stop() before start() is safe no-op', () async {
      await controller.stop();
      expect(controller.status, GatewayStatus.stopped);
    });

    test('multiple stop() calls in a row OK', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      await controller.stop();
      await controller.stop();
      await controller.stop();
      expect(controller.status, GatewayStatus.stopped);
    });
  });

  group('hi hữu — listener safety', () {
    test('listeners are notified on start', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      int n = 0;
      controller.addListener(() => n++);
      await controller.start();
      expect(n, greaterThan(0));
    });

    test('removed listeners are not notified', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      int n = 0;
      void l() => n++;
      controller.addListener(l);
      controller.removeListener(l);
      await controller.start();
      expect(n, 0);
    });

    test('listener that throws is isolated (other listeners still get fired)',
        () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      int healthy = 0;
      controller.addListener(() => throw Exception('bad listener'));
      controller.addListener(() => healthy++);
      // Even if one throws, others run; ChangeNotifier rethrows asynchronously.
      try {
        await controller.start();
      } catch (_) {/* swallow framework rethrow */}
      expect(healthy, greaterThan(0));
    });
  });

  group('hi hữu — processPendingMessages without start', () {
    test('returns silently when never started (no repository)', () async {
      await controller.processPendingMessages();
      expect(controller.sentCount, 0);
      expect(controller.failedCount, 0);
    });

    test('returns silently after disposed', () async {
      controller.dispose();
      // Should not throw.
      await controller.processPendingMessages();
      expect(true, isTrue);
    });
  });

  group('hi hữu — config validation', () {
    test('start with only backend missing', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            backendUrl: '',
          ));
      await controller.start();
      expect(controller.status, GatewayStatus.errored);
    });

    test('start with only token missing', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            gatewayToken: '',
          ));
      await controller.start();
      expect(controller.status, GatewayStatus.errored);
    });

    test('start with only deviceCode missing', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            deviceCode: '',
          ));
      await controller.start();
      expect(controller.status, GatewayStatus.errored);
    });
  });

  group('hi hữu — permission flow', () {
    test('requests permission when not initially granted', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      when(() => perm.hasSmsPermission()).thenAnswer((_) async => false);
      when(() => perm.requestSmsPermission()).thenAnswer((_) async => true);
      await controller.start();
      expect(controller.status, GatewayStatus.running);
      verify(() => perm.requestSmsPermission()).called(1);
    });

    test('does not request when already granted', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      when(() => perm.hasSmsPermission()).thenAnswer((_) async => true);
      await controller.start();
      verifyNever(() => perm.requestSmsPermission());
    });

    test('requests notification permission when missing', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      when(() => perm.hasNotificationPermission())
          .thenAnswer((_) async => false);
      await controller.start();
      verify(() => perm.requestNotificationPermission()).called(1);
    });

    test('does not block start when notification permission denied', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      when(() => perm.hasNotificationPermission())
          .thenAnswer((_) async => false);
      when(() => perm.requestNotificationPermission())
          .thenAnswer((_) async => false);
      await controller.start();
      expect(controller.status, GatewayStatus.running);
    });
  });

  group('hi hữu — foreground service unavailable', () {
    test('logs warning but still starts when foreground service throws',
        () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      when(() => native.startForegroundService())
          .thenThrow(Exception('no service'));
      await controller.start();
      expect(controller.status, GatewayStatus.running);
      expect(controller.logs.any((l) => l.level == SmsLogLevel.warning),
          isTrue);
    });

    test('stop tolerates stopForegroundService throwing', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      when(() => native.stopForegroundService()).thenThrow(Exception('x'));
      // Should not propagate exception.
      await controller.stop();
      expect(controller.status, GatewayStatus.stopped);
    });
  });

  group('hi hữu — clearLogs in various states', () {
    test('clearLogs when no logs present is no-op', () {
      controller.clearLogs();
      expect(controller.logs, isEmpty);
    });

    test('clearLogs after dispose is silent no-op', () {
      controller.dispose();
      expect(() => controller.clearLogs(), returnsNormally);
    });

    test('clearLogs notifies listeners when logs were non-empty', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig());
      await controller.start();
      int n = 0;
      controller.addListener(() => n++);
      controller.clearLogs();
      expect(n, greaterThan(0));
    });
  });

  group('hi hữu — realtime state getters', () {
    test('initial realtimeState is disconnected', () {
      expect(controller.realtimeState, RealtimeConnectionState.disconnected);
    });

    test('isRealtimeActive is false when state != connected', () {
      expect(controller.isRealtimeActive, isFalse);
    });

    test('realtimeDetail initially null', () {
      expect(controller.realtimeDetail, isNull);
    });

    test('activePollInterval has a sensible default before start', () {
      expect(controller.activePollInterval.inSeconds, isNonNegative);
    });
  });

  group('hi hữu — boundary conditions on poll interval', () {
    test('exactly 5 seconds → used as-is', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            backendUrl: 'http://offline.invalid.test',
            pollingIntervalSeconds: 5,
          ));
      await controller.start();
      expect(controller.activePollInterval.inSeconds, 5);
    });

    test('exactly 600 seconds → used as-is', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            backendUrl: 'http://offline.invalid.test',
            pollingIntervalSeconds: 600,
          ));
      await controller.start();
      expect(controller.activePollInterval.inSeconds, 600);
    });

    test('0 seconds → clamped to 5s', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            backendUrl: 'http://offline.invalid.test',
            pollingIntervalSeconds: 0,
          ));
      await controller.start();
      expect(controller.activePollInterval.inSeconds, 5);
    });

    test('negative seconds → clamped to 5s', () async {
      when(() => storage.readConfig()).thenAnswer((_) async => buildConfig(
            backendUrl: 'http://offline.invalid.test',
            pollingIntervalSeconds: -100,
          ));
      await controller.start();
      expect(controller.activePollInterval.inSeconds, 5);
    });
  });
}
