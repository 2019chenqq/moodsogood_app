import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../ai/innera_ai_message.dart';
import '../../ai/innera_ai_mode.dart';
import '../../ai/innera_ai_service.dart';
import '../../meds/medication_subjective_summary_builder.dart';
import '../models/follow_up_ai_summary.dart';
import 'follow_up_question_parser.dart';

class FollowUpQuestionResult {
  const FollowUpQuestionResult.success(this.questions) : error = null;
  const FollowUpQuestionResult.failure(this.error) : questions = null;

  final List<String>? questions;
  final Object? error;

  bool get isSuccess => questions != null;
}

class FollowUpAiService {
  FollowUpAiService({InneraAiService? inneraAiService})
      : _inneraAiService = inneraAiService ?? InneraAiService();

  final InneraAiService _inneraAiService;

  Future<FollowUpQuestionResult> generateFollowUpQuestions(
      FollowUpAiV1Input input) async {
    if (kDebugMode) {
      debugPrint('FollowUpAiService generateFollowUpQuestions called=true');
    }
    try {
      final response = await _send(
        input,
        '''用藥判讀規則：
1. 只有 currentMedications 或 medicationTimeline 明確存在的藥物，才能詢問藥效、副作用、服藥情況或服用後變化。
2. 研究主題、關鍵字、醫師提及、曾詢問或討論過的藥物，都不代表使用者已取得或正在服用。
3. 自由文字與結構化用藥資料不一致時，一律以 currentMedications 與 medicationTimeline 為準。
4. 不得詢問輸入資料中不存在的具體藥物。
5. 不得把「拿到關鍵字／資訊」理解成「拿到或服用藥物」。

'''
        '''你正在執行「回診摘要補問」。請先檢查 app 已計算好的資料與使用者主題，只針對會明顯影響回診討論的重要缺漏提出 2～4 個簡短問題；不得重問已有明確資料。若沒有重要缺漏可回傳空陣列。questions 陣列只能放實際問題，不得放問候、開場白、前言或「請問：」等引導文字；每個問題必須以「？」結尾。reply 必須只包含以下 JSON，不要 Markdown 或說明：
{"questions":["最近是否有影響日常生活？"]}。即使只有 1 題，也必須回傳 {"questions":["...？"]}；沒有問題時回傳 {"questions":[]}。不得只回傳問題文字。''',
      );
      if (kDebugMode) {
        debugPrint('FollowUpAiService _send success=true');
        debugPrint(
          'FollowUpAiService response replyLength=${response.reply.length} '
          'followUpQuestionExists='
          '${response.followUpQuestion?.trim().isNotEmpty == true}',
        );
        debugPrint(
          'FollowUpAiService replyPreview='
          '${_debugReplyPreview(response.reply)}',
        );
      }
      return parseFollowUpQuestionResponse(
        response.reply,
        input,
        followUpQuestion: response.followUpQuestion,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('FollowUpAiService _send success=false');
        debugPrint(
          'FollowUpAiService errorType=${error.runtimeType} '
          'errorMessage=$error',
        );
        debugPrint(
          'FollowUpAiService failure=ai_request_failed',
        );
      }
      return FollowUpQuestionResult.failure(error);
    }
  }

  @visibleForTesting
  static FollowUpQuestionResult parseFollowUpQuestionResponse(
    String reply,
    FollowUpAiV1Input input, {
    String? followUpQuestion,
  }) {
    final json = _tryReplyJson(reply);
    if (kDebugMode) {
      debugPrint(
        'FollowUpAiService jsonParseSuccess=${json != null} '
        'jsonKeys=${json == null ? const <String>[] : json.keys.toList()}',
      );
    }
    if (json == null || json['questions'] is! List) {
      if (json?['reply'] is String &&
          (json!['reply'] as String).trim() != reply.trim()) {
        final nested = parseFollowUpQuestionResponse(
          json['reply'] as String,
          input,
          followUpQuestion: followUpQuestion,
        );
        if (nested.isSuccess) return nested;
      }
      final transportQuestions = normalizeFollowUpQuestions(
        _canonicalQuestionValues([
          if (followUpQuestion?.trim().isNotEmpty == true) followUpQuestion!,
        ]),
      );
      if (transportQuestions.isNotEmpty) {
        final questions = _filterUnsupportedMedicationQuestions(
          transportQuestions,
          input,
        ).take(4).toList(growable: false);
        if (kDebugMode) {
          debugPrint(
            'FollowUpAiService questionCount raw=1 '
            'normalized=${transportQuestions.length} '
            'medicationFilter=${questions.length}',
          );
        }
        if (questions.isNotEmpty) {
          return FollowUpQuestionResult.success(questions);
        }
        if (kDebugMode) {
          debugPrint(
            'FollowUpAiService failure=medication_filter_removed_all',
          );
        }
        return const FollowUpQuestionResult.failure(
          'medication_filter_removed_all',
        );
      }
      final replyLines = reply
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      final plainTextQuestions = normalizeFollowUpQuestions(
        replyLines
            .map(_cleanListItem)
            .where((line) => line.endsWith('？') || line.endsWith('?')),
      );
      if (replyLines.length > 1 && plainTextQuestions.isNotEmpty) {
        final questions = _filterUnsupportedMedicationQuestions(
          plainTextQuestions,
          input,
        ).take(4).toList(growable: false);
        if (kDebugMode) {
          debugPrint(
            'FollowUpAiService questionCount '
            'raw=${plainTextQuestions.length} '
            'normalized=${plainTextQuestions.length} '
            'medicationFilter=${questions.length}',
          );
        }
        if (questions.isNotEmpty) {
          return FollowUpQuestionResult.success(questions);
        }
        if (kDebugMode) {
          debugPrint(
            'FollowUpAiService failure=medication_filter_removed_all',
          );
        }
        return const FollowUpQuestionResult.failure(
          'medication_filter_removed_all',
        );
      }
      final singleQuestion = _singlePlainTextQuestion(reply);
      if (singleQuestion != null) {
        final normalized = normalizeFollowUpQuestions([singleQuestion]);
        final questions = _filterUnsupportedMedicationQuestions(
          normalized,
          input,
        ).take(4).toList(growable: false);
        if (kDebugMode) {
          debugPrint(
            'FollowUpAiService parserPath=single_plain_text_question '
            'questionCount raw=1 normalized=${normalized.length} '
            'medicationFilter=${questions.length}',
          );
        }
        if (questions.isNotEmpty) {
          return FollowUpQuestionResult.success(questions);
        }
        if (kDebugMode) {
          debugPrint(
            'FollowUpAiService failure=medication_filter_removed_all',
          );
        }
        return const FollowUpQuestionResult.failure(
          'medication_filter_removed_all',
        );
      }
      if (kDebugMode) {
        final failure =
            json == null ? 'invalid_questions_json' : 'invalid_questions_array';
        debugPrint(
            'FollowUpAiService parser questionCount before=unknown after=0');
        debugPrint('FollowUpAiService failure=$failure');
      }
      return FollowUpQuestionResult.failure(
        json == null ? 'invalid_questions_json' : 'invalid_questions_array',
      );
    }
    final rawList = json['questions'] as List;
    final rawQuestions = _questionValues(rawList);
    if (rawList.isNotEmpty && rawQuestions.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          'FollowUpAiService parser questionCount '
          'before=${rawList.length} after=0',
        );
        debugPrint('FollowUpAiService failure=invalid_questions_array');
      }
      return const FollowUpQuestionResult.failure('invalid_questions_array');
    }
    final parsedQuestions = normalizeFollowUpQuestions(
      _canonicalQuestionValues(rawQuestions),
    );
    final questions = _filterUnsupportedMedicationQuestions(
      parsedQuestions,
      input,
    ).take(4).toList(growable: false);
    if (kDebugMode) {
      debugPrint(
        'FollowUpAiService questionCount raw=${rawQuestions.length} '
        'normalized=${parsedQuestions.length} '
        'medicationFilter=${questions.length}',
      );
    }
    // Only an explicitly empty AI array means "no clarification needed".
    // Non-empty content that the parser or safety filter cannot accept is a
    // failure, otherwise malformed output could silently skip clarification.
    if (rawQuestions.isNotEmpty && questions.isEmpty) {
      final failure = parsedQuestions.isEmpty
          ? 'no_valid_questions_after_parsing'
          : 'medication_filter_removed_all';
      if (kDebugMode) {
        debugPrint('FollowUpAiService failure=$failure');
      }
      return FollowUpQuestionResult.failure(failure);
    }
    return FollowUpQuestionResult.success(questions);
  }

  static Iterable<String> _canonicalQuestionValues(Iterable<String> values) =>
      values.map((value) {
        final question = value.trim();
        if (question.isEmpty ||
            question.endsWith('？') ||
            question.endsWith('?')) {
          return question;
        }
        return '$question？';
      });

  static String _debugReplyPreview(String reply) {
    final singleLine = reply
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return singleLine.length <= 120 ? singleLine : singleLine.substring(0, 120);
  }

  static String? _singlePlainTextQuestion(String reply) {
    final value = reply.trim();
    if (value.length < 5 || value.length > 120) return null;
    if (value.contains('\n') || value.contains('\r')) return null;
    if (!value.endsWith('?') && !value.endsWith('？')) return null;
    if (RegExp(r'[{}\[\]]|```').hasMatch(value)) return null;
    if (RegExp(
      r'^(以下|建議|說明|無需|沒有|無重要缺漏|錯誤|error)',
      caseSensitive: false,
    ).hasMatch(value)) {
      return null;
    }
    if (RegExp(r'^(?:#{1,6}\s|[-*+]\s|>\s)').hasMatch(value)) return null;
    return value;
  }

  static List<String> _filterUnsupportedMedicationQuestions(
    Iterable<String> questions,
    FollowUpAiV1Input input,
  ) {
    final currentNames = input.currentMedications
        .map((item) => item['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    final timelineNames = input.medicationTimeline
        .map((item) => item['medicationName']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    final supportedNames = {...currentNames, ...timelineNames};

    bool mentions(Iterable<String> names, String question) {
      final normalizedQuestion = _normalizeMedicationText(question);
      return names.any((name) {
        final normalizedName = _normalizeMedicationText(name);
        return normalizedName.isNotEmpty &&
            normalizedQuestion.contains(normalizedName);
      });
    }

    final source = questions.toList(growable: false);
    final result = <String>[];
    for (final question in source) {
      final asksAboutMedication = RegExp(
        r'藥|服用|服藥|用藥|劑量|漏服|停藥|停用',
      ).hasMatch(question);
      if (!asksAboutMedication) {
        result.add(question);
        continue;
      }

      final claimsCurrentUse =
          RegExp(r'目前(?:正在)?服用|現在(?:正在)?服用').hasMatch(question);
      final supported = mentions(
        claimsCurrentUse ? currentNames : supportedNames,
        question,
      );
      final compactQuestion = question.replaceAll(
        RegExp(r'[，。！？；、\s]'),
        '',
      );
      final genericOnly = RegExp(
        r'^(?:最近)?(?:目前|現在)?(?:的)?(?:服藥|用藥|藥物)(?:情況|狀況|後)?',
      ).hasMatch(compactQuestion);
      final hasStructuredMedication = claimsCurrentUse
          ? currentNames.isNotEmpty
          : supportedNames.isNotEmpty;

      if (supported || (genericOnly && hasStructuredMedication)) {
        result.add(question);
        continue;
      }
    }
    if (kDebugMode && result.length < source.length) {
      debugPrint(
        'FollowUpAiService medicationFilter '
        'questionCountBefore=${source.length} '
        'questionCountAfter=${result.length} '
        'reason=medication_not_in_structured_data',
      );
    }
    return result;
  }

  static String _normalizeMedicationText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s，。！？；、,.!?;：:（）()「」『』\-_/]'), '');

  @visibleForTesting
  static List<String> filterMedicationQuestionsForTesting(
    Iterable<String> questions,
    FollowUpAiV1Input input,
  ) =>
      _filterUnsupportedMedicationQuestions(questions, input);

  Future<FollowUpAiOutput> generateSummary(
    FollowUpAiV1Input input, {
    Map<String, String> followUpAnswers = const {},
  }) async {
    final response = await _send(
      input,
      '''你正在產生可供回診使用的資料摘要。補問題目與原始回答只供這次整理使用，不得逐字放入任何輸出欄位：${jsonEncode(followUpAnswers)}
以下規則優先於後文：discussionDetails 是使用者原文，由 App 另行逐字顯示，AI 不得改寫、摘要、複製或放入任何輸出欄位。discussionItems 只可整理有內容的補問回答，沒有回答時必須是空陣列；內容若只是重複 discussionDetails 已明確寫過的資訊，也必須略過。
只能描述資料支持的觀察與日期先後；不得診斷躁期或鬱期、不得斷言或暗示藥物因果、不得建議自行停藥或調藥。coOccurrenceSummary.clusters 是唯一可使用的共現結果，只能整理既有 coreItems、companionItems 與客觀次數，不得新增模式或使用「導致、造成、引發、證明、副作用、高度相關」等因果式文字。有價值的日期先後資訊可放入 keyChanges，但不得與 App 的藥物調整時間軸逐字重複。睡眠、症狀及其他基本紀錄只能放在 keyChanges，不得放入 userSharedNotes。請把已選主題、discussionDetails，以及有內容的補問題目與答案整合成 discussionItems：共 1～5 項，每項為可直接提供醫師閱讀的完整中性句子；合併相近內容，移除口語贅詞、聊天語氣、表情符號與重複內容；保留使用者明確提到的時間、頻率、程度及生活影響；不得加入未說過的資訊。discussionItems 不得保留 Q／A 格式，也不得出現「使用者回答」、「AI 提問」、「AI 補問」、「問題一」、「問：」或「答：」。userSharedNotes 只可忠實保留 additionalNotes，不得放入任何補問原始回答，不得擴寫、推測或放入症狀、睡眠、情緒、藥物、身體數據。若 diaryContext 不為空，必須逐篇檢視每一則日記，只要內容包含重要生活事件、主觀感受、睡眠或症狀補充、想告訴醫師的事情、正向事件或成就，就必須為該篇產生至少一筆對應的 diaryHighlights 候選（同一篇最多 2 筆）；只有在該篇完全沒有可用內容時才可略過，不得因保守或不確定而整體省略 diaryHighlights。日記提到藥名不得視為目前用藥；不得依日記判定躁期、鬱期或診斷；與結構化資料衝突時以結構化資料為準。diaryHighlights 只摘要原意，不得加入醫療推論。主要變化不得重複睡眠卡已有的平均、最低、最高與事件天數；睡眠只在 App 提供的 comparison 顯示明顯增減時，簡短描述與前期相差多少。keyChanges 必須 3～5 項。請將下列格式的摘要 JSON 序列化後放在 reply 字串中，不要在 reply 加入 Markdown 或其他說明：
注意：後端的結構化輸出會直接使用下列摘要欄位；請勿建立 reply 欄位或把摘要 JSON 再序列化成字串。直接回傳：
{"keyChanges":["主要變化一（附資料）","主要變化二（附資料）","主要變化三（附資料）"],"discussionItems":["可直接提供醫師閱讀的完整句子。"],"userSharedNotes":[],"dataLimitations":[],"diaryHighlights":[{"date":"YYYY-MM-DD","category":"life_event|subjective_feeling|sleep_note|symptom_note|share_with_doctor","summary":"忠於原意的簡短摘要","source":"diary"}]}''',
    );
    final json = _tryReplyJson(response.reply);
    if (json != null) {
      final parsed = _summaryFromJson(json);
      if (parsed != null) {
        return _withStructuredMedicationTimeline(
          parsed,
          input,
          followUpAnswers: followUpAnswers,
        );
      }
      _debugParseFailure('summary_shape', response.reply,
          'required fields are not valid string arrays');
    } else {
      _debugParseFailure('json_decode', response.reply, 'no valid JSON object');
    }
    return _fallbackSummary(input, followUpAnswers: followUpAnswers);
  }

  Future<InneraAiResponse> _send(FollowUpAiV1Input input, String instruction) {
    return _inneraAiService.sendMessageWithContext(
      mode: InneraAiMode.recentReview,
      history: const <InneraAiMessage>[],
      userMessage: instruction,
      context: <String, dynamic>{
        'followUpAiV1': input.toJson(),
        'safetyContract': const {
          'diagnosis': false,
          'episodeClassification': false,
          'medicationCausality': false,
          'medicationChangeAdvice': false,
        },
      },
      contextSources: <AiContextSource>[
        AiContextSource(
          label: '上次到本次回診期間的結構化健康紀錄',
          dateRange:
              '${_date(input.statistics.periodStart)}～${_date(input.statistics.periodEnd)}',
          count: input.statistics.validRecordDays,
        ),
      ],
    );
  }

  static Map<String, dynamic>? _tryReplyJson(String reply) {
    final text = reply.trim();
    final candidates = <String>[];
    candidates.add(text);
    for (final match in RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).allMatches(text)) {
      candidates.add(match.group(1)!.trim());
    }
    candidates.addAll(_balancedJsonObjects(text));
    for (var candidate in candidates) {
      candidate = candidate.replaceAllMapped(
        RegExp(r',\s*([}\]])'),
        (match) => match.group(1)!,
      );
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } on FormatException {
        // Try the next repair candidate.
      }
    }
    return null;
  }

  static Iterable<String> _balancedJsonObjects(String text) sync* {
    for (var start = 0; start < text.length; start++) {
      if (text.codeUnitAt(start) != 123) continue;
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var index = start; index < text.length; index++) {
        final code = text.codeUnitAt(index);
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (code == 92) {
            escaped = true;
          } else if (code == 34) {
            inString = false;
          }
          continue;
        }
        if (code == 34) {
          inString = true;
        } else if (code == 123) {
          depth++;
        } else if (code == 125 && --depth == 0) {
          yield text.substring(start, index + 1);
          break;
        }
      }
    }
  }

  static FollowUpAiOutput? _summaryFromJson(Map<String, dynamic> json) {
    List<String>? list(String key, {bool optional = false}) {
      final value = json[key];
      if (value == null && optional) return const [];
      if (value is! List) return null;
      return value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    final keyChanges = list('keyChanges');
    final discussionItems = json.containsKey('discussionItems')
        ? list('discussionItems')
        : list('discussionPriorities');
    final sharedNotes = json.containsKey('userSharedNotes')
        ? list('userSharedNotes', optional: true)
        : list('userReportedConcerns', optional: true);
    final limitations = list('dataLimitations');
    final diaryHighlights = _diaryHighlightValues(json['diaryHighlights']);
    if (keyChanges == null ||
        keyChanges.length < 3 ||
        keyChanges.length > 5 ||
        discussionItems == null ||
        discussionItems.length > 5 ||
        sharedNotes == null ||
        limitations == null) {
      return null;
    }
    return FollowUpAiOutput(
      keyChanges: keyChanges,
      discussionPriorities: const [],
      discussionItems: discussionItems,
      timelineRelations: const [],
      medicationSubjectiveSummaries:
          _strings(json['medicationSubjectiveSummaries']),
      recordEvidenceHighlights: _strings(json['recordEvidenceHighlights']),
      userSharedNotes: sharedNotes,
      diaryHighlights: diaryHighlights,
      dataLimitations: limitations,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  static List<FollowUpDiaryHighlight> _diaryHighlightValues(dynamic value) {
    const categories = {
      'life_event',
      'subjective_feeling',
      'sleep_note',
      'symptom_note',
      'share_with_doctor',
    };
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => FollowUpDiaryHighlight.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) =>
            item.date.isNotEmpty &&
            categories.contains(item.category) &&
            item.summary.isNotEmpty &&
            item.source == 'diary')
        .toList(growable: false);
  }

  static void _debugParseFailure(
    String stage,
    String reply,
    String error,
  ) {
    if (!kDebugMode) return;
    final singleLine = reply
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final preview = singleLine.length <= 500
        ? singleLine
        : '${singleLine.substring(0, 500)}…';
    debugPrint(
      'FollowUpAiService parse failed: stage=$stage, error=$error, '
      'replyLength=${reply.length}, replyPreview=$preview',
    );
  }

  static FollowUpAiOutput _fallbackSummary(
    FollowUpAiV1Input input, {
    Map<String, String> followUpAnswers = const {},
  }) {
    final statistics = input.statistics;
    final keyChanges = <String>[];
    // Never copy malformed model output into a clinical-facing fallback.
    const malformedReply = '';
    final aiLines = malformedReply
        .split(RegExp(r'[\r\n]+'))
        .map(_cleanListItem)
        .where((line) => line.length >= 8 && line.length <= 220)
        .where((line) => !line.contains('{') && !line.contains('"'))
        .where((line) => !RegExp(
              r'^(主要變化|時間關聯|優先討論|使用者|資料限制)',
            ).hasMatch(line))
        .take(2);
    keyChanges.addAll(aiLines);
    keyChanges.add(
      '${_date(statistics.periodStart)}～${_date(statistics.periodEnd)}共有 '
      '${statistics.validRecordDays} 天有效紀錄。',
    );
    final sleepChange = _sleepComparisonText(input.sleep);
    if (sleepChange != null) keyChanges.add(sleepChange);
    if (input.highFrequencySymptoms.isNotEmpty) {
      final symptom = input.highFrequencySymptoms.first;
      keyChanges.add(
        '${symptom['name']}在統計期間出現 ${symptom['occurrenceDays']} 天。',
      );
    }
    while (keyChanges.length < 3) {
      keyChanges.add('目前可用紀錄較少，這次摘要以使用者提供的內容為主要依據。');
    }

    final sharedNotes = <String>[
      if (input.additionalNotes.trim().isNotEmpty) input.additionalNotes.trim(),
    ];
    final limitations = input.dataLimitations.toSet().toList();
    final evidenceHighlights = _recordEvidenceHighlights(input);
    return FollowUpAiOutput(
      keyChanges: keyChanges.take(5).toList(),
      discussionPriorities: const [],
      discussionItems: const [],
      timelineRelations: MedicationSubjectiveSummaryBuilder.fallbackSummaries(
        input.medicationSubjectiveReports,
      ),
      medicationSubjectiveSummaries:
          MedicationSubjectiveSummaryBuilder.fallbackSummaries(
        input.medicationSubjectiveReports,
      ),
      recordEvidenceHighlights: evidenceHighlights,
      followUpResponses: _followUpResponses(followUpAnswers),
      userSharedNotes: sharedNotes,
      dataLimitations: limitations,
      generatedAt: DateTime.now().toUtc(),
      usedFallback: true,
    );
  }

  static String _compactNumber(dynamic value) {
    if (value is! num) return value.toString();
    final number = value.toDouble();
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number
        .toString()
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static List<String> _withoutDuplicateSleepDetails(
    Map<String, dynamic> sleep,
    Iterable<String> source,
  ) {
    final values =
        source.where((item) => !item.contains('睡眠')).toList(growable: true);
    final comparison = _sleepComparisonText(sleep);
    if (comparison != null) values.add(comparison);
    return values;
  }

  static String? _sleepComparisonText(Map<String, dynamic> sleep) {
    final duration = sleep['durationHours'];
    if (duration is! Map) return null;
    final comparison = duration['comparison'];
    if (comparison is! Map || comparison['change'] is! num) return null;
    final change = (comparison['change'] as num).toDouble();
    if (change.abs() < .4) return null;
    final direction = change > 0 ? '增加' : '減少';
    return '睡眠時間較前期$direction：${_compactNumber(change.abs())}小時';
  }

  static FollowUpAiOutput _withStructuredMedicationTimeline(
    FollowUpAiOutput output,
    FollowUpAiV1Input input, {
    Map<String, String> followUpAnswers = const {},
  }) {
    final medicationSubjectiveSummaries =
        _resolvedMedicationSubjectiveSummaries(
      output.medicationSubjectiveSummaries,
      input.medicationSubjectiveReports,
    );
    final userSharedNotes = <String>{
      if (input.additionalNotes.trim().isNotEmpty) input.additionalNotes.trim(),
    }.toList();
    // Only block items that merely echo the raw question text (i.e. the AI
    // repeated the prompt instead of summarizing an answer). Items that
    // reflect the user's actual answer must be kept, or the follow-up
    // question's information disappears from the summary entirely.
    final blockedQuestionKeys = _followUpQuestionKeys(followUpAnswers);
    final keyChanges = _withoutMedicationTimelineDuplicates(
      input,
      _withoutDuplicateSleepDetails(
        input.sleep,
        output.keyChanges.where(
          (item) =>
              !FollowUpSummaryTextFormatter.isQuestionAnswerTranscript(item) &&
              !blockedQuestionKeys.contains(_summaryComparisonKey(item)),
        ),
      ),
    );
    if (keyChanges.length < 3) {
      final seen = keyChanges.map(_summaryComparisonKey).toSet();
      for (final candidate in _fallbackSummary(
        input,
        followUpAnswers: followUpAnswers,
      ).keyChanges) {
        if (seen.add(_summaryComparisonKey(candidate))) {
          keyChanges.add(candidate);
        }
        if (keyChanges.length == 3) break;
      }
    }
    final discussionItems = _safeGeneratedDiscussionItems(
      output.discussionItems.isNotEmpty
          ? output.discussionItems
          : output.discussionPriorities,
      followUpAnswers,
    );
    return FollowUpAiOutput(
      keyChanges: keyChanges.take(5).toList(growable: false),
      discussionPriorities: const [],
      discussionItems: _withoutDiscussionDetailsDuplicates(
        discussionItems,
        input.discussionDetails,
      ),
      medicationSubjectiveSummaries: medicationSubjectiveSummaries,
      recordEvidenceHighlights: output.recordEvidenceHighlights.isNotEmpty
          ? output.recordEvidenceHighlights
          : _recordEvidenceHighlights(input),
      followUpResponses: _followUpResponses(followUpAnswers),
      timelineRelations: medicationSubjectiveSummaries,
      // This section is reserved for the user's own preparation text; recorded
      // symptoms must not be relabeled as an actively shared concern.
      userSharedNotes: userSharedNotes.toList(),
      diaryHighlights: output.diaryHighlights,
      dataLimitations: output.dataLimitations,
      generatedAt: output.generatedAt,
      usedFallback: output.usedFallback ||
          output.medicationSubjectiveSummaries.any(
            (item) => !MedicationSubjectiveSummaryBuilder.isSafeAiSummary(item),
          ),
    );
  }

  static List<String> _recordEvidenceHighlights(FollowUpAiV1Input input) {
    final result = <String>[];
    for (final symptom in input.highFrequencySymptoms.take(3)) {
      final name = symptom['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final days = symptom['occurrenceDays'] ?? 0;
      final events = symptom['eventCount'] ?? 0;
      final maxSeverity = symptom['maxSeverity'];
      result.add(
        '$name 出現 $days 個記錄日；快速記錄共 $events 次'
        '${maxSeverity == null ? '' : '，最高強度 $maxSeverity/5'}。',
      );
    }

    final clusters = input.coOccurrenceSummary['clusters'];
    if (clusters is List) {
      for (final raw in clusters.whereType<Map>().take(3)) {
        final core = _strings(raw['coreItems']);
        final companions = _strings(raw['companionItems']);
        final count = raw['occurrenceCount'];
        final nearby = raw['nearbyTimeCount'];
        if (core.length < 2 || count is! num) continue;
        final sentence = StringBuffer(
          '${core.join('、')}於觀察期間重複共同出現 ${count.toInt()} 次',
        );
        if (nearby is num && nearby > 0) {
          sentence.write('，其中 ${nearby.toInt()} 次發生於相近時間');
        }
        if (companions.isNotEmpty) {
          sentence.write('；另常伴隨${companions.join('、')}');
        }
        sentence.write('。');
        result.add(sentence.toString());
      }
    }
    return result.take(5).toList(growable: false);
  }

  static List<String> _resolvedMedicationSubjectiveSummaries(
    Iterable<String> aiSummaries,
    Iterable<Map<String, dynamic>> structuredReports,
  ) {
    final safeSummaries = aiSummaries
        .map((item) => item.trim())
        .where((item) =>
            item.isNotEmpty &&
            MedicationSubjectiveSummaryBuilder.isSafeAiSummary(item))
        .toList(growable: false);
    final aiCount = aiSummaries
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .length;
    if (aiCount == 0) return const [];
    if (safeSummaries.length == aiCount) return safeSummaries;
    return MedicationSubjectiveSummaryBuilder.fallbackSummaries(
      structuredReports,
    );
  }

  static List<String> _withoutMedicationTimelineDuplicates(
    FollowUpAiV1Input input,
    Iterable<String> keyChanges,
  ) {
    final medicationKeys = input.medicationTimeline
        .map(formatMedicationTimelineEvent)
        .map(_summaryComparisonKey)
        .where((value) => value.isNotEmpty)
        .toSet();
    return keyChanges
        .where((item) => !medicationKeys.contains(_summaryComparisonKey(item)))
        .toList(growable: true);
  }

  static String _summaryComparisonKey(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s，。！？；、,.!?;：:]'), '');

  @visibleForTesting
  static FollowUpAiOutput? parseSummaryReplyForTesting(String reply) {
    final json = _tryReplyJson(reply);
    return json == null ? null : _summaryFromJson(json);
  }

  @visibleForTesting
  static FollowUpAiOutput applySelectionRulesForTesting(
    FollowUpAiOutput output,
    FollowUpAiV1Input input, {
    Map<String, String> followUpAnswers = const {},
  }) =>
      _withStructuredMedicationTimeline(
        output,
        input,
        followUpAnswers: followUpAnswers,
      );

  @visibleForTesting
  static FollowUpAiOutput fallbackSummaryForTesting(
    FollowUpAiV1Input input, {
    Map<String, String> followUpAnswers = const {},
  }) =>
      _fallbackSummary(input, followUpAnswers: followUpAnswers);

  static List<String> _safeGeneratedDiscussionItems(
    Iterable<String> values,
    Map<String, String> followUpAnswers,
  ) {
    final blockedQuestionKeys = _followUpQuestionKeys(followUpAnswers);
    return FollowUpSummaryTextFormatter.safeDiscussionItems(values)
        .where((item) =>
            !blockedQuestionKeys.contains(_summaryComparisonKey(item)))
        .take(5)
        .toList(growable: false);
  }

  static List<String> _withoutDiscussionDetailsDuplicates(
    Iterable<String> values,
    String discussionDetails,
  ) {
    final detailsKey = _summaryComparisonKey(discussionDetails);
    if (detailsKey.isEmpty) return values.toList(growable: false);
    return values.where((item) {
      final itemKey = _summaryComparisonKey(item);
      return itemKey.isNotEmpty && !detailsKey.contains(itemKey);
    }).toList(growable: false);
  }

  /// Only the literal question text is blocked here: an item that merely
  /// repeats the prompt back conveys no information. An item that reflects
  /// the user's actual answer must be kept, otherwise the follow-up
  /// question's content disappears from the summary entirely.
  static Set<String> _followUpQuestionKeys(Map<String, String> answers) => {
        for (final entry in answers.entries)
          if (entry.key.trim().isNotEmpty) _summaryComparisonKey(entry.key),
      };

  static List<Map<String, String>> _followUpResponses(
    Map<String, String> answers,
  ) =>
      answers.entries
          .where((entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          .map((entry) => {
                'question': entry.key.trim(),
                'answer': entry.value.trim(),
              })
          .toList(growable: false);

  static String formatMedicationTimelineEvent(Map<String, dynamic> event) {
    final date = event['date']?.toString().trim() ?? '';
    final name = event['medicationName']?.toString().trim() ?? '';
    final prefix = [date, name].where((part) => part.isNotEmpty).join(' ');
    final type = event['type']?.toString().trim() ?? '';
    final beforeDose = _dose(event['beforeDose']);
    final afterDose = _dose(event['afterDose']);
    final rawBeforeUnit = event['beforeUnit']?.toString().trim() ?? '';
    final rawAfterUnit = event['afterUnit']?.toString().trim() ?? '';
    final beforeUnit = rawBeforeUnit.isEmpty ? rawAfterUnit : rawBeforeUnit;
    final afterUnit = rawAfterUnit.isEmpty ? rawBeforeUnit : rawAfterUnit;
    final beforeTimes = _strings(event['beforeTimes']).join('、');
    final afterTimes = _strings(event['afterTimes']).join('、');

    String doseWithUnit(String? dose, String unit) =>
        dose == null ? '' : '$dose${unit.isEmpty ? '' : ' $unit'}';
    String doseChange(String label) {
      final before = doseWithUnit(beforeDose, beforeUnit);
      final after = doseWithUnit(afterDose, afterUnit);
      if (before.isNotEmpty && after.isNotEmpty && before != after) {
        return '$label：$before → $after';
      }
      final value = after.isNotEmpty ? after : before;
      return value.isEmpty ? label : '劑量：$value';
    }

    final detail = switch (type) {
      'scheduleChanged' => beforeTimes.isNotEmpty &&
              afterTimes.isNotEmpty &&
              beforeTimes != afterTimes
          ? '服藥時間：$beforeTimes → $afterTimes'
          : (afterTimes.isNotEmpty || beforeTimes.isNotEmpty)
              ? '服藥時間：${afterTimes.isNotEmpty ? afterTimes : beforeTimes}'
              : '服藥時間調整',
      'added' => afterDose == null
          ? '新增'
          : '新增，劑量 ${doseWithUnit(afterDose, afterUnit)}',
      'increased' => doseChange('劑量增加'),
      'decreased' => doseChange('劑量減少'),
      'doseChanged' => doseChange('劑量調整'),
      'stopped' => '停用',
      'resumed' => afterDose == null
          ? '恢復使用'
          : '恢復使用，劑量 ${doseWithUnit(afterDose, afterUnit)}',
      _ => type,
    };
    return [prefix, detail].where((part) => part.isNotEmpty).join('：');
  }

  static String? _dose(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().trim() ?? '');
    if (number == null) return null;
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  static String _cleanListItem(String value) =>
      value.trim().replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)、])\s*'), '').trim();

  static List<String> _strings(dynamic value) => value is List
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];

  static Iterable<String> _questionValues(dynamic value) {
    if (value is String) return [value];
    return _strings(value);
  }

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
