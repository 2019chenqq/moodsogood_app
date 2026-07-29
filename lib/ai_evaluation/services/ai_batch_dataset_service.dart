import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ai_batch_test_result.dart';

class AiBatchEvaluationCase {
  const AiBatchEvaluationCase({
    required this.testCaseId,
    required this.startDate,
    required this.endDate,
    required this.persona,
    required this.dailyRecords,
    required this.isSynthetic,
    required this.dataPurpose,
  });

  final String testCaseId;
  final String startDate;
  final String endDate;
  final Map<String, dynamic> persona;
  final List<Map<String, dynamic>> dailyRecords;
  final bool isSynthetic;
  final String dataPurpose;

  factory AiBatchEvaluationCase.fromJson(Map<String, dynamic> json) {
    final period =
        (json['period'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AiBatchEvaluationCase(
      testCaseId: (json['testCaseId'] ?? '').toString(),
      startDate: (period['startDate'] ?? '').toString(),
      endDate: (period['endDate'] ?? '').toString(),
      persona: (json['persona'] as Map?)?.cast<String, dynamic>() ?? const {},
      dailyRecords: (json['dailyRecords'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(),
      isSynthetic: json['isSynthetic'] == true,
      dataPurpose: (json['dataPurpose'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toInputJson() => {
        'testCaseId': testCaseId,
        'period': {'startDate': startDate, 'endDate': endDate},
        'persona': persona,
        'dailyRecords': dailyRecords,
        'isSynthetic': isSynthetic,
        'dataPurpose': dataPurpose,
      };
}

class AiBatchDataset {
  const AiBatchDataset({
    required this.file,
    required this.cases,
    required this.version,
    required this.seed,
  });

  final File file;
  final List<AiBatchEvaluationCase> cases;
  final String version;
  final int? seed;

  String get fileName => file.uri.pathSegments.last;
}

class AiBatchDatasetService {
  AiBatchDatasetService({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  Future<Directory> exportsDirectory() async {
    final documents = await _documentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}ai_evaluation_exports',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<List<File>> listFullDatasets() async {
    final directory = await exportsDirectory();
    final files = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) {
      final name = file.uri.pathSegments.last;
      return name.startsWith('ai_evaluation_full_') && name.endsWith('.json');
    }).toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<AiBatchDataset> load(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('評測 JSON 頂層必須是物件。');
    }
    final json = Map<String, dynamic>.from(decoded);
    final rawCases = json['cases'];
    if (rawCases is! List || rawCases.isEmpty) {
      throw const FormatException('評測 JSON 沒有可執行的 cases。');
    }
    if (rawCases.any((item) => item is! Map)) {
      throw const FormatException('評測 JSON 含有格式錯誤的 case。');
    }
    final cases = rawCases
        .whereType<Map>()
        .map((item) => AiBatchEvaluationCase.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
    if (cases.any(
        (item) => !item.isSynthetic || item.dataPurpose != 'ai_evaluation')) {
      throw const FormatException('檔案包含非 AI 評測用的資料，已停止執行。');
    }
    if (cases.any((item) => item.testCaseId.trim().isEmpty)) {
      throw const FormatException('評測 JSON 含有缺少 caseId 的 case。');
    }
    return AiBatchDataset(
      file: file,
      cases: cases,
      version: (json['version'] ?? '').toString(),
      seed: (json['seed'] as num?)?.toInt(),
    );
  }

  Future<String> writeResult(AiBatchTestResult result) async {
    final directory = await exportsDirectory();
    final suffix = _timestamp(result.createdAt);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'ai_evaluation_result_$suffix.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
      flush: true,
    );
    return file.path;
  }

  String _timestamp(DateTime date) => '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}_'
      '${date.hour.toString().padLeft(2, '0')}'
      '${date.minute.toString().padLeft(2, '0')}'
      '${date.second.toString().padLeft(2, '0')}';
}
