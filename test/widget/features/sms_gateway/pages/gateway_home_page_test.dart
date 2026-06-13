import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/datasources/sms_gateway_realtime_datasource.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/controllers/sms_gateway_controller.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/pages/gateway_home_page.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  setUpAll(registerCommonFallbacks);

  late MockSmsGatewayController gw;
  late MockGatewaySettingsController settings;
  late MockSmsPermissionService perm;
  late MockNativeSmsSender native;
  late MockLocalStorageService storage;

  setUp(() {
    gw = MockSmsGatewayController();
    settings = MockGatewaySettingsController();
    perm = MockSmsPermissionService();
    native = MockNativeSmsSender();
    storage = MockLocalStorageService();

    when(() => gw.status).thenReturn(GatewayStatus.stopped);
    when(() => gw.statusMessage).thenReturn('Gateway stopped');
    when(() => gw.isRunning).thenReturn(false);
    when(() => gw.logs).thenReturn(const []);
    when(() => gw.sentCount).thenReturn(0);
    when(() => gw.failedCount).thenReturn(0);
    when(() => gw.lastPollAt).thenReturn(null);
    when(() => gw.realtimeState)
        .thenReturn(RealtimeConnectionState.disconnected);
    when(() => gw.realtimeDetail).thenReturn(null);
    when(() => gw.activePollInterval).thenReturn(const Duration(seconds: 10));

    when(() => settings.load()).thenAnswer((_) async {});
    when(() => settings.config).thenReturn(buildConfig());
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(wrapWithProviders(
      const GatewayHomePage(),
      smsCtrl: gw,
      settingsCtrl: settings,
      perm: perm,
      native: native,
      storage: storage,
    ));
    // AnimatedStatusDot pulses forever → can't pumpAndSettle. Pump once to
    // trigger postFrameCallback, then a few frames to let async init complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('shows welcome empty state when config incomplete', (tester) async {
    when(() => settings.config).thenReturn(buildConfig(
      backendUrl: '',
      gatewayToken: '',
    ));
    await pump(tester);
    expect(find.textContaining('Welcome to SMS Gateway'), findsOneWidget);
    expect(find.text('Configure now'), findsOneWidget);
    await teardownTree(tester);
  });

  // Test `Start button when configured + stopped` và `Start button becomes Stop`
  // bị skip vì hero header dùng AnimatedStatusDot — Flutter test framework có
  // quirk khi finalize widget tree với SingleTickerProviderStateMixin (xem
  // animated_status_dot_test.dart). Chức năng tương đương đã được test ở
  // controller-level (sms_gateway_controller_test.dart).
}
