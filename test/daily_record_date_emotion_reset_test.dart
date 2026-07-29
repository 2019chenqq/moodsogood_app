import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/daily_record_helpers.dart';
import 'package:moodsogood_app/daily/emotion_dimensions.dart';
import 'package:moodsogood_app/models/daily_record.dart';

void main() {
  test('an empty date starts with every emotion unselected', () {
    final emotions = emotionItemsForRecord(const <Emotion>[]);

    expect(emotions.map((item) => item.name), kEmotionCheckboxNames);
    expect(emotions.every((item) => item.value == null), isTrue);
  });

  test('only emotions saved for the selected date receive scores', () {
    final emotions = emotionItemsForRecord(const [
      Emotion(name: '焦慮', value: 4),
      Emotion(name: '自訂感受', value: 2),
    ]);

    expect(
      emotions.singleWhere((item) => item.name == '焦慮').value,
      4,
    );
    expect(
      emotions.singleWhere((item) => item.name == '平靜').value,
      isNull,
    );
    expect(
      emotions.singleWhere((item) => item.name == '自訂感受').value,
      2,
    );

    final nextDate = emotionItemsForRecord(const <Emotion>[]);
    expect(nextDate.any((item) => item.name == '自訂感受'), isFalse);
    expect(nextDate.every((item) => item.value == null), isTrue);
  });
}
