import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/theme/app_theme.dart';
import 'package:sms_gateway_app/shared/widgets/section_card.dart';

void main() {
  testWidgets('SectionCard with subtitle + 2 children', (tester) async {
    await tester.pumpWidget(_frame(const SectionCard(
      icon: Icons.cloud_outlined,
      title: 'Backend',
      subtitle: 'Where this gateway pulls SMS from',
      children: [
        TextField(decoration: InputDecoration(labelText: 'Backend URL')),
        SizedBox(height: 12),
        TextField(decoration: InputDecoration(labelText: 'Gateway token')),
      ],
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/section_card_backend.png'));
  });

  testWidgets('SectionCard without subtitle', (tester) async {
    await tester.pumpWidget(_frame(const SectionCard(
      icon: Icons.smartphone_outlined,
      title: 'Device',
      children: [
        TextField(decoration: InputDecoration(labelText: 'Device code')),
      ],
    )));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/section_card_device.png'));
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
        child: child,
      ),
    ),
  );
}
