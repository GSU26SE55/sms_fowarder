import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/shared/widgets/section_card.dart';

import '../../helpers/test_helpers.dart';

void main() {
  testWidgets('renders title, subtitle, and children', (tester) async {
    await tester.pumpWidget(wrapWithApp(const SectionCard(
      icon: Icons.cloud_outlined,
      title: 'Backend',
      subtitle: 'Where this gateway pulls SMS from',
      children: [Text('child-1'), Text('child-2')],
    )));
    expect(find.text('Backend'), findsOneWidget);
    expect(find.text('Where this gateway pulls SMS from'), findsOneWidget);
    expect(find.text('child-1'), findsOneWidget);
    expect(find.text('child-2'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
  });

  testWidgets('renders without subtitle', (tester) async {
    await tester.pumpWidget(wrapWithApp(const SectionCard(
      icon: Icons.dns,
      title: 'No subtitle',
      children: [SizedBox.shrink()],
    )));
    expect(find.text('No subtitle'), findsOneWidget);
  });

  testWidgets('renders with empty children list', (tester) async {
    await tester.pumpWidget(wrapWithApp(const SectionCard(
      icon: Icons.dns,
      title: 'No kids',
      children: [],
    )));
    expect(find.text('No kids'), findsOneWidget);
  });

  testWidgets('renders many children', (tester) async {
    await tester.pumpWidget(wrapWithApp(SectionCard(
      icon: Icons.dns,
      title: 'Many',
      children: List.generate(5, (i) => Text('child-$i')),
    )));
    for (var i = 0; i < 5; i++) {
      expect(find.text('child-$i'), findsOneWidget);
    }
  });
}
