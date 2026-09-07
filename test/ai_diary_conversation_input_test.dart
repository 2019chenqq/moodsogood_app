import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/ai_diary_draft_service.dart';
import 'package:moodsogood_app/ai/innera_ai_message.dart';

void main() {
  test('diary input keeps all turns and full ordinary event narratives', () {
    final messages = List.generate(
        40,
        (i) => InneraAiMessage(
              id: '$i',
              role: i.isEven
                  ? InneraAiMessageRole.user
                  : InneraAiMessageRole.assistant,
              text: i == 0
                  ? '和朋友去市場買菜，回家一起做飯。'
                  : '第$i則：${List.filled(2100, '文').join()}事件結尾',
              createdAt: DateTime(2026, 9, 6),
            ));
    final input = AiDiaryDraftService.conversationForDiary(messages);
    expect(input, hasLength(40));
    expect(input.first['content'], messages.first.text);
    expect(input.last['content'], messages.last.text);
  });
}
