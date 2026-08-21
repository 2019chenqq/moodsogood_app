import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_record_draft.dart';
import 'package:moodsogood_app/ai/widgets/ai_record_draft_card.dart';

void main() {
  testWidgets('fits a narrow phone without overflowing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final draft = InneraAiRecordDraft.fromMap({
      'dateKey': '2026-08-19',
      'emotionMentions': [
        {
          'rawText': '焦慮',
          'normalizedDimensionId': '焦慮',
          'normalizedDimensionName': '焦慮',
          'value': 4,
          'subjectType': 'user',
        },
      ],
      'symptoms': ['心悸', '頭痛'],
      'missingFields': ['心悸程度', '活動量'],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiRecordDraftCard(
              draft: draft,
              onPreview: () {},
              onExtractDiary: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('可以整理成紀錄'), findsOneWidget);
    expect(find.text('查看並確認'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers a separate final action for an unconfirmed draft',
      (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiRecordDraftCard(
            draft: InneraAiRecordDraft.empty(DateTime(2026, 7, 28)),
            onPreview: () {},
            onExtractDiary: () => pressed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看並確認'));
    expect(pressed, isTrue);
  });

  testWidgets('allows an already confirmed draft to supplement the record',
      (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiRecordDraftCard(
            draft: InneraAiRecordDraft.empty(
              DateTime(2026, 7, 28),
            ).copyWith(confirmed: true),
            onPreview: () {},
            onExtractDiary: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.text('新增另一筆紀錄'), findsOneWidget);
    await tester.tap(find.text('新增另一筆紀錄'));
    expect(pressed, isTrue);
  });

  testWidgets('routes an unconfirmed multi-event draft to event preview',
      (tester) async {
    var previewPressed = false;
    var diaryPressed = false;
    final draft = InneraAiRecordDraft.fromMap({
      'dateKey': '2026-08-21',
      'eventDrafts': [
        {
          'id': 'afternoon',
          'timeContext': '下午',
          'timePrecision': 'approximate',
          'symptoms': ['疲倦'],
          'rawUserEntries': ['下午很累'],
          'note': '下午很累',
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiRecordDraftCard(
          draft: draft,
          onPreview: () => previewPressed = true,
          onExtractDiary: () => diaryPressed = true,
        ),
      ),
    ));

    await tester.tap(find.text('查看並確認 1 筆紀錄'));
    expect(previewPressed, isTrue);
    expect(diaryPressed, isFalse);
  });
}
