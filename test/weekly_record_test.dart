import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/weekly_record.dart';

void main() {
  test('weekly record parses the fields needed by trends and visit summaries',
      () {
    final record = WeeklyRecord.fromData('2026-07-27', {
      'weekStart': '2026-07-27T00:00:00.000',
      'weekEnd': '2026-08-02T00:00:00.000',
      'overallState': 2,
      'comparison': '稍微變差',
      'emotions': ['焦慮', '疲憊', '煩躁'],
      'primaryEmotion': '焦慮',
      'primaryEmotionIntensity': 4,
      'sleepQuality': 2,
      'poorSleepDays': '3～4 天',
      'sleepIssues': ['入睡困難'],
      'symptoms': [
        {'name': '心悸', 'intensity': 4, 'frequency': '數天'},
      ],
      'functionImpacts': {'專注完成事情': 2, '外出': 1},
      'majorChanges': ['工作／學業壓力'],
      'eventNote': '專案進度壓力增加。',
      'safetyFlags': ['都沒有'],
      'note': '這週很累。',
      'nextWeekFocus': '睡眠與作息',
    });

    expect(record.overallState, 2);
    expect(record.comparison, '稍微變差');
    expect(record.emotions, ['焦慮', '疲憊', '煩躁']);
    expect(record.primaryEmotionIntensity, 4);
    expect(record.sleepQuality, 2);
    expect(record.symptoms.single.name, '心悸');
    expect(record.symptoms.single.intensity, 4);
    expect(record.symptoms.single.frequency, '數天');
    expect(record.functionImpacts['專注完成事情'], 2);
    expect(record.majorChanges, ['工作／學業壓力']);
    expect(record.nextWeekFocus, '睡眠與作息');
    expect(record.visitSummary, contains('本週整體狀態為 2 分'));
    expect(record.visitSummary, contains('主要情緒為焦慮、疲憊、煩躁'));
    expect(record.visitSummary, contains('主要睡眠狀況為入睡困難'));
    expect(record.visitSummary, contains('日常功能受影響項目為專注完成事情、外出'));
  });
}
