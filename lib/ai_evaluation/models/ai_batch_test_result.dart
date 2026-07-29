class AiBatchCaseResult {
  const AiBatchCaseResult({
    required this.caseId,
    required this.success,
    required this.response,
    required this.elapsedMs,
    required this.input,
    this.inputTokens,
    this.outputTokens,
    this.error,
  });

  final String caseId;
  final bool success;
  final String response;
  final int elapsedMs;
  final int? inputTokens;
  final int? outputTokens;
  final Map<String, dynamic> input;
  final String? error;

  Map<String, dynamic> toJson() => {
        'caseId': caseId,
        'success': success,
        'response': response,
        'elapsedMs': elapsedMs,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'input': input,
        if (error != null) 'error': error,
      };

  factory AiBatchCaseResult.fromJson(Map<String, dynamic> json) =>
      AiBatchCaseResult(
        caseId: (json['caseId'] ?? '').toString(),
        success: json['success'] == true,
        response: (json['response'] ?? '').toString(),
        elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
        inputTokens: (json['inputTokens'] as num?)?.toInt(),
        outputTokens: (json['outputTokens'] as num?)?.toInt(),
        input: json['input'] is Map
            ? Map<String, dynamic>.from(json['input'] as Map)
            : const <String, dynamic>{},
        error: json['error']?.toString(),
      );
}

class AiBatchTestResult {
  const AiBatchTestResult({
    required this.model,
    required this.promptVersion,
    required this.createdAt,
    required this.sourceFile,
    required this.results,
  });

  final String model;
  final String promptVersion;
  final DateTime createdAt;
  final String sourceFile;
  final List<AiBatchCaseResult> results;

  int get successCount => results.where((item) => item.success).length;
  int get failureCount => results.length - successCount;
  double get averageElapsedMs {
    final successful = results.where((item) => item.success).toList();
    if (successful.isEmpty) return 0;
    return successful.fold<int>(0, (sum, item) => sum + item.elapsedMs) /
        successful.length;
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'promptVersion': promptVersion,
        'createdAt': createdAt.toIso8601String(),
        'sourceFile': sourceFile,
        'results': results.map((item) => item.toJson()).toList(),
      };

  factory AiBatchTestResult.fromJson(Map<String, dynamic> json) =>
      AiBatchTestResult(
        model: (json['model'] ?? 'unknown').toString(),
        promptVersion: (json['promptVersion'] ?? 'unknown').toString(),
        createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        sourceFile: (json['sourceFile'] ?? '').toString(),
        results: (json['results'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => AiBatchCaseResult.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(),
      );
}

class AiBatchRunOutput {
  const AiBatchRunOutput({required this.result, required this.filePath});

  final AiBatchTestResult result;
  final String filePath;
}
