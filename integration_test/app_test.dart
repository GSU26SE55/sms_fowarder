import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_gateway_app/app.dart';
import 'package:sms_gateway_app/core/constants/storage_keys.dart';
import 'package:sms_gateway_app/core/storage/local_storage_service.dart';

/// Integration test — chạy trên thiết bị thật hoặc emulator:
///
///   flutter test integration_test/app_test.dart
///
/// Đây là end-to-end smoke test cho user flow chính: launch app, thấy
/// welcome state khi chưa config, mở Settings, điền form, save, quay về Home,
/// thấy nút Start gateway.
///
/// Test KHÔNG thực sự bấm Start gateway vì sẽ cần backend chạy thật. Phần
/// đó nên chạy bằng tay theo TESTING.md.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches and shows welcome state when no config',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorageService.create();

    await tester.pumpWidget(SmsGatewayApp(storageService: storage));
    await tester.pumpAndSettle();

    expect(find.text('SMS Gateway'), findsWidgets);
    expect(find.textContaining('Welcome'), findsOneWidget);
    expect(find.text('Configure now'), findsOneWidget);
  });

  testWidgets('settings → save → back to home shows running stats panel',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.backendUrl: 'https://api.test.local',
      StorageKeys.gatewayToken: 'token-1',
      StorageKeys.deviceCode: 'device-1',
      StorageKeys.pollingIntervalSeconds: 10,
    });
    final storage = await LocalStorageService.create();

    await tester.pumpWidget(SmsGatewayApp(storageService: storage));
    await tester.pumpAndSettle();

    expect(find.text('Start gateway'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);

    // Open Settings, change interval, save.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Backend'), findsOneWidget);

    final intervalField = find.byType(TextFormField).at(3);
    await tester.enterText(intervalField, '30');
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();

    // Back on Home, can see stats again.
    expect(find.text('Sent'), findsOneWidget);
  });
}
