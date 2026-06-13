import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/shared/widgets/stat_card.dart';

import '../../helpers/test_helpers.dart';

void main() {
  testWidgets('renders icon, value, label', (tester) async {
    await tester.pumpWidget(wrapWithApp(const Center(
      child: StatCard(
        icon: Icons.check,
        accent: Colors.green,
        label: 'Sent',
        value: '42',
      ),
    )));
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('value text truncates at maxLines=1', (tester) async {
    await tester.pumpWidget(wrapWithApp(SizedBox(
      width: 100,
      child: const StatCard(
        icon: Icons.text_format,
        accent: Colors.blue,
        label: 'Label',
        value: 'AVeryVeryLongValueThatShouldEllipsis',
      ),
    )));
    final text = tester.widget<Text>(find.text('AVeryVeryLongValueThatShouldEllipsis'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('renders with optional subtitle', (tester) async {
    await tester.pumpWidget(wrapWithApp(const Center(
      child: StatCard(
        icon: Icons.timer,
        accent: Colors.indigo,
        label: 'Polling',
        value: '10s',
        subtitle: 'every interval',
      ),
    )));
    expect(find.text('every interval'), findsOneWidget);
  });

  testWidgets('renders very large value (counters)', (tester) async {
    await tester.pumpWidget(wrapWithApp(const Center(
      child: StatCard(
        icon: Icons.send,
        accent: Colors.green,
        label: 'Sent',
        value: '999999',
      ),
    )));
    expect(find.text('999999'), findsOneWidget);
  });

  testWidgets('renders zero value', (tester) async {
    await tester.pumpWidget(wrapWithApp(const Center(
      child: StatCard(
        icon: Icons.send,
        accent: Colors.green,
        label: 'Sent',
        value: '0',
      ),
    )));
    expect(find.text('0'), findsOneWidget);
  });
}
