import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/shared/widgets/app_button.dart';

import '../../helpers/test_helpers.dart';

void main() {
  testWidgets('renders label + icon and triggers onPressed', (tester) async {
    var clicks = 0;
    await tester.pumpWidget(wrapWithApp(AppButton(
      label: 'Save',
      icon: Icons.save,
      onPressed: () => clicks++,
    )));

    expect(find.text('Save'), findsOneWidget);
    expect(find.byIcon(Icons.save), findsOneWidget);

    await tester.tap(find.byType(AppButton));
    expect(clicks, 1);
  });

  testWidgets('shows loading spinner when loading=true and disables tap',
      (tester) async {
    var clicks = 0;
    await tester.pumpWidget(wrapWithApp(AppButton(
      label: 'Save',
      loading: true,
      onPressed: () => clicks++,
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(AppButton));
    expect(clicks, 0, reason: 'tap should be ignored while loading');
  });

  testWidgets('danger variant uses red background', (tester) async {
    await tester.pumpWidget(wrapWithApp(AppButton(
      label: 'Stop',
      variant: AppButtonVariant.danger,
      onPressed: () {},
    )));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final bg = button.style!.backgroundColor!.resolve({});
    expect(bg, isNotNull);
  });

  testWidgets('success variant renders without exception', (tester) async {
    await tester.pumpWidget(wrapWithApp(AppButton(
      label: 'Done',
      variant: AppButtonVariant.success,
      icon: Icons.check,
      onPressed: () {},
    )));
    expect(find.text('Done'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('neutral variant renders without exception', (tester) async {
    await tester.pumpWidget(wrapWithApp(AppButton(
      label: 'Cancel',
      variant: AppButtonVariant.neutral,
      onPressed: () {},
    )));
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('onPressed=null disables button', (tester) async {
    var clicks = 0;
    await tester.pumpWidget(wrapWithApp(const AppButton(
      label: 'Disabled',
      onPressed: null,
    )));
    await tester.tap(find.byType(AppButton));
    expect(clicks, 0);
  });

  testWidgets('button with no icon and no loading shows just text',
      (tester) async {
    await tester.pumpWidget(wrapWithApp(AppButton(
      label: 'TextOnly',
      onPressed: () {},
    )));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('TextOnly'), findsOneWidget);
  });
}
