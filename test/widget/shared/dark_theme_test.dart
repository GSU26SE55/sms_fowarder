import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/theme/app_theme.dart';
import 'package:sms_gateway_app/shared/widgets/app_button.dart';
import 'package:sms_gateway_app/shared/widgets/empty_state.dart';
import 'package:sms_gateway_app/shared/widgets/section_card.dart';
import 'package:sms_gateway_app/shared/widgets/stat_card.dart';

void main() {
  Widget wrapDark(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  testWidgets('AppButton renders in dark theme', (tester) async {
    await tester.pumpWidget(wrapDark(AppButton(
      label: 'Save',
      onPressed: () {},
    )));
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('StatCard renders in dark theme', (tester) async {
    await tester.pumpWidget(wrapDark(const StatCard(
      icon: Icons.check,
      accent: Colors.green,
      label: 'Sent',
      value: '42',
    )));
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('SectionCard renders in dark theme', (tester) async {
    await tester.pumpWidget(wrapDark(const SectionCard(
      icon: Icons.cloud_outlined,
      title: 'Backend',
      children: [Text('child')],
    )));
    expect(find.text('Backend'), findsOneWidget);
  });

  testWidgets('EmptyState renders in dark theme', (tester) async {
    await tester.pumpWidget(wrapDark(const EmptyState(
      icon: Icons.inbox,
      title: 'Empty',
      message: 'no items',
    )));
    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('no items'), findsOneWidget);
  });
}
