import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../daily/emotion_dimensions.dart';
import 'ai_callable_diagnostics.dart';
import 'ai_request_id.dart';
import 'innera_ai_chat_image_service.dart';
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
    this.promptVersion,
    this.inputTokens,
    this.outputTokens,
  });

  final String reply;
  final String? followUpQuestion;
  final List<AiContextSource> sources;
  final List<String> suggestedActions;
  final Map<String, dynamic>? recordDraft;
  final AiSafetyLevel safetyLevel;
  final bool requiresFixedSafetyUi;
  final String? model;
  final String? promptVersion;
  final int? inputTokens;
  final int? outputTokens;

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
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: AiCallableEndpoints.region);

  final InneraAiContextService _contextService;
  final InneraAiSafetyService _safetyService;
  final FirebaseFunctions _functions;

  Future<InneraAiResponse> sendMessage({
    required InneraAiMode mode,
    required List<InneraAiMessage> history,
    required String userMessage,
    InneraAiTemporaryImage? image,
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

    return sendMessageWithContext(
      mode: mode,
      history: history,
      userMessage: userMessage,
      image: image,
      context: contextBundle.data,
      contextSources: contextBundle.sources,
      recordDraft: recordDraft,
    );
  }

  /// Uses the same production callable with an explicitly supplied context.
  ///
  /// This is intended for isolated developer tooling, where reading the
  /// signed-in user's Firestore context would contaminate synthetic tests.
  Future<InneraAiResponse> sendMessageWithContext({
    required InneraAiMode mode,
    required List<InneraAiMessage> history,
    required String userMessage,
    required Map<String, dynamic> context,
    required List<AiContextSource> contextSources,
    InneraAiTemporaryImage? image,
    InneraAiRecordDraft? recordDraft,
  }) async {
    final localSafety = _safetyService.assess(userMessage);
    if (_requiresFixedSafetyUi(localSafety.level)) {
      return _fixedSafetyResponse(localSafety.level);
    }

    final messages = _historyPayload(history, userMessage);
    final payload = <String, dynamic>{
      'requestId': createAiRequestId(),
      'mode': mode.systemPromptKey,
      'message': userMessage,
      'messages': messages,
      'context': context,
      'contextSources': contextSources.map(_sourcePayload).toList(),
      if (image != null)
        'image': {
          'storagePath': image.storagePath,
          'contentType': image.contentType,
        },
      'emotionDimensions': kEmotionDimensions
          .map(
            (dimension) => <String, dynamic>{
              'id': dimension.id,
              'displayName': dimension.displayName,
              'aliases': dimension.aliases,
            },
          )
          .toList(),
      if (recordDraft != null) 'recordDraft': recordDraft.toCallablePayload(),
    };

    try {
      final result = await _functions
          .httpsCallable(AiCallableEndpoints.chat)
          .call(payload)
          .timeout(const Duration(seconds: 60));
      final data = _asMap(result.data);
      final response = _parseResponse(data, contextSources);
      if (response.requiresFixedSafetyUi) return response;

      final responseSafety = _safetyService.assess(response.reply);
      if (_requiresFixedSafetyUi(responseSafety.level)) {
        return _fixedSafetyResponse(responseSafety.level);
      }
      return response;
    } on FirebaseFunctionsException catch (error, stackTrace) {
      logAiCallableFailure(
        functionName: AiCallableEndpoints.chat,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } on TimeoutException {
      throw const InneraAiException('AI 回應逾時，請稍後再試；目前草稿已保留。');
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
    const maxMessages = 60;
    const maxCharacters = 48000;
    final selected = <InneraAiMessage>[];
    var characters = 0;
    for (final message in messages.reversed) {
      if (selected.length >= maxMessages) break;
      final nextCharacters = characters + message.text.length;
      if (selected.isNotEmpty && nextCharacters > maxCharacters) break;
      selected.add(message);
      characters = nextCharacters;
    }
    return selected.reversed
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
      promptVersion: _optionalText(data['promptVersion']),
      inputTokens: (data['inputTokens'] as num?)?.toInt(),
      outputTokens: (data['outputTokens'] as num?)?.toInt(),
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
      promptVersion: null,
      inputTokens: null,
      outputTokens: null,
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
