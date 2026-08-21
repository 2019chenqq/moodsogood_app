import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_response_shortcuts.dart';

void main() {
  test('shows rating shortcuts only for an explicit five-point question', () {
    expect(
      inneraAiResponseShortcuts('這個不舒服的程度，如果用 1～5 分評分會是幾分？'),
      ['1 / 5', '2 / 5', '3 / 5', '4 / 5', '5 / 5'],
    );
    expect(inneraAiResponseShortcuts('最近程度有變化嗎？'), isEmpty);
  });

  test('shows occurrence-time shortcuts only for an explicit when question',
      () {
    expect(
      inneraAiResponseShortcuts('這件事大約什麼時候發生？'),
      ['現在', '今天早上', '今天下午', '其他時間'],
    );
    expect(inneraAiResponseShortcuts('最近睡眠時間有改變嗎？'), isEmpty);
    expect(inneraAiResponseShortcuts('你大約什麼時候入睡？'), isEmpty);
  });

  test('sleep-pattern question takes priority over generic time wording', () {
    expect(
      inneraAiResponseShortcuts('比較像難入睡還是容易醒？'),
      ['難入睡', '容易醒', '太早醒', '睡睡醒醒', '其他'],
    );
    expect(
      inneraAiResponseShortcuts('睡不好的類型是哪一種，還是睡眠時間改變？'),
      ['難入睡', '容易醒', '太早醒', '睡睡醒醒', '其他'],
    );
    expect(inneraAiResponseShortcuts('是太早醒來嗎？'), isEmpty);
  });
}
