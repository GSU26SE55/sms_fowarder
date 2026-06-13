import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/sms_log_entry.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/pages/gateway_logs_page.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  setUpAll(registerCommonFallbacks);

  late MockSmsGatewayController ctrl;

  setUp(() {
    ctrl = MockSmsGatewayController();
  });

  testWidgets('shows empty state when no logs', (tester) async {
    when(() => ctrl.logs).thenReturn(const []);
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));
    expect(find.textContaining('No activity'), findsOneWidget);
  });

  testWidgets('renders log entries when not empty', (tester) async {
    when(() => ctrl.logs).thenReturn([
      SmsLogEntry.success('Sent A', smsId: 'a'),
      SmsLogEntry.error('Failed B', smsId: 'b'),
      SmsLogEntry.info('Polled'),
    ]);
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));
    expect(find.text('Sent A'), findsOneWidget);
    expect(find.text('Failed B'), findsOneWidget);
    expect(find.text('Polled'), findsOneWidget);
  });

  testWidgets('filter chip "Sent" reduces to success entries only',
      (tester) async {
    when(() => ctrl.logs).thenReturn([
      SmsLogEntry.success('Sent A'),
      SmsLogEntry.error('Failed B'),
    ]);
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));

    await tester.tap(find.text('Sent'));
    await tester.pump();

    expect(find.text('Sent A'), findsOneWidget);
    expect(find.text('Failed B'), findsNothing);
  });

  testWidgets('filter chip "Failed" reduces to error entries', (tester) async {
    when(() => ctrl.logs).thenReturn([
      SmsLogEntry.success('Sent X'),
      SmsLogEntry.error('Failed Y'),
      SmsLogEntry.info('Info Z'),
    ]);
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));

    await tester.tap(find.text('Failed'));
    await tester.pump();

    expect(find.text('Failed Y'), findsOneWidget);
    expect(find.text('Sent X'), findsNothing);
    expect(find.text('Info Z'), findsNothing);
  });

  testWidgets('filter chip "Warnings" reduces to warning entries',
      (tester) async {
    when(() => ctrl.logs).thenReturn([
      SmsLogEntry.warning('slow-network'),
      SmsLogEntry.info('plain-info-text'),
    ]);
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));

    await tester.tap(find.text('Warnings'));
    await tester.pump();

    expect(find.text('slow-network'), findsOneWidget);
    expect(find.text('plain-info-text'), findsNothing);
  });

  testWidgets('filter chip "Info" reduces to info entries', (tester) async {
    when(() => ctrl.logs).thenReturn([
      SmsLogEntry.info('tick-1'),
      SmsLogEntry.error('err-1'),
    ]);
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));

    await tester.tap(find.text('Info'));
    await tester.pump();

    expect(find.text('tick-1'), findsOneWidget);
    expect(find.text('err-1'), findsNothing);
  });

  testWidgets('filter "All" restores full list', (tester) async {
    when(() => ctrl.logs).thenReturn([
      SmsLogEntry.success('msg-sent-1'),
      SmsLogEntry.error('msg-failed-1'),
    ]);
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));

    await tester.tap(find.text('Sent'));
    await tester.pump();
    expect(find.text('msg-failed-1'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('msg-sent-1'), findsOneWidget);
    expect(find.text('msg-failed-1'), findsOneWidget);
  });

  testWidgets('clear button is disabled when logs empty', (tester) async {
    when(() => ctrl.logs).thenReturn(const []);
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));
    final iconButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline_rounded));
    expect(iconButton.onPressed, isNull);
  });

  testWidgets('clear button opens confirmation dialog', (tester) async {
    when(() => ctrl.logs).thenReturn([SmsLogEntry.info('keep me')]);
    when(() => ctrl.clearLogs()).thenAnswer((_) {});
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Clear all logs?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    // Cancel does not clear.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => ctrl.clearLogs());
  });

  testWidgets('clear button → confirm → clearLogs called', (tester) async {
    when(() => ctrl.logs).thenReturn([SmsLogEntry.info('a')]);
    when(() => ctrl.clearLogs()).thenAnswer((_) {});
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    verify(() => ctrl.clearLogs()).called(1);
  });

  testWidgets('chip badges show counts', (tester) async {
    when(() => ctrl.logs).thenReturn([
      SmsLogEntry.success('s1'),
      SmsLogEntry.success('s2'),
      SmsLogEntry.error('e1'),
    ]);
    await tester.pumpWidget(
        wrapWithProviders(const GatewayLogsPage(), smsCtrl: ctrl));
    // "All" badge = 3, "Sent" = 2, "Failed" = 1
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
