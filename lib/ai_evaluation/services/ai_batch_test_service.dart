import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../ai/innera_ai_mode.dart';
import '../../ai/ai_request_id.dart';
import '../models/ai_batch_test_result.dart';
import 'ai_batch_dataset_service.dart';

class AiBatchAiReply {
  const AiBatchAiReply({
    required this.text,
    this.model,
    this.promptVersion,
    this.inputTokens,
    this.outputTokens,
  });

  final String text;
  final String? model;
  final String? promptVersion;
  final int? inputTokens;
  final int? outputTokens;
}

abstract class AiBatchAiGateway {
  Future<AiBatchAiReply> send(AiBatchEvaluationCase evaluationCase);
}

class ProductionAiBatchGateway implements AiBatchAiGateway {
  ProductionAiBatchGateway({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  static const requestMessage = '請回顧並整理這段期間的紀錄。';

  final FirebaseFunctions _functions;

  @override
  Future<AiBatchAiReply> send(AiBatchEvaluationCase evaluationCase) async {
    final context = _contextFor(evaluationCase);
    final result = await _functions
        .httpsCallable('generateInneraAiChat')
        .call(<String, dynamic>{
      'requestId': createAiRequestId(),
      'mode': InneraAiMode.recentReview.systemPromptKey,
      'message': requestMessage,
      'messages': const <Map<String, String>>[],
      'context': context,
      'contextSources': <Map<String, dynamic>>[
        <String, dynamic>{
          'label': '匿名模擬評測紀錄',
          'dateRange':
              '${evaluationCase.startDate} 至 ${evaluationCase.endDate}',
          'count': evaluationCase.dailyRecords.length,
        },
      ],
    }).timeout(const Duration(seconds: 60));
    final response = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : const <String, dynamic>{};
    final reply = (response['reply'] ?? '').toString().trim();
    final followUp = (response['followUpQuestion'] ?? '').toString().trim();
    if (reply.isEmpty) {
      throw const FormatException('Missing AI reply');
    }
    return AiBatchAiReply(
      text: followUp.isEmpty ? reply : '$reply\n\n$followUp',
      model: _optionalText(response['model']),
      promptVersion: _optionalText(response['promptVersion']),
      inputTokens: (response['inputTokens'] as num?)?.toInt(),
      outputTokens: (response['outputTokens'] as num?)?.toInt(),
    );
  }

  String? _optionalText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> _contextFor(AiBatchEvaluationCase evaluationCase) {
    final records = evaluationCase.dailyRecords.map(_compactRecord).toList();
    final diaries = evaluationCase.dailyRecords
        .map((record) => _compactDiary(record))
        .whereType<Map<String, dynamic>>()
        .toList();
    return <String, dynamic>{
      'mode': InneraAiMode.recentReview.systemPromptKey,
      'generatedAt': DateTime.now().toIso8601String(),
      'lookbackDays': _periodDays(evaluationCase),
      'dailyRecordStats': _basicStats(evaluationCase),
      'recentDailyRecords': records,
      'recentDiaries': diaries,
      'persona': evaluationCase.persona,
      'isSynthetic': true,
      'dataPurpose': 'ai_evaluation',
    };
  }

  Map<String, dynamic> _compactRecord(Map<String, dynamic> record) => {
        'date': record['date'],
        'overallMood': record['overallMood'],
        'moodScale': record['moodScale'],
        'emotions': record['emotions'],
        'symptoms': record['bodySymptoms'] ?? record['symptoms'],
        'sleep': record['sleep'],
        'isPeriod': record['isPeriod'],
        'medicines': record['medicines'],
        'dailyActivities': record['dailyActivities'],
        'chatEntries': record['chatEntries'],
        'lifeEvents': record['lifeEvents'],
      };

  Map<String, dynamic>? _compactDiary(Map<String, dynamic> record) {
    final raw = record['diaryEntry'];
    if (raw is! Map) return null;
    final diary = Map<String, dynamic>.from(raw);
    return {
      'date': record['date'],
      'title': diary['title'],
      'summary': diary['content'],
      'overallMood': diary['overallMood'],
    };
  }

  Map<String, dynamic> _basicStats(AiBatchEvaluationCase evaluationCase) {
    final expected = _periodDays(evaluationCase);
    return {
      'recordedDays': evaluationCase.dailyRecords.length,
      'expectedDays': expected,
      'missingDays':
          (expected - evaluationCase.dailyRecords.length).clamp(0, expected),
    };
  }

  int _periodDays(AiBatchEvaluationCase evaluationCase) {
    final start = DateTime.tryParse(evaluationCase.startDate);
    final end = DateTime.tryParse(evaluationCase.endDate);
    if (start == null || end == null) return evaluationCase.dailyRecords.length;
    return end.difference(start).inDays + 1;
  }
}

typedef AiBatchProgressCallback = void Function(
  int completed,
  int total,
  int successes,
  int failures,
);

class AiBatchTestService {
  AiBatchTestService({
    AiBatchAiGateway? gateway,
    AiBatchDatasetService? datasetService,
    DateTime Function()? clock,
  })  : _gateway = gateway ?? ProductionAiBatchGateway(),
        _datasetService = datasetService ?? AiBatchDatasetService(),
        _clock = clock ?? DateTime.now;

  final AiBatchAiGateway _gateway;
  final AiBatchDatasetService _datasetService;
  final DateTime Function() _clock;

  Future<AiBatchRunOutput> run({
    required AiBatchDataset dataset,
    AiBatchProgressCallback? onProgress,
  }) async {
    if (!kDebugMode) {
      throw UnsupportedError('AI 批次測試僅限 Debug 模式。');
    }
    final results = <AiBatchCaseResult>[];
    String? model;
    String? promptVersion;
    var successes = 0;
    var failures = 0;

    for (final evaluationCase in dataset.cases) {
      final stopwatch = Stopwatch()..start();
      try {
        final reply = await _gateway.send(evaluationCase);
        stopwatch.stop();
        model ??= _nonEmpty(reply.model);
        promptVersion ??= _nonEmpty(reply.promptVersion);
        results.add(
          AiBatchCaseResult(
            caseId: evaluationCase.testCaseId,
            success: true,
            response: reply.text,
            elapsedMs: stopwatch.elapsedMilliseconds,
            inputTokens: reply.inputTokens,
            outputTokens: reply.outputTokens,
            input: evaluationCase.toInputJson(),
          ),
        );
        successes++;
      } catch (error, stackTrace) {
        stopwatch.stop();
        debugPrint(
          'AI batch case ${evaluationCase.testCaseId} failed: '
          '$error\n$stackTrace',
        );
        results.add(
          AiBatchCaseResult(
            caseId: evaluationCase.testCaseId,
            success: false,
            response: '',
            elapsedMs: stopwatch.elapsedMilliseconds,
            input: evaluationCase.toInputJson(),
            error: error.toString(),
          ),
        );
        failures++;
      }
      onProgress?.call(
        results.length,
        dataset.cases.length,
        successes,
        failures,
      );
    }

    final result = AiBatchTestResult(
      model: model ?? 'not_reported',
      promptVersion: promptVersion ?? 'not_reported',
      createdAt: _clock(),
      sourceFile: dataset.fileName,
      results: results,
    );
    final filePath = await _datasetService.writeResult(result);
    return AiBatchRunOutput(result: result, filePath: filePath);
  }

  String? _nonEmpty(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
