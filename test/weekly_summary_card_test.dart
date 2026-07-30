import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/widgets/weekly_summary_card.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/weekly_record.dart';

void main() {
  Widget buildCard({
    List<DailyRecord> records = const [],
    bool currentWeekHasNoDailyRecords = false,
    WeeklyRecord? weeklyRecord,
    VoidCallback? onStart,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WeeklySummaryCard(
            records: records,
            title: '狀態小結',
            subtitle: '本週',
            totalDays: 7,
            currentWeekHasNoDailyRecords: currentWeekHasNoDailyRecords,
            currentWeeklyRecord: weeklyRecord,
            onStartWeeklyReview: onStart,
          ),
        ),
      ),
    );
  }

  testWidgets('zero daily records offers the three minute weekly review',
      (tester) async {
    var started = false;
    await tester.pumpWidget(
      buildCard(
        currentWeekHasNoDailyRecords: true,
        onStart: () => started = true,
      ),
    );

    expect(find.text('開始 3 分鐘每週回顧'), findsOneWidget);
    expect(find.textContaining('不用補登'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start_weekly_review_button')));
    expect(started, isTrue);
  });

  testWidgets('a saved weekly record replaces the entry prompt',
      (tester) async {
    await tester.pumpWidget(
      buildCard(
        currentWeekHasNoDailyRecords: true,
        weeklyRecord: WeeklyRecord(
          id: '2026-07-27',
          weekStart: DateTime(2026, 7, 27),
          weekEnd: DateTime(2026, 8, 2),
          overallState: 2,
          energyLevel: 3,
          feeling: '疲憊',
          note: '先留下一點就好。',
        ),
        onStart: () {},
      ),
    );

    expect(find.textContaining('本週已留下週紀錄：有些低落'), findsOneWidget);
    expect(find.text('力氣 3/5 · 疲憊'), findsOneWidget);
    expect(find.text('先留下一點就好。'), findsOneWidget);
    expect(find.text('開始 3 分鐘每週回顧'), findsNothing);
  });

  testWidgets('existing daily records can also start a complementary review',
      (tester) async {
    await tester.pumpWidget(
      buildCard(
        records: [
          DailyRecord(id: '2026-07-30', date: DateTime(2026, 7, 30)),
        ],
        currentWeekHasNoDailyRecords: false,
        onStart: () {},
      ),
    );

    expect(find.text('把這週整理成一筆週紀錄。'), findsOneWidget);
    expect(find.text('開始 3 分鐘每週回顧'), findsOneWidget);
  });
}
