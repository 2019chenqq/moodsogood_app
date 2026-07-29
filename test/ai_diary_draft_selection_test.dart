import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/ai_diary_draft.dart';
import 'package:moodsogood_app/ai/ai_diary_draft_service.dart';
import 'package:moodsogood_app/ai/innera_ai_message.dart';
import 'package:moodsogood_app/ai/widgets/ai_diary_draft_sheet.dart';

void main() {
  test('keeps every user-authored character for the original diary option', () {
    final original = List.filled(775, '心').join();
    final messages = [
      InneraAiMessage(
        id: 'user-1',
        role: InneraAiMessageRole.user,
        text: original,
        createdAt: DateTime(2026, 7, 24),
      ),
      InneraAiMessage(
        id: 'assistant-1',
        role: InneraAiMessageRole.assistant,
        text: '這段 AI 回覆不應混入原稿。',
        createdAt: DateTime(2026, 7, 24),
      ),
    ];

    final result = AiDiaryDraftService.originalUserContent(messages);

    expect(result.runes.length, 775);
    expect(result, original);
    expect(result, isNot(contains('AI 回覆')));
  });

  test('combines every selected suggestion instead of keeping only the first',
      () {
    const suggestions = [
      DiaryDraftSuggestion(
        value: '我有清楚說出自己的感受',
        source: DiaryDraftSource.explicit,
        confidence: 1,
      ),
      DiaryDraftSuggestion(
        value: '我仍然完成了今天的重要事情',
        source: DiaryDraftSource.explicit,
        confidence: 1,
      ),
    ];

    expect(
      AiDiaryDraftService.combineSuggestionValues(suggestions),
      '我有清楚說出自己的感受\n我仍然完成了今天的重要事情',
    );
  });

  testWidgets('review sheet offers full original text and multi-select items',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = List.filled(775, '心').join();
    final draft = AiDiaryDraft(
      id: '2026-07-24',
      recordDate: DateTime(2026, 7, 24),
      promptVersion: 'test',
      createdAt: DateTime(2026, 7, 24),
      content: const DiaryDraftSuggestion(
        value: 'AI 整理稿',
        source: DiaryDraftSource.summarized,
        confidence: 1,
      ),
      didWellSuggestions: const [
        DiaryDraftSuggestion(
          value: '我有清楚說出自己的感受',
          source: DiaryDraftSource.explicit,
          confidence: 1,
        ),
        DiaryDraftSuggestion(
          value: '我仍完成今天的重要事情',
          source: DiaryDraftSource.explicit,
          confidence: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDiaryDraftSheet(
            draft: draft,
            existingDiary: null,
            originalContent: original,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('保留完整原稿（775 字）'), findsOneWidget);
    expect(find.text('使用 AI 整理稿（6 字）'), findsOneWidget);

    final secondChoice = find.text('我仍完成今天的重要事情');
    final tile = find.ancestor(
      of: secondChoice,
      matching: find.byType(CheckboxListTile),
    );
    expect(tester.widget<CheckboxListTile>(tile).value, isTrue);

    await tester.tap(secondChoice);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(tile).value, isFalse);
  });
}
