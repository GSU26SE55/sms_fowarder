import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/theme/app_theme.dart';
import 'package:sms_gateway_app/shared/widgets/stat_card.dart';

void main() {
  testWidgets('StatCards row layout (3 cards)', (tester) async {
    await tester.pumpWidget(_frame(Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.check_circle_outline_rounded,
            accent: AppTheme.statusRunning,
            label: 'Sent',
            value: '12',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.error_outline_rounded,
            accent: AppTheme.statusErrored,
            label: 'Failed',
            value: '3',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.sync_rounded,
            accent: AppTheme.brandSeed,
            label: 'Status',
            value: 'On',
          ),
        ),
      ],
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/stats_row_3cards.png'));
  });

  testWidgets('StatCards row with large numbers', (tester) async {
    await tester.pumpWidget(_frame(Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.check_circle_outline_rounded,
            accent: AppTheme.statusRunning,
            label: 'Sent',
            value: '12345',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.error_outline_rounded,
            accent: AppTheme.statusErrored,
            label: 'Failed',
            value: '999',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.sync_rounded,
            accent: AppTheme.brandSeed,
            label: 'Status',
            value: 'On',
          ),
        ),
      ],
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/stats_row_large.png'));
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
        child: SizedBox(width: 380, child: child),
      ),
    ),
  );
}
