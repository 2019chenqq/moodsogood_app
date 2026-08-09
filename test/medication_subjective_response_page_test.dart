import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/medication_subjective_response_page.dart';

void main() {
  Widget subject({int day = 7}) => MaterialApp(
    home: MedicationSubjectiveResponsePage(
      medicationId: 'med-1',
      medicationName: '測試藥物',
      changeRecordId: 'change-1',
      changeDate: DateTime(2026, 8, 1),
      adjustmentSummary: '10 mg → 20 mg',
      followUpDay: day,
    ),
  );

  testWidgets('shows adjustment context and all questionnaire sections', (
    tester,
  ) async {
    await tester.pumpWidget(subject());

    expect(find.text('測試藥物'), findsOneWidget);
    expect(find.text('10 mg → 20 mg'), findsOneWidget);
    expect(find.text('調整日期 2026/08/01'), findsOneWidget);
    expect(find.text('Day 7'), findsOneWidget);
    expect(find.text('有改善'), findsOneWidget);
    expect(find.text('好壞都有'), findsOneWidget);
    expect(find.text('精神／活動力'), findsOneWidget);
    expect(find.text('很可能有關'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('其他藥物調整'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('其他藥物調整'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('補充說明'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('補充說明'), findsOneWidget);
  });

  testWidgets('save is enabled after the two required answers', (tester) async {
    await tester.pumpWidget(subject());
    FilledButton button() =>
        tester.widget(find.widgetWithText(FilledButton, '儲存'));

    expect(button().onPressed, isNull);
    await tester.tap(find.text('有改善'));
    await tester.tap(find.text('可能有關'));
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  test('rejects unsupported follow-up days', () {
    expect(() => subject(day: 10), throwsArgumentError);
  });
}
