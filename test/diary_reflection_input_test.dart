import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/daily_check_in.dart';
import 'package:moodsogood_app/services/diary_reflection_input.dart';

void main() {
  final date = DateTime(2026, 9, 6);
  DailyCheckIn checkIn(DateTime day, int score) => DailyCheckIn(
        date: day,
        overallMood: score,
        healthStatus: 5,
        noSpecialEvent: false,
      );
  Map<String, dynamic> input(DailyCheckIn? value) => buildDiaryReflectionInput(
        diary: {'content': '今天和朋友聊天。', 'overallMood': 1, 'moodScore': 2},
        checkIn: value,
        date: date,
      );
  test('check-in wins over legacy diary mood and supplies the displayed score',
      () {
    final current = checkIn(date, 4);
    expect(diaryReflectionMood(current, date), 4);
    expect(input(current)['emotions'], [
      {'name': '整體情緒', 'score': 4}
    ]);
    expect(input(current)['diaryText'], contains('今天和朋友聊天。'));
    expect(input(current)['moodScale'], 5);
  });
  test('missing or another-day check-in never falls back to diary scores', () {
    for (final value in [null, checkIn(DateTime(2026, 9, 5), 5)]) {
      expect(diaryReflectionMood(value, date), isNull);
      expect(input(value)['emotions'], isEmpty);
    }
  });
  test('updated check-in is reflected and invalid scores are omitted', () {
    expect(input(checkIn(date, 2))['emotions'], [
      {'name': '整體情緒', 'score': 2}
    ]);
    expect(input(checkIn(date, 0))['emotions'], isEmpty);
  });
}
