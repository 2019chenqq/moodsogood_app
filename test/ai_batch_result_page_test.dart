import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai_evaluation/models/ai_batch_test_result.dart';
import 'package:moodsogood_app/ai_evaluation/screens/ai_batch_result_page.dart';

void main() {
  testWidgets('shows statistics and switches cases horizontally',
      (tester) async {
    final result = AiBatchTestResult(
      model: 'gpt-test',
      promptVersion: 'prompt-v1',
      createdAt: DateTime.utc(2026, 7, 23),
      sourceFile: 'ai_evaluation_full_test.json',
      results: const [
        AiBatchCaseResult(
          caseId: 'case_1',
          success: true,
          response: '第一筆完整回覆',
          elapsedMs: 1000,
          input: {'dailyRecords': []},
        ),
        AiBatchCaseResult(
          caseId: 'case_2',
          success: false,
          response: '',
          elapsedMs: 3000,
          input: {'dailyRecords': []},
          error: '模擬失敗',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AiBatchResultPage(
          result: result,
          resultFilePath: 'ai_evaluation_result_test.json',
        ),
      ),
    );

    expect(find.text('案例數：2'), findsOneWidget);
    expect(find.text('成功：1'), findsOneWidget);
    expect(find.text('失敗：1'), findsOneWidget);
    expect(find.text('平均回覆時間：1000 ms'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('執行失敗：模擬失敗'), findsOneWidget);
  });
}
