import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_conversation_service.dart';
import 'package:moodsogood_app/ai/innera_ai_mode.dart';
import 'package:moodsogood_app/ai/innera_ai_prompt_builder.dart';

void main() {
  test('AI purposes expose user-facing chat labels', () {
    expect(InneraAiMode.emotionalSupport.title, '陪我聊聊');
    expect(InneraAiMode.emotionalSupport.subtitle, '自由說說現在的感受與想法');
    expect(InneraAiMode.dailyRecord.title, '幫我記錄');
    expect(InneraAiMode.dailyRecord.subtitle, '把對話整理成狀態紀錄');
    expect(InneraAiMode.physicalHealth.title, '身體不舒服');
    expect(
      InneraAiMode.physicalHealth.subtitle,
      '記錄身體不適的位置、時間與程度',
    );
    expect(InneraAiMode.recentReview.title, '回顧近況');
    expect(
      InneraAiMode.recentReview.subtitle,
      '回顧近期的情緒、睡眠與症狀變化',
    );
  });

  test('all AI purposes use one persisted conversation per day', () {
    const dateKey = '2026-07-24';
    final ids = InneraAiMode.values
        .map(
          (_) => InneraAiConversationService.conversationDocumentId(dateKey),
        )
        .toSet();

    expect(ids, {dateKey});
  });

  test('legacy per-mode ids remain available for compatibility', () {
    const dateKey = '2026-07-24';
    expect(
      InneraAiConversationService.legacyModeConversationDocumentId(
        dateKey,
        InneraAiMode.emotionalSupport,
      ),
      '${dateKey}_emotionalSupport',
    );
  });

  test('chat entry modes keep distinct response instructions', () {
    final builder = InneraAiPromptBuilder();
    final emotional = builder.buildSystemPrompt(InneraAiMode.emotionalSupport);
    final physical = builder.buildSystemPrompt(InneraAiMode.physicalHealth);
    final review = builder.buildSystemPrompt(InneraAiMode.recentReview);

    expect(emotional, contains('目前模式：我想聊聊'));
    expect(emotional, contains('直接、自然地承接使用者實際說的事件或感受'));
    expect(emotional, contains('60～140 個繁體中文字'));
    expect(emotional, contains('最後最多提出一個容易回答的問題'));
    expect(emotional, contains('不得因 draft 缺少能量、食慾、活動量、睡眠、情緒分數、頻率或其他紀錄欄位而補問'));
    expect(physical, contains('目前模式：身體不適聊聊'));
    expect(physical, contains('先確認症狀位置、開始時間、強度及變化'));
    expect(review, contains('目前模式：狀態回顧'));
    expect(review, contains('紀錄事實'));
  });

  test('only explicit record intent changes chat to record', () {
    for (final text in [
      '幫我記一下，今天下午三點突然開始頭痛。',
      '我要記錄',
      '我想記一下下午發生的事情',
      '這個幫我存起來',
    ]) {
      expect(
        resolveInneraAiModeIntent(
          activeMode: InneraAiMode.emotionalSupport,
          message: text,
        ),
        InneraAiMode.dailyRecord,
      );
    }
  });

  test('symptoms and emotions alone do not change chat mode', () {
    for (final text in [
      '今天上班真的好累，什麼都不想做。',
      '我最近心情很差',
      '今天工作真的很煩',
      '我今天下午有點頭痛，好煩。',
    ]) {
      expect(
        resolveInneraAiModeIntent(
          activeMode: InneraAiMode.emotionalSupport,
          message: text,
        ),
        InneraAiMode.emotionalSupport,
      );
    }
  });

  test('explicit stop-recording intent changes record to chat', () {
    for (final text in ['我不想記了，想聊聊', '先不用記錄', '我們聊聊就好']) {
      expect(
        resolveInneraAiModeIntent(
          activeMode: InneraAiMode.dailyRecord,
          message: text,
        ),
        InneraAiMode.emotionalSupport,
      );
    }
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
