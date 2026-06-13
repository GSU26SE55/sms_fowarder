import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/theme/app_theme.dart';
import 'package:sms_gateway_app/shared/widgets/app_button.dart';

void main() {
  testWidgets('AppButton primary', (tester) async {
    await tester.pumpWidget(_frame(AppButton(
      label: 'Start gateway',
      icon: Icons.play_arrow_rounded,
      onPressed: () {},
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_button_primary.png'));
  });

  testWidgets('AppButton danger', (tester) async {
    await tester.pumpWidget(_frame(AppButton(
      label: 'Stop gateway',
      icon: Icons.stop_rounded,
      variant: AppButtonVariant.danger,
      onPressed: () {},
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_button_danger.png'));
  });

  testWidgets('AppButton success', (tester) async {
    await tester.pumpWidget(_frame(AppButton(
      label: 'Save settings',
      icon: Icons.check_rounded,
      variant: AppButtonVariant.success,
      onPressed: () {},
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_button_success.png'));
  });

  testWidgets('AppButton loading', (tester) async {
    await tester.pumpWidget(_frame(AppButton(
      label: 'Loading…',
      loading: true,
      onPressed: () {},
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_button_loading.png'));
  });
}

Widget _frame(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(child: SizedBox(width: 340, child: child)),
    ),
  );
}
