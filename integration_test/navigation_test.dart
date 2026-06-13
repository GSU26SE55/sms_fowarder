import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_gateway_app/app.dart';
import 'package:sms_gateway_app/core/constants/storage_keys.dart';
import 'package:sms_gateway_app/core/storage/local_storage_service.dart';

/// Navigation flows test:
///
///   flutter test integration_test/navigation_test.dart
///
/// Tests navigate giữa các page chính: Home ↔ Logs, Home ↔ Settings.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> bootApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.backendUrl: 'https://api.test.local',
      StorageKeys.gatewayToken: 'token-1',
      StorageKeys.deviceCode: 'device-1',
      StorageKeys.pollingIntervalSeconds: 10,
    });
    final storage = await LocalStorageService.create();
    await tester.pumpWidget(SmsGatewayApp(storageService: storage));
    await tester.pumpAndSettle();
  }

  testWidgets('Home → Logs → back to Home', (tester) async {
    await bootApp(tester);

    expect(find.text('Start gateway'), findsOneWidget);

    // Tap logs icon.
    await tester.tap(find.byTooltip('Logs'));
    await tester.pumpAndSettle();

    expect(find.text('Activity logs'), findsOneWidget);

    // Back to home.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Start gateway'), findsOneWidget);
  });

  testWidgets('Home → Settings → cancel back', (tester) async {
    await bootApp(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Backend'), findsOneWidget);
    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Behavior'), findsOneWidget);

    // Cancel via back button.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Start gateway'), findsOneWidget);
  });

  testWidgets('Empty config → Welcome → Configure now → Settings page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorageService.create();
    await tester.pumpWidget(SmsGatewayApp(storageService: storage));
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome'), findsOneWidget);
    await tester.tap(find.text('Configure now'));
    await tester.pumpAndSettle();
    expect(find.text('Backend'), findsOneWidget);
  });
}
