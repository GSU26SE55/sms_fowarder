import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/controllers/gateway_settings_controller.dart';

import '../../../../../helpers/test_helpers.dart';

void main() {
  setUpAll(registerCommonFallbacks);

  late MockLocalStorageService storage;
  late GatewaySettingsController controller;

  setUp(() {
    storage = MockLocalStorageService();
    controller = GatewaySettingsController(storage);
  });

  test('starts with empty config', () {
    expect(controller.config.backendUrl, isEmpty);
    expect(controller.config.isComplete, isFalse);
  });

  test('load() pulls config from storage and notifies listeners', () async {
    final cfg = buildConfig(backendUrl: 'https://b.test');
    when(() => storage.readConfig()).thenAnswer((_) async => cfg);

    int notified = 0;
    controller.addListener(() => notified++);

    await controller.load();

    expect(controller.config.backendUrl, 'https://b.test');
    expect(notified, 1);
    verify(() => storage.readConfig()).called(1);
  });

  test('save() writes to storage and notifies listeners', () async {
    when(() => storage.saveConfig(any())).thenAnswer((_) async {});

    int notified = 0;
    controller.addListener(() => notified++);

    final newCfg = buildConfig(backendUrl: 'https://new.test');
    await controller.save(newCfg);

    expect(controller.config.backendUrl, 'https://new.test');
    expect(notified, 1);
    verify(() => storage.saveConfig(newCfg)).called(1);
  });
}
