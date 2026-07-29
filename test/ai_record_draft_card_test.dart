import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_record_draft.dart';
import 'package:moodsogood_app/ai/widgets/ai_record_draft_card.dart';

void main() {
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

    await tester.tap(find.text('加入每日紀錄'));
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

    expect(find.text('再次加入／補充每日紀錄'), findsOneWidget);
    await tester.tap(find.text('再次加入／補充每日紀錄'));
    expect(pressed, isTrue);
  });
}
