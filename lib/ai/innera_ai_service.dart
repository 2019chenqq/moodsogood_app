import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'innera_ai_context_service.dart';
import 'innera_ai_message.dart';
import 'innera_ai_mode.dart';
import 'innera_ai_record_draft.dart';
import 'innera_ai_safety_service.dart';

class InneraAiResponse {
  const InneraAiResponse({
    required this.reply,
    required this.followUpQuestion,
    required this.sources,
    required this.suggestedActions,
    required this.recordDraft,
    required this.safetyLevel,
    required this.requiresFixedSafetyUi,
    required this.model,
  });

  final String reply;
  final String? followUpQuestion;
  final List<AiContextSource> sources;
  final List<String> suggestedActions;
  final Map<String, dynamic>? recordDraft;
  final AiSafetyLevel safetyLevel;
  final bool requiresFixedSafetyUi;
  final String? model;

  String get displayText {
    if (followUpQuestion == null || followUpQuestion!.isEmpty) return reply;
    return '$reply\n\n$followUpQuestion';
  }
}

class InneraAiService {
  InneraAiService({
    InneraAiContextService? contextService,
    InneraAiSafetyService? safetyService,
    FirebaseFunctions? functions,
  })  : _contextService = contextService ?? InneraAiContextService(),
        _safetyService = safetyService ?? InneraAiSafetyService(),
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final InneraAiContextService _contextService;
  final InneraAiSafetyService _safetyService;
  final FirebaseFunctions _functions;

  Future<InneraAiResponse> sendMessage({
    required InneraAiMode mode,
    required List<InneraAiMessage> history,
    required String userMessage,
    InneraAiRecordDraft? recordDraft,
  }) async {
    final localSafety = _safetyService.assess(userMessage);
    if (_requiresFixedSafetyUi(localSafety.level)) {
      return _fixedSafetyResponse(localSafety.level);
    }

    late InneraAiContextBundle contextBundle;
    try {
      contextBundle = await _contextService
          .buildContext(mode: mode, latestUserMessage: userMessage)
          .timeout(const Duration(seconds: 18));
    } catch (error, stackTrace) {
      debugPrint('InneraAiService context failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      contextBundle = const InneraAiContextBundle(
        data: <String, dynamic>{},
        sources: <AiContextSource>[],
        partialFailureMessage: '目前無法載入部分近期紀錄，這次回答只會根據你在對話中提供的內容。',
      );
    }

    final messages = _historyPayload(history, userMessage);
    final payload = <String, dynamic>{
      'mode': mode.systemPromptKey,
      'message': userMessage,
      'messages': messages,
      'context': contextBundle.data,
      'contextSources': contextBundle.sources.map(_sourcePayload).toList(),
      if (recordDraft != null) 'recordDraft': recordDraft.toCallablePayload(),
    };

    try {
      final result = await _functions
          .httpsCallable('generateInneraAiChat')
          .call(payload)
          .timeout(const Duration(seconds: 60));
      final data = _asMap(result.data);
      final response = _parseResponse(data, contextBundle.sources);
      if (response.requiresFixedSafetyUi) return response;

      final responseSafety = _safetyService.assess(response.reply);
      if (_requiresFixedSafetyUi(responseSafety.level)) {
        return _fixedSafetyResponse(responseSafety.level);
      }
      return response;
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint(
        'generateInneraAiChat failed: '
        'code=${error.code}, message=${error.message}, '
        'details=${error.details}',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } on TimeoutException {
      throw const InneraAiException('目前暫時無法取得 AI 回覆，請稍後再試。');
    } catch (error, stackTrace) {
      debugPrint('InneraAiService generate failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw const InneraAiException('目前暫時無法取得 AI 回覆，請稍後再試。');
    }
  }

  List<Map<String, String>> _historyPayload(
    List<InneraAiMessage> history,
    String userMessage,
  ) {
    final messages = history
        .where((message) => !message.isLoading && !message.isError)
        .where((message) => message.role != InneraAiMessageRole.system)
        .toList();
    if (messages.isNotEmpty &&
        messages.last.role == InneraAiMessageRole.user &&
        messages.last.text.trim() == userMessage.trim()) {
      messages.removeLast();
    }
    return messages
        .skip(messages.length > 12 ? messages.length - 12 : 0)
        .map(
          (message) => <String, String>{
            'role':
                message.role == InneraAiMessageRole.user ? 'user' : 'assistant',
            'content': message.text,
          },
        )
        .toList();
  }

  Map<String, dynamic> _sourcePayload(AiContextSource source) =>
      <String, dynamic>{
        'label': source.label,
        'dateRange': source.dateRange,
        'count': source.count,
      };

  InneraAiResponse _parseResponse(
    Map<String, dynamic> data,
    List<AiContextSource> fallbackSources,
  ) {
    final requiresFixedSafetyUi = data['requiresFixedSafetyUi'] == true;
    final reply = (data['reply'] ?? '').toString().trim();
    if (reply.isEmpty && !requiresFixedSafetyUi) {
      throw const FormatException('Missing AI reply');
    }
    return InneraAiResponse(
      reply: reply,
      followUpQuestion: _optionalText(data['followUpQuestion']),
      sources: _parseSources(data['sources'], fallbackSources),
      suggestedActions: _stringList(data['suggestedActions']),
      recordDraft: _asOptionalMap(data['recordDraft']),
      safetyLevel: _parseSafetyLevel(data['safetyLevel']),
      requiresFixedSafetyUi: requiresFixedSafetyUi,
      model: _optionalText(data['model']),
    );
  }

  InneraAiResponse _fixedSafetyResponse(AiSafetyLevel level) {
    final medical = level == AiSafetyLevel.medicalUrgency;
    return InneraAiResponse(
      reply: medical
          ? InneraAiSafetyService.medicalUrgencyReply
          : InneraAiSafetyService.imminentSelfHarmReply,
      followUpQuestion: null,
      sources: const <AiContextSource>[],
      suggestedActions: const <String>[],
      recordDraft: null,
      safetyLevel: level,
      requiresFixedSafetyUi: true,
      model: null,
    );
  }

  bool _requiresFixedSafetyUi(AiSafetyLevel level) =>
      level == AiSafetyLevel.imminentDanger ||
      level == AiSafetyLevel.medicalUrgency;

  AiSafetyLevel _parseSafetyLevel(dynamic value) {
    final name = value?.toString();
    return AiSafetyLevel.values.firstWhere(
      (level) => level.name == name,
      orElse: () => AiSafetyLevel.normal,
    );
  }

  List<AiContextSource> _parseSources(
    dynamic value,
    List<AiContextSource> fallback,
  ) {
    if (value is! List) return fallback;
    return value
        .whereType<Map>()
        .map((item) {
          final map = _asMap(item);
          return AiContextSource(
            label: (map['label'] ?? '').toString(),
            dateRange: (map['dateRange'] ?? '').toString(),
            count: (map['count'] as num?)?.toInt() ?? 0,
          );
        })
        .where((source) => source.label.isNotEmpty)
        .toList();
  }

  List<String> _stringList(dynamic value) => value is List
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const <String>[];

  Map<String, dynamic> _asMap(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  Map<String, dynamic>? _asOptionalMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  String? _optionalText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class InneraAiException implements Exception {
  const InneraAiException(this.message);

  final String message;

  @override
  String toString() => message;
}
