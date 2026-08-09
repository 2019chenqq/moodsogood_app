import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ai/innera_ai_message.dart';
import '../ai/innera_ai_mode.dart';
import '../ai/innera_ai_service.dart';
import '../meds/medication_subjective_summary_builder.dart';
import '../models/follow_up_ai_summary.dart';
import 'follow_up_question_parser.dart';

class FollowUpAiService {
  FollowUpAiService({InneraAiService? inneraAiService})
      : _inneraAiService = inneraAiService ?? InneraAiService();

  final InneraAiService _inneraAiService;

  static const _subjectiveMarker = '__med_subjective__:';
  static const _medicationSubjectiveInstruction = '''

若 followUpAiV1.medicationSubjectiveReports 不為空，請依每個 changeRecordId 分組，按 followUpDay 3、7、14、28 整理為一段簡短純文字，放入 medicationSubjectiveSummaries 陣列，順序與輸入群組一致。只能整理 overallResponse、changedAreas、perceivedRelation、otherFactors、note；合併重複資訊，不逐筆照抄。只有一次回報時不得描述趨勢；資料矛盾時直接描述前後變化，不解釋原因。perceivedRelation 為 unsure 或有 otherFactors 時必須保留不確定性。固定使用「使用者主觀回報」、「使用者認為」、「同期紀錄顯示」等中性措辭。不得判定藥物有效或無效、判定副作用、推論因果、診斷，或建議增減藥、停藥、換藥。沒有資料時 medicationSubjectiveSummaries 必須是空陣列。
JSON 另包含："medicationSubjectiveSummaries":[]。
''';

  Future<List<String>> generateFollowUpQuestions(
      FollowUpAiV1Input input) async {
    final response = await _send(
      input.copyWith(medicationSubjectiveReports: const []),
      '''你正在執行「回診摘要補問」。請先檢查 app 已計算好的資料與使用者主題，只針對會明顯影響回診討論的重要缺漏提出 2～4 個簡短問題；不得重問已有明確資料。若沒有重要缺漏可回傳空陣列。questions 陣列只能放實際問題，不得放問候、開場白、前言或「請問：」等引導文字；每個問題必須以「？」結尾。reply 必須只包含以下 JSON，不要 Markdown 或說明：
{"questions":["問題一"]}''',
    );
    final json = _tryReplyJson(response.reply);
    if (json != null) {
      final questions = normalizeFollowUpQuestions(
        _questionValues(json['questions']),
      );
      if (questions.isNotEmpty) return questions.take(4).toList();
    }
    final fallback = normalizeFollowUpQuestions([
      if (response.followUpQuestion?.trim().isNotEmpty == true)
        response.followUpQuestion!.trim(),
      ...response.reply
          .split(RegExp(r'[\r\n]+'))
          .map(_cleanListItem)
          .where((line) => line.endsWith('？') || line.endsWith('?')),
    ]);
    return fallback.take(4).toList();
  }

  Future<FollowUpAiOutput> generateSummary(
    FollowUpAiV1Input input, {
    Map<String, String> followUpAnswers = const {},
  }) async {
    try {
      final response = await _sendSummary(
        input,
      '''你正在產生可供回診使用的資料摘要。補問與回答如下：${jsonEncode(followUpAnswers)}
只能描述資料支持的觀察與時間關聯；不得診斷躁期或鬱期、不得斷言藥物因果、不得建議自行停藥或調藥。睡眠、藥物時間軸、症狀及其他基本紀錄只能放在 keyChanges 或 timelineRelations，不得放入 userSharedNotes。discussionPriorities 整理已選主題、使用者的 discussionDetails 與適合優先詢問醫師的事項。userSharedNotes 只可忠實保留 additionalNotes，以及補問中明確屬於自由補充的使用者原文，不得擴寫、推測或放入症狀、睡眠、情緒、藥物、身體數據。主要變化使用簡短的「欄位：數值」格式；睡眠時數分成「睡眠平均時間：X小時」、「最低：X小時」、「最高：X小時」，不要把期間、趨勢、最低與最高塞在同一句。keyChanges 必須 3～5 項。請將下列格式的摘要 JSON 序列化後放在 reply 字串中，不要在 reply 加入 Markdown 或其他說明：
{"keyChanges":["主要變化一（附資料）","主要變化二（附資料）","主要變化三（附資料）"],"discussionPriorities":[],"timelineRelations":[],"userSharedNotes":[],"dataLimitations":[]}''',
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
        _debugParseFailure(
            'json_decode', response.reply, 'no valid JSON object');
      }
    } catch (error, stackTrace) {
      debugPrint('FollowUpAiService summary generation failed: $error');
      if (kDebugMode) debugPrint('$stackTrace');
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

  Future<InneraAiResponse> _sendSummary(
    FollowUpAiV1Input input,
    String instruction,
  ) =>
      _send(input, '$instruction$_medicationSubjectiveInstruction');

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
    final priorities = list('discussionPriorities');
    final timeline = list('timelineRelations');
    final subjectiveSummaries =
        list('medicationSubjectiveSummaries', optional: true);
    final sharedNotes = json.containsKey('userSharedNotes')
        ? list('userSharedNotes', optional: true)
        : list('userReportedConcerns', optional: true);
    final limitations = list('dataLimitations');
    if (keyChanges == null ||
        keyChanges.length < 3 ||
        keyChanges.length > 5 ||
        priorities == null ||
        timeline == null ||
        subjectiveSummaries == null ||
        sharedNotes == null ||
        limitations == null) {
      return null;
    }
    return FollowUpAiOutput(
      keyChanges: keyChanges,
      discussionPriorities: priorities,
      timelineRelations: [
        ...timeline,
        ...subjectiveSummaries.map((item) => '$_subjectiveMarker$item'),
      ],
      userSharedNotes: sharedNotes,
      dataLimitations: limitations,
      generatedAt: DateTime.now().toUtc(),
    );
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
    final selectedTopics =
        input.discussionTopics.where((topic) => topic.selected).toList();
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
    final sleepDuration = input.sleep['durationHours'];
    if (sleepDuration is Map && sleepDuration['average'] != null) {
      keyChanges.add('睡眠平均時間：${_compactNumber(sleepDuration['average'])}小時');
      if (sleepDuration['minimum'] is num) {
        keyChanges.add('最低：${_compactNumber(sleepDuration['minimum'])}小時');
      }
      if (sleepDuration['maximum'] is num) {
        keyChanges.add('最高：${_compactNumber(sleepDuration['maximum'])}小時');
      }
    }
    if (input.highFrequencySymptoms.isNotEmpty) {
      final symptom = input.highFrequencySymptoms.first;
      keyChanges.add(
        '${symptom['name']}在統計期間出現 ${symptom['occurrenceDays']} 天。',
      );
    }
    while (keyChanges.length < 3) {
      keyChanges.add('目前可用紀錄較少，這次摘要以使用者提供的內容為主要依據。');
    }

    final priorities =
        selectedTopics.map((topic) => topic.label).toSet().toList();
    final sharedNotes = <String>[
      if (input.additionalNotes.trim().isNotEmpty) input.additionalNotes.trim(),
      ..._freeSupplementAnswers(followUpAnswers),
    ];
    final timeline = input.medicationTimeline
        .take(5)
        .map(formatMedicationTimelineEvent)
        .where((item) => item.isNotEmpty)
        .toList()
      ..addAll(
        MedicationSubjectiveSummaryBuilder.fallbackSummaries(
          input.medicationSubjectiveReports,
        ),
      );
    final limitations = input.dataLimitations.toSet().toList();
    return FollowUpAiOutput(
      keyChanges: keyChanges.take(5).toList(),
      discussionPriorities: priorities,
      timelineRelations: timeline,
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

  static FollowUpAiOutput _withStructuredMedicationTimeline(
    FollowUpAiOutput output,
    FollowUpAiV1Input input, {
    Map<String, String> followUpAnswers = const {},
  }) {
    final userSharedNotes = <String>{
      if (input.additionalNotes.trim().isNotEmpty) input.additionalNotes.trim(),
      ..._freeSupplementAnswers(followUpAnswers),
    }.toList();
    final medicationNames = input.medicationTimeline
        .map((event) => event['medicationName']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    final nonMedicationRelations = output.timelineRelations.where((relation) {
      if (relation.startsWith(_subjectiveMarker)) return false;
      if (medicationNames.any(relation.contains)) return false;
      return !const [
        'scheduleChanged',
        'doseChanged',
        'increased',
        'decreased',
        'added',
        'stopped',
      ].any(relation.contains);
    });
    final medicationRelations = input.medicationTimeline
        .map(formatMedicationTimelineEvent)
        .where((item) => item.isNotEmpty);
    final aiSubjectiveSummaries = output.timelineRelations
        .where((item) => item.startsWith(_subjectiveMarker))
        .map((item) => item.substring(_subjectiveMarker.length).trim())
        .toList();
    final aiSubjectiveIsUsable = input.medicationSubjectiveReports.isNotEmpty &&
        aiSubjectiveSummaries.length ==
            input.medicationSubjectiveReports.length &&
        aiSubjectiveSummaries
            .every(MedicationSubjectiveSummaryBuilder.isSafeAiSummary);
    final subjectiveSummaries = input.medicationSubjectiveReports.isEmpty
        ? const <String>[]
        : aiSubjectiveIsUsable
            ? aiSubjectiveSummaries
            : MedicationSubjectiveSummaryBuilder.fallbackSummaries(
                input.medicationSubjectiveReports,
              );
    return FollowUpAiOutput(
      keyChanges: output.keyChanges,
      // Topic selection controls priorities only. Health evidence remains in
      // key changes and timeline relations regardless of checkbox state.
      discussionPriorities: output.discussionPriorities,
      timelineRelations: [
        ...nonMedicationRelations,
        ...medicationRelations,
        ...subjectiveSummaries,
      ],
      // This section is reserved for the user's own preparation text; recorded
      // symptoms must not be relabeled as an actively shared concern.
      userSharedNotes: userSharedNotes.toList(),
      dataLimitations: output.dataLimitations,
      generatedAt: output.generatedAt,
      usedFallback: output.usedFallback ||
          (input.medicationSubjectiveReports.isNotEmpty &&
              !aiSubjectiveIsUsable),
    );
  }

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
  static FollowUpAiOutput fallbackSummaryForTesting(FollowUpAiV1Input input) =>
      _fallbackSummary(input);

  static List<String> _freeSupplementAnswers(Map<String, String> answers) {
    final freeQuestion = RegExp(r'其他|補充|還有什麼|想讓醫師知道|想跟醫師說');
    return answers.entries
        .where((entry) => freeQuestion.hasMatch(entry.key))
        .map((entry) => entry.value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

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
