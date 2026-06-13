import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_gateway_app/core/constants/storage_keys.dart';
import 'package:sms_gateway_app/core/storage/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('LocalStorageService.readConfig', () {
    test('returns defaults when nothing stored', () async {
      final svc = await LocalStorageService.create();
      final cfg = await svc.readConfig();
      expect(cfg.backendUrl, isEmpty);
      expect(cfg.gatewayToken, isEmpty);
      expect(cfg.autoStart, isFalse);
      expect(cfg.pollingIntervalSeconds, 10);
    });

    test('auto-generates a deviceCode on first read', () async {
      final svc = await LocalStorageService.create();
      final cfg = await svc.readConfig();
      expect(cfg.deviceCode, startsWith('android-'));
      // Đọc lần 2 → deviceCode phải ổn định (persisted)
      final cfg2 = await svc.readConfig();
      expect(cfg2.deviceCode, cfg.deviceCode);
    });

    test('returns saved values', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.backendUrl: 'https://x.test',
        StorageKeys.gatewayToken: 'tok-abc',
        StorageKeys.deviceCode: 'device-xyz',
        StorageKeys.autoStart: true,
        StorageKeys.pollingIntervalSeconds: 30,
      });
      final svc = await LocalStorageService.create();
      final cfg = await svc.readConfig();
      expect(cfg.backendUrl, 'https://x.test');
      expect(cfg.gatewayToken, 'tok-abc');
      expect(cfg.deviceCode, 'device-xyz');
      expect(cfg.autoStart, isTrue);
      expect(cfg.pollingIntervalSeconds, 30);
    });
  });

  group('LocalStorageService.saveConfig', () {
    test('persists and roundtrips', () async {
      final svc = await LocalStorageService.create();
      await svc.saveConfig(const GatewayConfig(
        backendUrl: 'https://saved.test ',
        gatewayToken: ' token-1 ',
        deviceCode: 'dev-1',
        autoStart: true,
        pollingIntervalSeconds: 45,
      ));
      final cfg = await svc.readConfig();
      expect(cfg.backendUrl, 'https://saved.test'); // trimmed
      expect(cfg.gatewayToken, 'token-1'); // trimmed
      expect(cfg.deviceCode, 'dev-1');
      expect(cfg.autoStart, isTrue);
      expect(cfg.pollingIntervalSeconds, 45);
    });
  });

  group('GatewayConfig', () {
    test('isComplete checks all 3 fields non-empty', () {
      expect(
          const GatewayConfig(
              backendUrl: 'u',
              gatewayToken: 't',
              deviceCode: 'd',
              autoStart: false,
              pollingIntervalSeconds: 10).isComplete,
          isTrue);
      expect(
          const GatewayConfig(
              backendUrl: '',
              gatewayToken: 't',
              deviceCode: 'd',
              autoStart: false,
              pollingIntervalSeconds: 10).isComplete,
          isFalse);
    });

    test('copyWith overrides selected fields', () {
      const base = GatewayConfig(
          backendUrl: 'u',
          gatewayToken: 't',
          deviceCode: 'd',
          autoStart: false,
          pollingIntervalSeconds: 10);
      final copy = base.copyWith(backendUrl: 'u2', autoStart: true);
      expect(copy.backendUrl, 'u2');
      expect(copy.gatewayToken, 't');
      expect(copy.autoStart, isTrue);
      expect(copy.pollingIntervalSeconds, 10);
    });
  });

  group('LocalStorageService.clear', () {
    test('removes URL/token/auto-start but preserves deviceCode', () async {
      final svc = await LocalStorageService.create();
      await svc.saveConfig(const GatewayConfig(
        backendUrl: 'u',
        gatewayToken: 't',
        deviceCode: 'dev-keep',
        autoStart: true,
        pollingIntervalSeconds: 60,
      ));
      await svc.clear();
      final cfg = await svc.readConfig();
      expect(cfg.backendUrl, isEmpty);
      expect(cfg.gatewayToken, isEmpty);
      expect(cfg.deviceCode, 'dev-keep');
      expect(cfg.autoStart, isFalse);
    });
  });

  group('LocalStorageService.saveConfig — edge cases', () {
    test('trims trailing whitespace from URL + token', () async {
      final svc = await LocalStorageService.create();
      await svc.saveConfig(const GatewayConfig(
        backendUrl: '  https://x.test  ',
        gatewayToken: '\ttok\t',
        deviceCode: 'd',
        autoStart: false,
        pollingIntervalSeconds: 10,
      ));
      final cfg = await svc.readConfig();
      expect(cfg.backendUrl, 'https://x.test');
      expect(cfg.gatewayToken, 'tok');
    });

    test('preserves special chars in deviceCode (UUID with dashes)', () async {
      final svc = await LocalStorageService.create();
      await svc.saveConfig(const GatewayConfig(
        backendUrl: 'u',
        gatewayToken: 't',
        deviceCode: 'android-abc-1234-DEF',
        autoStart: false,
        pollingIntervalSeconds: 10,
      ));
      final cfg = await svc.readConfig();
      expect(cfg.deviceCode, 'android-abc-1234-DEF');
    });

    test('writes and overwrites multiple times', () async {
      final svc = await LocalStorageService.create();
      await svc.saveConfig(const GatewayConfig(
        backendUrl: 'a',
        gatewayToken: 't',
        deviceCode: 'd',
        autoStart: false,
        pollingIntervalSeconds: 10,
      ));
      await svc.saveConfig(const GatewayConfig(
        backendUrl: 'b',
        gatewayToken: 't2',
        deviceCode: 'd',
        autoStart: true,
        pollingIntervalSeconds: 20,
      ));
      final cfg = await svc.readConfig();
      expect(cfg.backendUrl, 'b');
      expect(cfg.gatewayToken, 't2');
      expect(cfg.autoStart, isTrue);
      expect(cfg.pollingIntervalSeconds, 20);
    });

    test('persists negative polling interval value as-is (validator at UI)',
        () async {
      final svc = await LocalStorageService.create();
      await svc.saveConfig(const GatewayConfig(
        backendUrl: 'u',
        gatewayToken: 't',
        deviceCode: 'd',
        autoStart: false,
        pollingIntervalSeconds: -5,
      ));
      final cfg = await svc.readConfig();
      // Storage không validate; clamp xảy ra ở SmsGatewayController.
      expect(cfg.pollingIntervalSeconds, -5);
    });

    test('large polling interval (1 day) persists', () async {
      final svc = await LocalStorageService.create();
      await svc.saveConfig(const GatewayConfig(
        backendUrl: 'u',
        gatewayToken: 't',
        deviceCode: 'd',
        autoStart: false,
        pollingIntervalSeconds: 86400,
      ));
      final cfg = await svc.readConfig();
      expect(cfg.pollingIntervalSeconds, 86400);
    });
  });

  group('GatewayConfig.copyWith — edge cases', () {
    test('copyWith with no params returns equal config', () {
      const base = GatewayConfig(
          backendUrl: 'u',
          gatewayToken: 't',
          deviceCode: 'd',
          autoStart: false,
          pollingIntervalSeconds: 10);
      final copy = base.copyWith();
      expect(copy.backendUrl, base.backendUrl);
      expect(copy.gatewayToken, base.gatewayToken);
      expect(copy.deviceCode, base.deviceCode);
      expect(copy.autoStart, base.autoStart);
      expect(copy.pollingIntervalSeconds, base.pollingIntervalSeconds);
    });

    test('copyWith all fields at once', () {
      const base = GatewayConfig(
          backendUrl: 'u',
          gatewayToken: 't',
          deviceCode: 'd',
          autoStart: false,
          pollingIntervalSeconds: 10);
      final copy = base.copyWith(
        backendUrl: 'u2',
        gatewayToken: 't2',
        deviceCode: 'd2',
        autoStart: true,
        pollingIntervalSeconds: 99,
      );
      expect(copy.backendUrl, 'u2');
      expect(copy.gatewayToken, 't2');
      expect(copy.deviceCode, 'd2');
      expect(copy.autoStart, isTrue);
      expect(copy.pollingIntervalSeconds, 99);
    });

    test('isComplete: only one field empty → false', () {
      // backend empty
      expect(
          const GatewayConfig(
              backendUrl: '',
              gatewayToken: 't',
              deviceCode: 'd',
              autoStart: false,
              pollingIntervalSeconds: 10).isComplete,
          isFalse);
      // token empty
      expect(
          const GatewayConfig(
              backendUrl: 'u',
              gatewayToken: '',
              deviceCode: 'd',
              autoStart: false,
              pollingIntervalSeconds: 10).isComplete,
          isFalse);
      // deviceCode empty
      expect(
          const GatewayConfig(
              backendUrl: 'u',
              gatewayToken: 't',
              deviceCode: '',
              autoStart: false,
              pollingIntervalSeconds: 10).isComplete,
          isFalse);
    });
  });
}
