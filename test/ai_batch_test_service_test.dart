import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai_evaluation/services/ai_batch_dataset_service.dart';
import 'package:moodsogood_app/ai_evaluation/services/ai_batch_test_service.dart';

void main() {
  late Directory temporaryDirectory;
  late AiBatchDatasetService datasetService;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('ai_batch_');
    datasetService = AiBatchDatasetService(
      documentsDirectory: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('lists full datasets only and rejects non-synthetic cases', () async {
    final exports = await datasetService.exportsDirectory();
    final valid = File('${exports.path}/ai_evaluation_full_20260723.json');
    final ignored = File('${exports.path}/ai_evaluation_inputs_20260723.json');
    await valid.writeAsString(jsonEncode(_datasetJson(isSynthetic: false)));
    await ignored.writeAsString('{}');

    final listed = await datasetService.listFullDatasets();
    expect(listed, hasLength(1));
    expect(listed.single.uri.pathSegments.last,
        'ai_evaluation_full_20260723.json');
    expect(
      () => datasetService.load(valid),
      throwsA(isA<FormatException>()),
    );
  });

  test('continues after a failed case and writes a standalone result',
      () async {
    final exports = await datasetService.exportsDirectory();
    final source = File('${exports.path}/ai_evaluation_full_20260723.json');
    await source.writeAsString(jsonEncode(_datasetJson(caseCount: 2)));
    final dataset = await datasetService.load(source);
    final progress = <List<int>>[];
    final service = AiBatchTestService(
      gateway: _FakeGateway(),
      datasetService: datasetService,
      clock: () => DateTime.utc(2026, 7, 23, 12, 34, 56),
    );

    final output = await service.run(
      dataset: dataset,
      onProgress: (completed, total, successes, failures) {
        progress.add([completed, total, successes, failures]);
      },
    );

    expect(progress, [
      [1, 2, 1, 0],
      [2, 2, 1, 1],
    ]);
    expect(output.result.model, 'production-model');
    expect(output.result.promptVersion, 'production-prompt-v1');
    expect(output.result.successCount, 1);
    expect(output.result.failureCount, 1);
    expect(await File(output.filePath).exists(), isTrue);
    expect(
        output.filePath, endsWith('ai_evaluation_result_20260723_123456.json'));

    final saved = jsonDecode(await File(output.filePath).readAsString()) as Map;
    final first = (saved['results'] as List).first as Map;
    expect(first['response'], '完整 AI 回覆');
    expect(first['inputTokens'], 101);
    expect(first['outputTokens'], 52);
    expect((first['input'] as Map).containsKey('groundTruth'), isFalse);
  });
}

Map<String, dynamic> _datasetJson({
  bool isSynthetic = true,
  int caseCount = 1,
}) =>
    {
      'version': '1.0.0',
      'seed': 20260723,
      'cases': List.generate(
        caseCount,
        (index) => {
          'testCaseId': 'case_${index + 1}',
          'scenarioType': 'stable',
          'difficulty': 'easy',
          'period': {
            'startDate': '2026-06-01',
            'endDate': '2026-06-02',
          },
          'persona': {'profile': '匿名成人'},
          'dailyRecords': [
            {
              'date': '2026-06-01',
              'overallMood': 3,
              'moodScale': 5,
              'emotions': [
                {'name': '平靜', 'value': 3}
              ],
              'sleep': {'quality': 4},
              'diaryEntry': {'title': '日記', 'content': '今天平穩。'},
            }
          ],
          'groundTruth': {'testCaseId': 'case_${index + 1}'},
          'isSynthetic': isSynthetic,
          'dataPurpose': 'ai_evaluation',
        },
      ),
    };

class _FakeGateway implements AiBatchAiGateway {
  int calls = 0;

  @override
  Future<AiBatchAiReply> send(AiBatchEvaluationCase evaluationCase) async {
    calls++;
    if (calls == 2) throw StateError('simulated failure');
    return const AiBatchAiReply(
      text: '完整 AI 回覆',
      model: 'production-model',
      promptVersion: 'production-prompt-v1',
      inputTokens: 101,
      outputTokens: 52,
    );
  }
}
