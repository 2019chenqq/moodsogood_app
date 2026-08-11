import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/quick_record_detail_section.dart';
import 'package:moodsogood_app/daily/record_detail_screen.dart';
import 'package:moodsogood_app/models/calendar_day_summary.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/services/calendar_summary_service.dart';
import 'package:moodsogood_app/services/daily_health_aggregation_service.dart';

void main() {
  const aggregation = DailyHealthAggregationService();

  test('history source has one day for DailyRecord plus three events', () {
    final result = aggregation.aggregateRange(
      dailyRecords: [
        DailyRecord(id: '2026-08-11', date: DateTime(2026, 8, 11)),
      ],
      healthEvents: [
        _event('a', DateTime(2026, 8, 11, 8)),
        _event('b', DateTime(2026, 8, 11, 12)),
        _event('c', DateTime(2026, 8, 11, 20)),
      ],
    );

    expect(result, hasLength(1));
    expect(result.single.hasDailyRecord, isTrue);
    expect(result.single.eventCount, 3);
  });

  test('QuickRecord-only date remains a history aggregate', () {
    final result = aggregation.aggregateRange(
      healthEvents: [_event('a', DateTime(2026, 8, 11, 8))],
    );

    expect(result, hasLength(1));
    expect(result.single.hasDailyRecord, isFalse);
    expect(result.single.recorded, isTrue);
  });

  testWidgets('detail section renders every QuickRecord', (tester) async {
    final events = [
      _event('a', DateTime(2026, 8, 11, 8)),
      _event('b', DateTime(2026, 8, 11, 12)),
      _event('c', DateTime(2026, 8, 11, 20)),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickRecordDetailSection(
            events: events,
            onEdit: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('quick-record-a')), findsOneWidget);
    expect(find.byKey(const Key('quick-record-b')), findsOneWidget);
    expect(find.byKey(const Key('quick-record-c')), findsOneWidget);
  });

  test('detail event ordering is ascending by timestamp', () {
    final sorted = sortHealthEventsByTimestamp([
      _event('late', DateTime(2026, 8, 11, 20)),
      _event('early', DateTime(2026, 8, 11, 8)),
      _event('middle', DateTime(2026, 8, 11, 12)),
    ]);

    expect(sorted.map((item) => item.id), ['early', 'middle', 'late']);
  });

  testWidgets('delete action targets only the selected HealthEvent',
      (tester) async {
    HealthEvent? deleted;
    final event = _event('target', DateTime(2026, 8, 11, 8));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickRecordDetailSection(
            events: [event],
            onEdit: (_) {},
            onDelete: (value) => deleted = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();

    expect(deleted?.id, 'target');
  });

  test('calendar recognizes QuickRecord-only day once', () {
    final aggregates = aggregation.aggregateRange(
      healthEvents: [
        _event('a', DateTime(2026, 8, 11, 8)),
        _event('b', DateTime(2026, 8, 11, 12)),
        _event('c', DateTime(2026, 8, 11, 20)),
      ],
    );
    final summaries = <String, CalendarDaySummary>{};

    CalendarSummaryService.applyQuickRecordAggregates(summaries, aggregates);

    expect(summaries, hasLength(1));
    expect(summaries['2026-08-11']!.hasDailyRecord, isFalse);
    expect(summaries['2026-08-11']!.hasQuickRecord, isTrue);
    expect(summaries['2026-08-11']!.quickRecordCount, 3);
    expect(summaries['2026-08-11']!.dailyRecordDocId, isNull);
  });

  test('QuickRecord merge preserves PeriodCycle presentation flags', () {
    final summaries = <String, CalendarDaySummary>{
      '2026-08-11': CalendarDaySummary(
        date: DateTime(2026, 8, 11),
        isPeriodDay: true,
        isPredictedPeriodDay: true,
      ),
    };
    final aggregates = aggregation.aggregateRange(
      healthEvents: [_event('a', DateTime(2026, 8, 11, 8))],
    );

    CalendarSummaryService.applyQuickRecordAggregates(summaries, aggregates);

    expect(summaries['2026-08-11']!.isPeriodDay, isTrue);
    expect(summaries['2026-08-11']!.isPredictedPeriodDay, isTrue);
  });

  test('midnight boundary creates separate calendar summaries', () {
    final aggregates = aggregation.aggregateRange(
      healthEvents: [
        _event('before', DateTime(2026, 8, 11, 23, 59)),
        _event('after', DateTime(2026, 8, 12)),
      ],
    );
    final summaries = <String, CalendarDaySummary>{};

    CalendarSummaryService.applyQuickRecordAggregates(summaries, aggregates);

    expect(summaries.keys, containsAll(['2026-08-11', '2026-08-12']));
    expect(summaries['2026-08-11']!.quickRecordCount, 1);
    expect(summaries['2026-08-12']!.quickRecordCount, 1);
  });
}

HealthEvent _event(String id, DateTime timestamp) => HealthEvent(
      id: id,
      timestamp: timestamp,
      emotions: const [HealthEventEmotion(name: '焦慮', intensity: 3)],
    );
