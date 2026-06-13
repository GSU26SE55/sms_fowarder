import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sms_gateway_app/core/storage/local_storage_service.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/pages/gateway_settings_page.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  setUpAll(registerCommonFallbacks);

  late MockGatewaySettingsController settings;
  late MockSmsGatewayController gw;

  setUp(() {
    settings = MockGatewaySettingsController();
    gw = MockSmsGatewayController();
    when(() => settings.config).thenReturn(buildConfig(
      backendUrl: 'https://api.test',
      gatewayToken: 'tok',
      deviceCode: 'dev-1',
    ));
    when(() => gw.isRunning).thenReturn(false);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(wrapWithProviders(
      const GatewaySettingsPage(),
      smsCtrl: gw,
      settingsCtrl: settings,
    ));
    await tester.pump();
  }

  testWidgets('renders 3 sections', (tester) async {
    await pump(tester);
    expect(find.text('Backend'), findsOneWidget);
    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Behavior'), findsOneWidget);
  });

  testWidgets('URL validator rejects invalid URL on text entry', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField).first, 'not-a-url');
    await tester.pump();
    expect(find.textContaining('Invalid URL'), findsOneWidget);
  });

  testWidgets('URL validator rejects URL with path', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byType(TextFormField).first, 'https://api.example.com/api');
    await tester.pump();
    expect(find.textContaining('Remove path'), findsOneWidget);
  });

  testWidgets('URL validator rejects URL with query', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byType(TextFormField).first, 'https://x.com?foo=1');
    await tester.pump();
    expect(find.textContaining('Remove ? and #'), findsOneWidget);
  });

  testWidgets('URL validator accepts http scheme', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byType(TextFormField).first, 'http://192.168.1.10:5001');
    await tester.pump();
    expect(find.textContaining('Invalid URL'), findsNothing);
    expect(find.textContaining('Must start'), findsNothing);
  });

  testWidgets('URL validator rejects ftp scheme', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byType(TextFormField).first, 'ftp://files.test');
    await tester.pump();
    expect(find.textContaining('Must start with http'), findsOneWidget);
  });

  testWidgets('Token field shows obscured by default', (tester) async {
    await pump(tester);
    // TextFormField doesn't expose obscureText; check via the EditableText
    // nested widget instead.
    final tokenEditable = tester.widgetList<EditableText>(
        find.descendant(
          of: find.byType(TextFormField).at(1),
          matching: find.byType(EditableText),
        )).first;
    expect(tokenEditable.obscureText, isTrue);
  });

  testWidgets('Token eye icon toggles visibility', (tester) async {
    await pump(tester);
    // Initially shown obscured: eye icon is "visibility" (off).
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    // After toggle: shows "visibility_off" icon.
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('Save with valid form calls save()', (tester) async {
    when(() => settings.save(any())).thenAnswer((_) async {});
    await pump(tester);

    // Scroll until Save button is visible.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    await tester.tap(find.text('Save settings'));
    await tester.pump();

    final captured =
        verify(() => settings.save(captureAny())).captured.single
            as GatewayConfig;
    expect(captured.backendUrl, 'https://api.test');
    expect(captured.gatewayToken, 'tok');
    expect(captured.deviceCode, 'dev-1');
  });

  testWidgets('Auto start switch toggles state', (tester) async {
    await pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    final initial = tester.widget<Switch>(switchFinder).value;
    await tester.tap(switchFinder);
    await tester.pump();
    final toggled = tester.widget<Switch>(switchFinder).value;
    expect(toggled, !initial);
  });
}

