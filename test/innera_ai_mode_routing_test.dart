import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_conversation_service.dart';
import 'package:moodsogood_app/ai/innera_ai_mode.dart';
import 'package:moodsogood_app/ai/innera_ai_prompt_builder.dart';

void main() {
  test('each AI mode uses a separate persisted conversation', () {
    const dateKey = '2026-07-24';
    final ids = InneraAiMode.values
        .map(
          (mode) =>
              InneraAiConversationService.conversationDocumentId(dateKey, mode),
        )
        .toSet();

    expect(ids, hasLength(InneraAiMode.values.length));
    expect(ids, contains('${dateKey}_emotionalSupport'));
    expect(ids, contains('${dateKey}_physicalHealth'));
    expect(ids, contains('${dateKey}_recentReview'));
  });

  test('chat entry modes keep distinct response instructions', () {
    final builder = InneraAiPromptBuilder();
    final emotional = builder.buildSystemPrompt(InneraAiMode.emotionalSupport);
    final physical = builder.buildSystemPrompt(InneraAiMode.physicalHealth);
    final review = builder.buildSystemPrompt(InneraAiMode.recentReview);

    expect(emotional, contains('目前模式：我想聊聊'));
    expect(emotional, contains('先回應使用者情緒與處境'));
    expect(physical, contains('目前模式：身體有些不舒服'));
    expect(physical, contains('先確認症狀位置、開始時間、強度及變化'));
    expect(review, contains('目前模式：回顧最近的狀態'));
    expect(review, contains('紀錄事實'));
  });
}
