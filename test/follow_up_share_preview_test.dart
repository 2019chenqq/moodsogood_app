import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/pages/follow_up_share_preview_page.dart';

void main() {
  testWidgets('share preview starts empty and only reveals checked sections',
      (tester) async {
    final now = DateTime.utc(2026, 8, 5);
    final record = FollowUpSummaryRecord(
      id: 'private-summary-id',
      createdAt: now,
      updatedAt: now,
      confirmedAt: now,
      appointmentDate: now,
      periodStart: DateTime.utc(2026, 8, 1),
      periodEnd: now,
      validRecordDays: 3,
      selectedTopics: const [
        {'type': 'sleep', 'label': '睡眠品質'},
      ],
      discussionDetails: '想詢問最近早醒',
      additionalNotes: '最近完成了一趟旅行',
      aiOutput: FollowUpAiOutput(
        keyChanges: const ['頭痛出現 2 天', '睡眠平均 7 小時', '情緒紀錄平穩'],
        timelineRelations: const [],
        discussionPriorities: const ['優先討論早醒'],
        userSharedNotes: const ['最近完成了一趟旅行'],
        dataLimitations: const ['有效紀錄 3 天'],
        generatedAt: now,
      ),
      sleepSummary: const {},
      sleepTrend: const [],
      medicationTimeline: const [],
    );

    await tester.pumpWidget(MaterialApp(
      home: FollowUpSharePreviewPage(summary: record),
    ));

    expect(find.textContaining('想詢問最近早醒。'), findsNothing);
    expect(find.textContaining('頭痛出現 2 天。'), findsNothing);
    expect(find.textContaining('最近完成了一趟旅行。'), findsNothing);

    await tester.tap(find.text('討論主題'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('想詢問最近早醒。'), findsOneWidget);
    expect(find.textContaining('頭痛出現 2 天。'), findsNothing);
    expect(find.textContaining('最近完成了一趟旅行。'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生活近況'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.textContaining('最近完成了一趟旅行。'), findsOneWidget);
  });
}
