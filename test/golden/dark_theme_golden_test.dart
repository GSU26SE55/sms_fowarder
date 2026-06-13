import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/theme/app_theme.dart';
import 'package:sms_gateway_app/features/sms_gateway/domain/entities/sms_log_entry.dart';
import 'package:sms_gateway_app/features/sms_gateway/presentation/widgets/sms_log_item.dart';
import 'package:sms_gateway_app/shared/widgets/app_button.dart';
import 'package:sms_gateway_app/shared/widgets/empty_state.dart';
import 'package:sms_gateway_app/shared/widgets/section_card.dart';
import 'package:sms_gateway_app/shared/widgets/stat_card.dart';

void main() {
  final fixedTs = DateTime(2026, 1, 15, 14, 30, 45);

  testWidgets('AppButton primary dark', (tester) async {
    await tester.pumpWidget(_darkFrame(AppButton(
      label: 'Start gateway',
      icon: Icons.play_arrow_rounded,
      onPressed: () {},
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/dark_app_button_primary.png'));
  });

  testWidgets('StatCard dark', (tester) async {
    await tester.pumpWidget(_darkFrame(const StatCard(
      icon: Icons.check_circle_outline_rounded,
      accent: Color(0xFF10B981),
      label: 'Sent',
      value: '42',
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/dark_stat_card.png'));
  });

  testWidgets('SectionCard dark', (tester) async {
    await tester.pumpWidget(_darkFrame(const SectionCard(
      icon: Icons.cloud_outlined,
      title: 'Backend',
      subtitle: 'Where this gateway pulls SMS from',
      children: [
        TextField(decoration: InputDecoration(labelText: 'Backend URL')),
      ],
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/dark_section_card.png'));
  });

  testWidgets('EmptyState dark', (tester) async {
    await tester.pumpWidget(_darkFrame(const EmptyState(
      icon: Icons.sms_outlined,
      title: 'Welcome to SMS Gateway',
      message: 'Configure backend URL to start forwarding.',
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/dark_empty_state.png'));
  });

  testWidgets('SmsLogItem success dark', (tester) async {
    await tester.pumpWidget(_darkFrame(SmsLogItem(
      entry: SmsLogEntry(
        timestamp: fixedTs,
        level: SmsLogLevel.success,
        message: 'Sent SMS to +84901234567',
        smsId: '5d6e7fd6-8e56',
      ),
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/dark_log_item_success.png'));
  });

  testWidgets('SmsLogItem error dark', (tester) async {
    await tester.pumpWidget(_darkFrame(SmsLogItem(
      entry: SmsLogEntry(
        timestamp: fixedTs,
        level: SmsLogLevel.error,
        message: 'Failed: NO_SERVICE',
      ),
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/dark_log_item_error.png'));
  });
}

Widget _darkFrame(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(width: 340, child: child),
      ),
    ),
  );
}
