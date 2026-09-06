import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/follow_up/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/follow_up/models/follow_up_summary_feedback.dart';
import 'package:moodsogood_app/follow_up/widgets/follow_up_feedback_dialog.dart';

void main() {
  test('Yes requires all coded answers and round trips', () {
    expect(
        () => FollowUpSummaryFeedback(
            shownToDoctor: true, submittedAt: DateTime.now()),
        throwsArgumentError);
    final feedback = FollowUpSummaryFeedback(
        shownToDoctor: true,
        surfacedForgottenInfo: FollowUpFeedbackAnswer.unsure,
        hadDeeperDiscussion: FollowUpFeedbackAnswer.no,
        doctorRequestedAgain: FollowUpDoctorAnswer.notMentioned,
        submittedAt: DateTime(2026, 9, 6));
    expect(FollowUpSummaryFeedback.fromMap(feedback.toMap())!.toMap(),
        feedback.toMap());
    expect(feedback.toMap()['doctorRequestedAgain'], 'notMentioned');
  });

  testWidgets('Yes enables submission only after all four answers',
      (tester) async {
    FollowUpSummaryFeedback? saved;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: FollowUpFeedbackDialog(
      onSubmit: (feedback) async {
        saved = feedback;
      },
    ))));
    await tester.tap(find.widgetWithText(ChoiceChip, '有'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '不確定').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '不確定').last);
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '沒有提到'));
    await tester.tap(find.widgetWithText(ChoiceChip, '沒有提到'));
    await tester.pump();
    await tester.tap(find.text('送出'));
    await tester.pump();
    expect(saved!.shownToDoctor, true);
    expect(saved!.doctorRequestedAgain, FollowUpDoctorAnswer.notMentioned);
  });

  test('legacy summaries and sharing remain unchanged by private feedback', () {
    final old = FollowUpSummaryRecord.fromMap('id', {});
    expect(old.feedback, isNull);
    final feedback = FollowUpSummaryFeedback(
        shownToDoctor: false,
        surfacedForgottenInfo: FollowUpFeedbackAnswer.yes,
        submittedAt: DateTime(2026, 9, 6));
    final updated = old.copyWith(feedback: feedback);
    expect(updated.toDeidentifiedSnapshot(), old.toDeidentifiedSnapshot());
    final restored = FollowUpSummaryRecord.fromMap('id', updated.toMap());
    expect(restored.feedback!.shownToDoctor, false);
    expect(restored.feedback!.surfacedForgottenInfo, isNull);
    expect(restored.copyWith(additionalNotes: 'edited').feedback, isNotNull);
  });

  testWidgets('No hides follow-ups, clears earlier answers and submits once',
      (tester) async {
    final saved = <FollowUpSummaryFeedback>[];
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: FollowUpFeedbackDialog(
      onSubmit: (feedback) async {
        saved.add(feedback);
      },
    ))));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, '有'));
    await tester.pump();
    expect(find.text('醫師有沒有表示下次可以再帶這份摘要？'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, '沒有').first);
    await tester.pump();
    expect(find.text('醫師有沒有表示下次可以再帶這份摘要？'), findsNothing);
    await tester.tap(find.text('送出'));
    await tester.pump();
    expect(saved, hasLength(1));
    expect(saved.single.shownToDoctor, false);
    expect(saved.single.hadDeeperDiscussion, isNull);
    expect(saved.single.doctorRequestedAgain, isNull);
  });

  testWidgets('failure preserves answers and permits retry or skip',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FollowUpFeedbackDialog(
      onSubmit: (_) async => throw StateError('offline'),
    ))));
    await tester.tap(find.widgetWithText(ChoiceChip, '沒有'));
    await tester.pump();
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();
    expect(find.text('回饋尚未送出，請稍後重試。'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(find.text('略過'), findsOneWidget);
  });
}
