import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:sms_gateway_app/core/permissions/sms_permission_service.dart';
import 'package:sms_gateway_app/core/storage/local_storage_service.dart';
import 'package:sms_gateway_app/core/theme/app_theme.dart';
import 'package:sms_gateway_app/features/sms_gateway/data/datasources/sms_gateway_remote_datasource.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/pending_sms.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/sms_log_entry.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/repositories/sms_gateway_repository.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/usecases/send_sms_usecase.dart';
import 'package:sms_gateway_app/features/sms_gateway/native/native_sms_sender.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/controllers/gateway_settings_controller.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/controllers/sms_gateway_controller.dart';

/// =====================================================================
///  Mock classes (mocktail) — declare once, reuse across tests.
/// =====================================================================
class MockSmsPermissionService extends Mock implements SmsPermissionService {}

class MockNativeSmsSender extends Mock implements NativeSmsSender {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockSmsGatewayRepository extends Mock implements SmsGatewayRepository {}

class MockSmsGatewayRemoteDatasource extends Mock
    implements SmsGatewayRemoteDatasource {}

class MockSendSmsUsecase extends Mock implements SendSmsUsecase {}

class MockSmsGatewayController extends Mock implements SmsGatewayController {}

class MockGatewaySettingsController extends Mock
    implements GatewaySettingsController {}

/// Helper: register fallback values cho mocktail. Gọi 1 lần ở `main()` test.
void registerCommonFallbacks() {
  registerFallbackValue(const GatewayConfig(
    backendUrl: '',
    gatewayToken: '',
    deviceCode: '',
    autoStart: false,
    pollingIntervalSeconds: 10,
  ));
  registerFallbackValue(
      SmsLogEntry.info('fallback', smsId: 'fallback-sms-id'));
  registerFallbackValue(const PendingSms(
    id: 'fallback',
    phoneNumber: '+84900000000',
    message: 'fallback',
  ));
}

/// Helper: build [GatewayConfig] với defaults nhanh, override field cần.
GatewayConfig buildConfig({
  String backendUrl = 'https://api.test.local',
  String gatewayToken = 'test-token',
  String deviceCode = 'test-device-001',
  bool autoStart = false,
  int pollingIntervalSeconds = 10,
}) =>
    GatewayConfig(
      backendUrl: backendUrl,
      gatewayToken: gatewayToken,
      deviceCode: deviceCode,
      autoStart: autoStart,
      pollingIntervalSeconds: pollingIntervalSeconds,
    );

/// Helper: build [PendingSms] nhanh.
PendingSms buildPendingSms({
  String id = 'sms-001',
  String phoneNumber = '+84901234567',
  String message = 'hello',
}) =>
    PendingSms(id: id, phoneNumber: phoneNumber, message: message);

/// Wrap widget với MaterialApp + theme cho widget test (đỡ phải lặp).
///
/// `TickerMode.enabled=false` để tắt animation tickers — tránh "Looking up
/// deactivated widget's ancestor" khi test framework finalize tree với
/// pending animations (vd AnimatedStatusDot pulsing forever).
Widget wrapWithApp(Widget child,
    {ThemeData? theme, NavigatorObserver? navigatorObserver}) {
  return MaterialApp(
    theme: theme ?? AppTheme.light(),
    home: Scaffold(
      body: TickerMode(enabled: false, child: child),
    ),
    navigatorObservers:
        navigatorObserver == null ? const [] : [navigatorObserver],
  );
}

/// Wrap widget với MultiProvider để test page cần ChangeNotifier providers.
Widget wrapWithProviders(
  Widget child, {
  SmsGatewayController? smsCtrl,
  GatewaySettingsController? settingsCtrl,
  SmsPermissionService? perm,
  NativeSmsSender? native,
  LocalStorageService? storage,
  ThemeData? theme,
}) {
  return MultiProvider(
    providers: [
      if (perm != null) Provider<SmsPermissionService>.value(value: perm),
      if (native != null) Provider<NativeSmsSender>.value(value: native),
      if (storage != null) Provider<LocalStorageService>.value(value: storage),
      if (settingsCtrl != null)
        ChangeNotifierProvider<GatewaySettingsController>.value(
            value: settingsCtrl),
      if (smsCtrl != null)
        ChangeNotifierProvider<SmsGatewayController>.value(value: smsCtrl),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(
        body: TickerMode(enabled: false, child: child),
      ),
    ),
  );
}

/// Tick mọi animation + microtask cho [tester] tới khi UI ổn định.
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
}
