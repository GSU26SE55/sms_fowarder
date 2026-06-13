import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/sms_log_entry.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/widgets/sms_log_item.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  testWidgets('success log shows check icon and message', (tester) async {
    await tester.pumpWidget(wrapWithApp(
      SmsLogItem(entry: SmsLogEntry.success('Sent OK', smsId: 'abc-123')),
    ));
    expect(find.text('Sent OK'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.textContaining('abc-123'), findsOneWidget);
  });

  testWidgets('error log shows error icon', (tester) async {
    await tester.pumpWidget(wrapWithApp(
      SmsLogItem(entry: SmsLogEntry.error('boom')),
    ));
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('warning + info also render', (tester) async {
    await tester.pumpWidget(wrapWithApp(Column(children: [
      SmsLogItem(entry: SmsLogEntry.warning('careful')),
      SmsLogItem(entry: SmsLogEntry.info('just info')),
    ])));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
  });

  testWidgets('shows timestamp formatted as HH:mm:ss', (tester) async {
    final entry = SmsLogEntry(
      timestamp: DateTime(2026, 1, 15, 14, 30, 45),
      level: SmsLogLevel.info,
      message: 'm',
    );
    await tester.pumpWidget(wrapWithApp(SmsLogItem(entry: entry)));
    expect(find.text('14:30:45'), findsOneWidget);
  });

  testWidgets('does NOT show smsId line when entry has no smsId',
      (tester) async {
    await tester.pumpWidget(wrapWithApp(
      SmsLogItem(entry: SmsLogEntry.info('plain message')),
    ));
    // smsId rendered with monospace font when present; only timestamp
    // appears in subtitle row.
    expect(find.text('·'), findsNothing);
  });

  testWidgets('shows smsId with separator when present', (tester) async {
    await tester.pumpWidget(wrapWithApp(
      SmsLogItem(entry: SmsLogEntry.success('m', smsId: 'sms-99')),
    ));
    expect(find.text('·'), findsOneWidget);
    expect(find.text('sms-99'), findsOneWidget);
  });

  testWidgets('renders very long message (multiline)', (tester) async {
    final entry = SmsLogEntry.error(
        'A very long error message that should display on multiple lines and not overflow horizontally in the card layout of the logs page rendering.');
    await tester.pumpWidget(wrapWithApp(SmsLogItem(entry: entry)));
    expect(find.byType(SmsLogItem), findsOneWidget);
  });

  testWidgets('renders unicode message correctly', (tester) async {
    await tester.pumpWidget(wrapWithApp(
      SmsLogItem(
          entry: SmsLogEntry.success('🎉 Đã gửi SMS', smsId: 'sms-vn')),
    ));
    expect(find.text('🎉 Đã gửi SMS'), findsOneWidget);
  });

  testWidgets('renders empty message', (tester) async {
    await tester.pumpWidget(wrapWithApp(
      SmsLogItem(entry: SmsLogEntry.info('')),
    ));
    expect(find.byType(SmsLogItem), findsOneWidget);
  });

  testWidgets('renders ellipsis on very long smsId in narrow tile',
      (tester) async {
    await tester.pumpWidget(wrapWithApp(SizedBox(
      width: 250,
      child: SmsLogItem(
        entry: SmsLogEntry.info(
          'short msg',
          smsId: 'super-long-smsid-aaaaaaaaaaaaaaaa-bbbbbbbb',
        ),
      ),
    )));
    final id = tester.widget<Text>(
        find.textContaining('super-long-smsid'));
    expect(id.maxLines, 1);
    expect(id.overflow, TextOverflow.ellipsis);
  });
}
