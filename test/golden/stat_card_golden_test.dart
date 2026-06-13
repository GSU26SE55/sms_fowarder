import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/theme/app_theme.dart';
import 'package:sms_gateway_app/shared/widgets/empty_state.dart';
import 'package:sms_gateway_app/shared/widgets/stat_card.dart';

/// =====================================================================
///  Golden tests — pixel-perfect snapshot.
///
///  Cách dùng:
///   - Lần đầu (hoặc khi UI đổi cố tình): `flutter test --update-goldens`
///   - Bình thường: `flutter test test/golden/`
///
///  Nếu UI vô tình thay đổi (regression), test fail và chỉ ra diff PNG.
///  Tests này demo pattern; bạn có thể thêm golden cho hero header, log item,
///  từng page tuỳ độ tỉ mỉ mong muốn.
/// =====================================================================
void main() {
  group('StatCard golden', () {
    testWidgets('default (green / sent)', (tester) async {
      await tester.pumpWidget(_frame(const StatCard(
        icon: Icons.check_circle_outline_rounded,
        accent: Color(0xFF10B981),
        label: 'Sent',
        value: '42',
      )));
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/stat_card_sent.png'));
    });

    testWidgets('error (red / failed)', (tester) async {
      await tester.pumpWidget(_frame(const StatCard(
        icon: Icons.error_outline_rounded,
        accent: Color(0xFFEF4444),
        label: 'Failed',
        value: '7',
      )));
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/stat_card_failed.png'));
    });
  });

  group('EmptyState golden', () {
    testWidgets('default', (tester) async {
      await tester.pumpWidget(_frame(const EmptyState(
        icon: Icons.sms_outlined,
        title: 'Welcome to SMS Gateway',
        message:
            'Configure your backend URL, device code, and gateway token to start.',
      )));
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/empty_state.png'));
    });
  });
}

Widget _frame(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SizedBox(width: 280, child: child),
      ),
    ),
  );
}
