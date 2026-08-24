import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/period_calendar_page.dart';
import 'package:moodsogood_app/daily/widgets/symptom_page.dart';
import 'package:moodsogood_app/models/period_cycle.dart';

void main() {
  test('calendar presentation calculates average cycle and marked days', () {
    final result = PeriodCalendarPage.buildPresentation(
      [
        PeriodCycle(
          id: 'first',
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 7, 5),
        ),
        PeriodCycle(
          id: 'second',
          startDate: DateTime(2026, 7, 29),
          endDate: DateTime(2026, 8, 2),
        ),
      ],
      asOf: DateTime(2026, 8, 22),
    );

    expect(result.cycleLength, 28);
    expect(result.nextExpectedStart, DateTime(2026, 8, 26));
    expect(result.markedDays, contains(DateTime(2026, 8, 2)));
    expect(result.markedDays, isNot(contains(DateTime(2026, 8, 3))));
  });

  test('average cycle keeps short and long positive intervals', () {
    final result = PeriodCalendarPage.buildPresentation(
      [
        PeriodCycle(id: 'a', startDate: DateTime(2026, 1, 1)),
        PeriodCycle(id: 'b', startDate: DateTime(2026, 1, 11)),
        PeriodCycle(id: 'c', startDate: DateTime(2026, 4, 11)),
      ],
      asOf: DateTime(2026, 4, 11),
    );

    expect(result.cycleLength, 50);
  });

  testWidgets('standalone period calendar can start expanded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              PeriodCalendarCard(
                markedDays: const {},
                focusedMonth: DateTime(2026, 8),
                isTodayPeriod: false,
                onTapDate: (_) {},
                onChangeMonth: (_) {},
                cycleLength: 28,
                nextExpectedStart: null,
                busy: false,
                initiallyExpanded: true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('2026年8月'), findsOneWidget);
    final crossFade = tester.widget<AnimatedCrossFade>(
      find.byType(AnimatedCrossFade),
    );
    expect(crossFade.crossFadeState, CrossFadeState.showFirst);
  });
}
