import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/quick_record_home_card.dart';
import 'package:moodsogood_app/models/health_event.dart';

void main() {
  test('timeline summary prioritizes structured fields and omits long text',
      () {
    final event = HealthEvent(
      id: 'event-1',
      timestamp: DateTime(2026, 8, 19, 15, 20),
      emotions: const [HealthEventEmotion(name: '焦慮', intensity: 4)],
      symptoms: const [HealthEventSymptom(name: '心悸', severity: 3)],
      stateChanges: const {'activity_change': 2},
      context: '這是一段不應該出現在時間軸卡片的很長情境文字',
      note: '這是一段應該在編輯頁才完整顯示的很長原始描述',
    );

    final summary = healthEventTimelineSummary(event);

    expect(summary, containsAll(['焦慮 4/5', '心悸 3/5']));
    expect(summary.join(), isNot(contains(event.context!)));
    expect(summary.join(), isNot(contains(event.note!)));
  });
}
