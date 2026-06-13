import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/theme/app_theme.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/sms_log_entry.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/widgets/sms_log_item.dart';

void main() {
  final fixedTs = DateTime(2026, 1, 15, 14, 30, 45);

  testWidgets('SmsLogItem success', (tester) async {
    await tester.pumpWidget(_frame(SmsLogItem(
      entry: SmsLogEntry(
        timestamp: fixedTs,
        level: SmsLogLevel.success,
        message: 'Sent SMS to +84901234567',
        smsId: '5d6e7fd6-8e56-4db2',
      ),
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/log_item_success.png'));
  });

  testWidgets('SmsLogItem error', (tester) async {
    await tester.pumpWidget(_frame(SmsLogItem(
      entry: SmsLogEntry(
        timestamp: fixedTs,
        level: SmsLogLevel.error,
        message: 'Failed: NO_SERVICE',
        smsId: '5d6e7fd6-8e56-4db2',
      ),
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/log_item_error.png'));
  });

  testWidgets('SmsLogItem warning', (tester) async {
    await tester.pumpWidget(_frame(SmsLogItem(
      entry: SmsLogEntry(
        timestamp: fixedTs,
        level: SmsLogLevel.warning,
        message: 'Realtime reconnecting',
      ),
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/log_item_warning.png'));
  });

  testWidgets('SmsLogItem info', (tester) async {
    await tester.pumpWidget(_frame(SmsLogItem(
      entry: SmsLogEntry(
        timestamp: fixedTs,
        level: SmsLogLevel.info,
        message: 'No pending SMS',
      ),
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/log_item_info.png'));
  });
}

Widget _frame(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(child: child),
      ),
    ),
  );
}
