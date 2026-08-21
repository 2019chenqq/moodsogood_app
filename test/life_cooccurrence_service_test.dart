import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/life_timeline_item.dart';
import 'package:moodsogood_app/services/life_cooccurrence_service.dart';

void main() {
  const service = LifeCooccurrenceService();

  test('shows only repeated shared clusters', () {
    final result = service.analyze({
      DateTime(2026, 8, 1): [_quick(DateTime(2026, 8, 1, 10), 'a')],
      DateTime(2026, 8, 2): [_quick(DateTime(2026, 8, 2, 11), 'b')],
    });

    expect(result, hasLength(1));
    expect(result.single.coreItems, containsAll(['心悸', '焦慮']));
    expect(result.single.sameDayCount, 2);
    expect(result.single.nearbyTimeCount, 0);
  });

  test('date-only evidence never counts as near-time occurrence', () {
    final result = service.analyze({
      DateTime(2026, 8, 1): [
        _dateOnlySymptom(DateTime(2026, 8, 1), '頭痛', 's1'),
        _dateOnlyEmotion(DateTime(2026, 8, 1), '焦慮', 'e1', 5),
      ],
      DateTime(2026, 8, 2): [
        _dateOnlySymptom(DateTime(2026, 8, 2), '頭痛', 's2'),
        _dateOnlyEmotion(DateTime(2026, 8, 2), '焦慮', 'e2', 10),
      ],
    });

    expect(result.single.sameDayCount, 2);
    expect(result.single.nearbyTimeCount, 0);
  });

  test('single occurrence and excluded diary/check-in pairs are hidden', () {
    final result = service.analyze({
      DateTime(2026, 8, 1): [
        _quick(DateTime(2026, 8, 1, 10), 'a'),
        LifeTimelineItem(
          time: DateTime(2026, 8, 1),
          type: LifeTimelineType.diary,
          title: '日記',
          summary: '有日記',
          hasExplicitTime: false,
        ),
        LifeTimelineItem(
          time: DateTime(2026, 8, 1),
          type: LifeTimelineType.dailyCheckIn,
          title: 'Daily Check-in',
          summary: '整體情緒 3/5',
          hasExplicitTime: false,
        ),
      ],
    });

    expect(result, isEmpty);
  });

  test('explicit events outside 120 minutes remain same-day only', () {
    final items = <DateTime, List<LifeTimelineItem>>{};
    for (var day = 1; day <= 2; day++) {
      final date = DateTime(2026, 8, day);
      items[date] = [
        _quickSymptom(DateTime(2026, 8, day, 8), 's$day'),
        _quickEmotion(DateTime(2026, 8, day, 12, 1), 'e$day'),
      ];
    }
    final result = service.analyze(items);

    expect(result, isEmpty);
  });
}

LifeTimelineItem _quick(DateTime time, String id) => LifeTimelineItem(
      time: time,
      type: LifeTimelineType.quickRecord,
      title: 'Quick Record',
      summary: '心悸、焦慮',
      sourceId: id,
      metadata: {
        'symptoms': [
          {'name': '心悸', 'severity': 4}
        ],
        'emotions': [
          {'name': '焦慮', 'intensity': 4}
        ],
      },
    );

LifeTimelineItem _quickSymptom(DateTime time, String id) => LifeTimelineItem(
      time: time,
      type: LifeTimelineType.quickRecord,
      title: 'Quick Record',
      summary: '心悸',
      sourceId: id,
      metadata: {
        'symptoms': [
          {'name': '心悸', 'severity': 4}
        ],
      },
    );

LifeTimelineItem _quickEmotion(DateTime time, String id) => LifeTimelineItem(
      time: time,
      type: LifeTimelineType.quickRecord,
      title: 'Quick Record',
      summary: '焦慮',
      sourceId: id,
      metadata: {
        'emotions': [
          {'name': '焦慮', 'intensity': 4}
        ],
      },
    );

LifeTimelineItem _dateOnlySymptom(DateTime date, String name, String id) =>
    LifeTimelineItem(
      time: date,
      type: LifeTimelineType.symptom,
      title: '症狀紀錄',
      summary: name,
      sourceId: id,
      hasExplicitTime: false,
      metadata: {
        'sourceType': 'dailyRecord',
        'symptoms': [name]
      },
    );

LifeTimelineItem _dateOnlyEmotion(
  DateTime date,
  String name,
  String id,
  int scale,
) =>
    LifeTimelineItem(
      time: date,
      type: LifeTimelineType.emotion,
      title: '情緒紀錄',
      summary: name,
      sourceId: id,
      hasExplicitTime: false,
      metadata: {
        'sourceType': 'dailyRecord',
        'moodScale': scale,
        'emotions': [
          {'name': name, 'value': 4}
        ],
      },
    );
