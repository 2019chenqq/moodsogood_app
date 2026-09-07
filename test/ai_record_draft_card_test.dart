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
    expect(find.text('加入日記'), findsOneWidget);
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

    await tester.tap(find.text('加入日記'));
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

    expect(find.text('加入日記'), findsOneWidget);
    await tester.tap(find.text('加入日記'));
    expect(pressed, isTrue);
  });

  testWidgets('saved diary cannot be added twice while events stay independent',
      (tester) async {
    var previewPressed = false;
    var diaryPressed = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AiRecordDraftCard(
      draft: InneraAiRecordDraft.empty(DateTime(2026, 9, 6)),
      diarySaved: true,
      onPreview: () => previewPressed = true,
      onExtractDiary: () => diaryPressed = true,
    ))));
    await tester.tap(find.text('日記已儲存'));
    expect(diaryPressed, isFalse);
    await tester.tap(find.text('確認事件'));
    expect(previewPressed, isTrue);
  });

  testWidgets('diary generation prevents duplicate actions', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AiRecordDraftCard(
      draft: InneraAiRecordDraft.empty(DateTime(2026, 9, 6)),
      isExtractingDiary: true,
      onPreview: () => pressed = true,
      onExtractDiary: () => pressed = true,
    ))));
    await tester.tap(find.text('確認事件'));
    await tester.tap(find.text('正在整理…'));
    expect(pressed, isFalse);
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

    await tester.tap(find.text('確認事件'));
    expect(previewPressed, isTrue);
    expect(diaryPressed, isFalse);
    previewPressed = false;
    await tester.tap(find.text('加入日記'));
    expect(diaryPressed, isTrue);
    expect(previewPressed, isFalse);
  });
}
