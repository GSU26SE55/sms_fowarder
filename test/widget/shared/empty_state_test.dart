import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/shared/widgets/empty_state.dart';

import '../../helpers/test_helpers.dart';

void main() {
  testWidgets('renders icon, title, message and optional action', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrapWithApp(EmptyState(
      icon: Icons.inbox,
      title: 'Nothing here',
      message: 'Add something to see it.',
      action: FilledButton(
        onPressed: () => taps++,
        child: const Text('Add now'),
      ),
    )));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add something to see it.'), findsOneWidget);
    expect(find.byIcon(Icons.inbox), findsOneWidget);
    await tester.tap(find.text('Add now'));
    expect(taps, 1);
  });

  testWidgets('omits message and action gracefully', (tester) async {
    await tester.pumpWidget(wrapWithApp(const EmptyState(
      icon: Icons.search_off,
      title: 'No results',
    )));
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('renders title-only without action', (tester) async {
    await tester.pumpWidget(wrapWithApp(const EmptyState(
      icon: Icons.cloud_off,
      title: 'Offline',
    )));
    expect(find.text('Offline'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('shows long message that wraps', (tester) async {
    await tester.pumpWidget(wrapWithApp(SizedBox(
      width: 200,
      child: const EmptyState(
        icon: Icons.info,
        title: 'Long',
        message:
            'This message is intentionally long to verify that the layout wraps gracefully across multiple lines without overflow.',
      ),
    )));
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
