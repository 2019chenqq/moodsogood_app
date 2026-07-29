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
    expect(physical, contains('目前模式：身體不適聊聊'));
    expect(physical, contains('先確認症狀位置、開始時間、強度及變化'));
    expect(review, contains('目前模式：狀態回顧'));
    expect(review, contains('紀錄事實'));
  });

  test('recent review stays separate from the shared daily record draft', () {
    final builder = InneraAiPromptBuilder();

    for (final mode in [
      InneraAiMode.dailyRecord,
      InneraAiMode.emotionalSupport,
      InneraAiMode.physicalHealth,
    ]) {
      expect(mode.supportsDailyRecordDraft, isTrue);
      final prompt = builder.buildSystemPrompt(mode);
      expect(prompt, contains('可以協助建立今天的共用紀錄草稿'));
      expect(prompt, contains('只整理使用者明確提到、且確實屬於今天'));
    }

    expect(InneraAiMode.recentReview.supportsDailyRecordDraft, isFalse);
    final reviewPrompt = builder.buildSystemPrompt(InneraAiMode.recentReview);
    expect(reviewPrompt, contains('不建立、不讀取、不更新今天的共用紀錄草稿'));
    expect(reviewPrompt, contains('recordDraft 必須為 null'));
    expect(reviewPrompt, contains('不得把回答縮成只描述今天'));
    expect(reviewPrompt, contains('不得從疲倦、做夢、睡眠品質'));
    expect(reviewPrompt, contains('frequentAfterMidnightSleep=true'));
    expect(reviewPrompt, contains('情緒分數 4～5 只代表該日強度'));
    expect(reviewPrompt, contains('mostFrequentEmotions'));
    expect(reviewPrompt, isNot(contains('只整理使用者明確提到、且確實屬於今天')));
  });
}
