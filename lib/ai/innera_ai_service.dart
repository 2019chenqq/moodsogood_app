import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

String inneraAiDisplayText(String reply, String? followUpQuestion) {
  if (followUpQuestion == null || followUpQuestion.isEmpty) return reply;
  if (_replyAlreadyAsksFollowUp(reply, followUpQuestion)) return reply;
  return '$reply\n\n$followUpQuestion';
}

bool _replyAlreadyAsksFollowUp(String reply, String followUp) {
  String normalize(String value) =>
      value.replaceAll(RegExp(r'[\s，。！？；：、,.!?;:]'), '').toLowerCase();
  final normalizedReply = normalize(reply);
  final normalizedFollowUp = normalize(followUp);
  if (normalizedFollowUp.isNotEmpty &&
      normalizedReply.contains(normalizedFollowUp)) {
    return true;
  }
  if (!RegExp(r'[？?]').hasMatch(reply)) return false;
  const topics = <String, String>{
    'time': r'什麼時候|何時|幾點|時間|多久',
    'severity': r'幾分|程度|強度|嚴重|多痛',
    'energy': r'能量|精神|精力',
    'appetite': r'食慾|胃口|想吃',
    'activity': r'活動量|活動程度|不想動',
    'sleep': r'睡眠|睡得|入睡|醒來|起床',
    'feeling': r'感覺|感受|心情|情緒',
    'cause': r'發生什麼|什麼事情|原因|為什麼',
  };
  final replyTopics = {
    for (final entry in topics.entries)
      if (RegExp(entry.value).hasMatch(reply)) entry.key,
  };
  final followUpTopics = {
    for (final entry in topics.entries)
      if (RegExp(entry.value).hasMatch(followUp)) entry.key,
  };
  return replyTopics.intersection(followUpTopics).isNotEmpty;
}

class InneraAiResponse {
  const InneraAiResponse({
    required this.reply,
    required this.followUpQuestion,
    required this.sources,
    required this.suggestedActions,
    required this.recordDraft,
    required this.eventDrafts,
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
  final List<Map<String, dynamic>> eventDrafts;
  final AiSafetyLevel safetyLevel;
  final bool requiresFixedSafetyUi;
  final String? model;
  final String? promptVersion;
  final int? inputTokens;
  final int? outputTokens;

  String get displayText => inneraAiDisplayText(reply, followUpQuestion);
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

  // Share one forced Auth refresh across concurrent AI calls. Firebase App
  // Check manages its own token lifecycle; forcing an App Check refresh here
  // can be rate-limited and turn one authentication failure into a retry loop.
  static Future<void>? _authRefreshInFlight;

  Future<InneraAiRecordDraft> summarizeHealthEvents({
    required List<InneraAiMessage> messages,
    required InneraAiRecordDraft draft,
  }) async {
    if (draft.eventDrafts.isEmpty) return draft;
    final relevantMessages = messages
        .where((item) => item.canPersist)
        .where((item) =>
            item.role == InneraAiMessageRole.user ||
            item.role == InneraAiMessageRole.assistant)
        .where((item) => item.safetyLevel == AiSafetyLevel.normal)
        .map((item) => <String, dynamic>{
              'role':
                  item.role == InneraAiMessageRole.user ? 'user' : 'assistant',
              'content': item.text.trim(),
            })
        .where((item) => (item['content'] as String).isNotEmpty)
        .toList();
    try {
      final result = await _functions
          .httpsCallable(AiCallableEndpoints.eventSummaries)
          .call({
        'requestId': createAiRequestId(),
        'messages': relevantMessages,
        'eventDrafts': draft.eventDrafts.map((item) => item.toMap()).toList(),
      }).timeout(const Duration(seconds: 60));
      final data = _asMap(result.data);
      var updated = draft;
      for (final raw in (data['eventSummaries'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final eventId = (raw['eventId'] ?? '').toString().trim();
        final summary = (raw['summary'] ?? '').toString().trim();
        if (eventId.isNotEmpty && summary.isNotEmpty) {
          updated = updated.withEventSummary(eventId, summary);
        }
      }
      return updated;
    } on FirebaseFunctionsException catch (error, stackTrace) {
      logAiCallableFailure(
        functionName: AiCallableEndpoints.eventSummaries,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } on TimeoutException {
      throw const InneraAiException('AI 整理逾時，原對話與事件草稿均已保留。');
    }
  }

  Future<InneraAiResponse> sendMessage({
    required InneraAiMode mode,
    required List<InneraAiMessage> history,
    required String userMessage,
    List<InneraAiTemporaryImage> images = const [],
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
      images: images,
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
    List<InneraAiTemporaryImage> images = const [],
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
      if (images.isNotEmpty)
        'images': images
            .take(10)
            .map((image) => {
                  'storagePath': image.storagePath,
                  'contentType': image.contentType,
                })
            .toList(),
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
      final result = await _callWithTokenRefresh(payload)
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
    } on InneraAiException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('InneraAiService generate failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw const InneraAiException('目前暫時無法取得 AI 回覆，請稍後再試。');
    }
  }

  Future<HttpsCallableResult<dynamic>> _callWithTokenRefresh(
    Map<String, dynamic> payload,
  ) async {
    final callable = _functions.httpsCallable(AiCallableEndpoints.chat);
    try {
      return await callable.call(payload);
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'unauthenticated' ||
          FirebaseAuth.instance.currentUser == null) {
        rethrow;
      }

      // Refresh Auth once. App Check tokens are refreshed automatically by the
      // Firebase SDK; forcing one here can fail with "Too many attempts".
      try {
        await _refreshAuthToken();
      } catch (refreshError, stackTrace) {
        debugPrint('AI callable Auth token refresh failed: $refreshError');
        debugPrintStack(stackTrace: stackTrace);
        throw const InneraAiException(
          '登入驗證暫時無法更新，請稍候再試；若持續發生再重新登入。',
        );
      }
      return callable.call(payload);
    }
  }

  Future<void> _refreshAuthToken() async {
    final activeRefresh = _authRefreshInFlight;
    if (activeRefresh != null) return activeRefresh;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No signed-in Firebase user');
    }
    final refresh = user.getIdToken(true).then<void>((_) {});
    _authRefreshInFlight = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_authRefreshInFlight, refresh)) {
        _authRefreshInFlight = null;
      }
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
      eventDrafts: _mapList(data['eventDrafts']),
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
    final urgent = level == AiSafetyLevel.imminentDanger;
    return InneraAiResponse(
      reply: medical
          ? InneraAiSafetyService.medicalUrgencyReply
          : urgent
              ? InneraAiSafetyService.imminentSelfHarmReply
              : InneraAiSafetyService.concernSelfHarmReply,
      followUpQuestion: null,
      sources: const <AiContextSource>[],
      suggestedActions: const <String>[],
      recordDraft: null,
      eventDrafts: const <Map<String, dynamic>>[],
      safetyLevel: level,
      requiresFixedSafetyUi: true,
      model: null,
      promptVersion: null,
      inputTokens: null,
      outputTokens: null,
    );
  }

  bool _requiresFixedSafetyUi(AiSafetyLevel level) =>
      level == AiSafetyLevel.possibleSelfHarm ||
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

  List<Map<String, dynamic>> _mapList(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : const <Map<String, dynamic>>[];

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
