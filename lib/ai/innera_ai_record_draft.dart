import 'package:cloud_firestore/cloud_firestore.dart';

import '../daily/emotion_dimensions.dart';

enum AiDraftSource {
  explicitUserInput,
  aiExtracted,
  existingRecord,
  defaultPendingConfirmation,
}

class AiEmotionDraft {
  const AiEmotionDraft({
    String? name,
    String? rawText,
    this.normalizedDimensionId,
    this.normalizedDimensionName,
    this.score,
    this.source = AiDraftSource.aiExtracted,
    this.mentioned = true,
    this.needsFollowUp = false,
    this.needsConfirmation = false,
    this.confidence = 0,
    this.timeContext,
    this.evidence,
  }) : rawText = rawText ?? name ?? '';

  final String rawText;
  final String? normalizedDimensionId;
  final String? normalizedDimensionName;
  final int? score;
  final AiDraftSource source;
  final bool mentioned;
  final bool needsFollowUp;
  final bool needsConfirmation;
  final double confidence;
  final String? timeContext;
  final String? evidence;

  String get name => normalizedDimensionName ?? rawText;
  String get dedupeKey => normalizedDimensionId ?? 'raw:${rawText.trim()}';
  bool get hasValidDimension =>
      normalizedDimensionId != null &&
      kEmotionDimensionsById[normalizedDimensionId]?.displayName ==
          normalizedDimensionName;

  Map<String, dynamic> toMap() => {
        'rawText': rawText,
        'normalizedDimensionId': normalizedDimensionId,
        'normalizedDimensionName': normalizedDimensionName,
        'value': score?.clamp(1, 5),
        'source': source.name,
        'mentioned': mentioned,
        'needsFollowUp': score == null || needsFollowUp,
        'needsConfirmation': !hasValidDimension || needsConfirmation,
        'confidence': confidence.clamp(0, 1),
        'timeContext': timeContext,
        'evidence': evidence,
      };

  static AiEmotionDraft? tryFromMap(Map<String, dynamic> map) {
    final rawText = _text(map['rawText'] ?? map['name'])?.trim() ?? '';
    final requestedId = _text(map['normalizedDimensionId']);
    final requestedName = _text(map['normalizedDimensionName']);
    EmotionDimensionDefinition? dimension;
    if (requestedId != null) {
      final candidate = kEmotionDimensionsById[requestedId];
      if (candidate != null &&
          (requestedName == null || requestedName == candidate.displayName)) {
        dimension = candidate;
      }
    }
    dimension ??= resolveEmotionDimension(requestedName ?? rawText);
    final rawScore = map['value'] ?? map['score'];
    final parsedScore = (rawScore as num?)?.toInt();
    final score = parsedScore != null && parsedScore >= 1 && parsedScore <= 5
        ? parsedScore
        : null;
    if (rawText.isEmpty && dimension == null) return null;
    final sourceName = map['source']?.toString();
    final rawConfidence = (map['confidence'] as num?)?.toDouble();
    return AiEmotionDraft(
      rawText: rawText.isEmpty ? dimension!.displayName : rawText,
      normalizedDimensionId: dimension?.id,
      normalizedDimensionName: dimension?.displayName,
      score: score,
      source: AiDraftSource.values.firstWhere(
        (value) => value.name == sourceName,
        orElse: () => sourceName == 'explicit'
            ? AiDraftSource.explicitUserInput
            : AiDraftSource.aiExtracted,
      ),
      mentioned: map['mentioned'] != false,
      needsFollowUp: map['needsFollowUp'] == true || score == null,
      needsConfirmation: map['needsConfirmation'] == true || dimension == null,
      confidence: rawConfidence?.clamp(0, 1) ??
          (dimension?.displayName == rawText
              ? 1
              : (dimension == null ? 0 : .9)),
      timeContext: _text(map['timeContext']),
      evidence: _text(map['evidence']),
    );
  }

  AiEmotionDraft copyWith({
    int? score,
    bool clearScore = false,
    EmotionDimensionDefinition? dimension,
  }) =>
      AiEmotionDraft(
        rawText: rawText,
        normalizedDimensionId: dimension?.id ?? normalizedDimensionId,
        normalizedDimensionName:
            dimension?.displayName ?? normalizedDimensionName,
        score: clearScore ? null : score ?? this.score,
        source: source,
        mentioned: mentioned,
        needsFollowUp: clearScore ? true : (score ?? this.score) == null,
        needsConfirmation: dimension != null ? false : needsConfirmation,
        confidence: dimension != null ? 1 : confidence,
        timeContext: timeContext,
        evidence: evidence,
      );

  static String? _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class AiSleepDraft {
  const AiSleepDraft({
    this.sleepTime,
    this.wakeTime,
    this.finalWakeTime,
    this.quality,
    this.midWakeList,
    this.flags = const [],
    this.naps = const [],
  });

  final String? sleepTime;
  final String? wakeTime;
  final String? finalWakeTime;
  final int? quality;
  final String? midWakeList;
  final List<String> flags;
  final List<Map<String, dynamic>> naps;

  bool get hasData =>
      sleepTime != null ||
      wakeTime != null ||
      finalWakeTime != null ||
      quality != null ||
      midWakeList != null ||
      flags.isNotEmpty ||
      naps.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'sleepTime': sleepTime,
        'wakeTime': wakeTime,
        'finalWakeTime': finalWakeTime,
        'quality': quality,
        'midWakeList': midWakeList,
        'flags': flags,
        'naps': naps,
      };

  factory AiSleepDraft.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AiSleepDraft();
    final naps = (map['naps'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    return AiSleepDraft(
      sleepTime: _time(map['sleepTime']),
      wakeTime: _time(map['wakeTime']),
      finalWakeTime: _time(map['finalWakeTime']),
      quality: _score(map['quality']),
      midWakeList: _text(map['midWakeList']),
      flags: (map['flags'] as List?)
              ?.map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList() ??
          const [],
      naps: naps,
    );
  }

  AiSleepDraft merge(AiSleepDraft? patch) {
    if (patch == null) return this;
    return AiSleepDraft(
      sleepTime: patch.sleepTime ?? sleepTime,
      wakeTime: patch.wakeTime ?? wakeTime,
      finalWakeTime: patch.finalWakeTime ?? finalWakeTime,
      quality: patch.quality ?? quality,
      midWakeList: patch.midWakeList ?? midWakeList,
      flags: {...flags, ...patch.flags}.toList(),
      naps: patch.naps.isEmpty ? naps : patch.naps,
    );
  }

  static String? _time(dynamic value) {
    final text = _text(value);
    if (text == null || !RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(text)) {
      return null;
    }
    final parts = text.split(':');
    return '${parts[0].padLeft(2, '0')}:${parts[1]}';
  }

  static int? _score(dynamic value) {
    final score = (value as num?)?.toInt();
    return score != null && score >= 1 && score <= 5 ? score : null;
  }

  static String? _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class InneraAiRecordDraft {
  const InneraAiRecordDraft({
    required this.dateKey,
    this.overallMood,
    this.emotions = const [],
    this.symptoms = const [],
    this.sleep = const AiSleepDraft(),
    this.events = const [],
    this.rawUserEntries = const [],
    this.diaryText = '',
    this.missingFields = const [],
    required this.updatedAt,
    this.confirmed = false,
    this.hasExistingRecord = false,
  }) : moodScale = 5;

  final String dateKey;
  final int moodScale;
  final double? overallMood;
  final List<AiEmotionDraft> emotions;
  final List<String> symptoms;
  final AiSleepDraft sleep;
  final List<String> events;
  final List<String> rawUserEntries;
  final String diaryText;
  final List<String> missingFields;
  final DateTime updatedAt;
  final bool confirmed;
  final bool hasExistingRecord;

  factory InneraAiRecordDraft.empty(DateTime date) => InneraAiRecordDraft(
        dateKey: _dateKey(date),
        updatedAt: DateTime.now(),
      );

  factory InneraAiRecordDraft.fromFirestore(Map<String, dynamic> map) =>
      InneraAiRecordDraft.fromMap(map);

  factory InneraAiRecordDraft.fromMap(Map<String, dynamic> map) {
    final emotionByName = <String, AiEmotionDraft>{};
    final rawEmotions = map['emotionMentions'] is List
        ? map['emotionMentions'] as List
        : (map['emotions'] as List?) ?? const [];
    for (final item in rawEmotions) {
      final parsed = item is Map
          ? AiEmotionDraft.tryFromMap(Map<String, dynamic>.from(item))
          : AiEmotionDraft.tryFromMap({
              'rawText': item.toString(),
              'mentioned': true,
              'needsFollowUp': true,
              'needsConfirmation': true,
            });
      if (parsed != null) emotionByName[parsed.dedupeKey] = parsed;
    }
    return InneraAiRecordDraft(
      dateKey: (map['dateKey'] ?? map['date'] ?? '').toString(),
      overallMood: _doubleInRange(map['overallMood']),
      emotions: emotionByName.values.toList(),
      symptoms: _sanitizeSymptoms(_strings(map['symptoms'])),
      sleep: AiSleepDraft.fromMap(_map(map['sleep'])),
      events: _strings(map['events']),
      rawUserEntries: _strings(map['rawUserEntries']),
      diaryText: (map['diaryText'] ?? '').toString().trim(),
      missingFields: _strings(map['missingFields']),
      updatedAt: _date(map['updatedAt']) ?? DateTime.now(),
      confirmed: map['confirmed'] == true,
      hasExistingRecord: map['hasExistingRecord'] == true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'dateKey': dateKey,
        'moodScale': 5,
        'overallMood': overallMood,
        'emotionMentions': emotions.map((item) => item.toMap()).toList(),
        'symptoms': symptoms,
        'sleep': sleep.toMap(),
        'events': events,
        'rawUserEntries': rawUserEntries,
        'diaryText': diaryText,
        'missingFields': missingFields,
        'updatedAt': Timestamp.fromDate(updatedAt),
        'confirmed': confirmed,
        'hasExistingRecord': hasExistingRecord,
      };

  /// Callable Functions accept JSON-compatible values only. Keep Firestore
  /// Timestamp values out of the AI request payload.
  Map<String, dynamic> toCallablePayload() => {
        'dateKey': dateKey,
        'moodScale': 5,
        'overallMood': overallMood,
        'emotionMentions': emotions.map((item) => item.toMap()).toList(),
        'symptoms': symptoms,
        'sleep': sleep.toMap(),
        'events': events,
        'rawUserEntries': rawUserEntries,
        'diaryText': diaryText,
        'missingFields': missingFields,
        'updatedAt': updatedAt.toIso8601String(),
        'confirmed': confirmed,
        'hasExistingRecord': hasExistingRecord,
      };

  InneraAiRecordDraft mergePatch(
    Map<String, dynamic>? patch, {
    String? rawUserEntry,
  }) {
    if (patch == null) return _withRawEntry(rawUserEntry);
    final parsed = InneraAiRecordDraft.fromMap({...patch, 'dateKey': dateKey});
    final emotionByName = <String, AiEmotionDraft>{
      for (final emotion in emotions) emotion.dedupeKey: emotion,
    };
    for (final emotion in parsed.emotions) {
      final existing = emotionByName[emotion.dedupeKey];
      emotionByName[emotion.dedupeKey] =
          emotion.score == null && existing?.score != null
              ? existing!
              : emotion;
    }
    final entries = <String>[...rawUserEntries];
    if (rawUserEntry != null && rawUserEntry.trim().isNotEmpty) {
      entries.add(rawUserEntry.trim());
    }
    return InneraAiRecordDraft(
      dateKey: dateKey,
      overallMood: parsed.overallMood ?? overallMood,
      emotions: emotionByName.values.toList(),
      symptoms: _sanitizeSymptoms({...symptoms, ...parsed.symptoms}.toList()),
      sleep: sleep.merge(parsed.sleep),
      events: {...events, ...parsed.events}.toList(),
      rawUserEntries: entries,
      diaryText: parsed.diaryText.isNotEmpty ? parsed.diaryText : diaryText,
      missingFields:
          parsed.missingFields.isEmpty ? missingFields : parsed.missingFields,
      updatedAt: DateTime.now(),
      confirmed: false,
      hasExistingRecord: hasExistingRecord,
    );
  }

  /// Deterministic compatibility fallback for explicit facts. The backend
  /// remains authoritative; these declarative rules prevent a partial/older
  /// AI response from dropping mentioned emotions or misclassifying sleep.
  InneraAiRecordDraft mergeExplicitRecordFacts(String rawUserEntry) {
    final text = rawUserEntry.trim();
    if (text.isEmpty) return this;

    final emotionByName = <String, AiEmotionDraft>{
      for (final emotion in emotions) emotion.dedupeKey: emotion,
    };
    final clauses = text.split(RegExp(r'[，。！？；\n]'));
    for (final clause in clauses) {
      for (final dimension in kEmotionDimensions) {
        final aliases = [...dimension.aliases]
          ..sort((left, right) => right.length.compareTo(left.length));
        final match =
            RegExp(RegExp.escape(dimension.displayName)).firstMatch(clause) ??
                (aliases.isEmpty
                    ? null
                    : RegExp(aliases.map(RegExp.escape).join('|'))
                        .firstMatch(clause));
        if (match == null) continue;
        final scoreMatch = RegExp(r'([1-5])\s*分').firstMatch(clause);
        final score =
            scoreMatch == null ? null : int.tryParse(scoreMatch.group(1)!);
        final existing = emotionByName[dimension.id];
        emotionByName[dimension.id] = AiEmotionDraft(
          rawText: match.group(0)!,
          normalizedDimensionId: dimension.id,
          normalizedDimensionName: dimension.displayName,
          score: score ?? existing?.score,
          source: AiDraftSource.explicitUserInput,
          mentioned: true,
          needsFollowUp: score == null && existing?.score == null,
          needsConfirmation: true,
          confidence: match.group(0) == dimension.displayName ? 1 : .9,
          timeContext: _timeContext(clause) ?? existing?.timeContext,
          evidence: clause.trim(),
        );
      }
    }

    final overallMatch = RegExp(
      r'(?:整體(?:情緒|心情)?|心情)(?:大概|約|是|有)?\s*([1-5])\s*分',
    ).firstMatch(text);
    final parsedOverall = overallMatch == null
        ? null
        : double.tryParse(overallMatch.group(1) ?? '');

    final sleepFlags = <String>{...sleep.flags};
    const sleepRules = <String, String>{
      'initInsomnia': r'睡不著|難入睡|很難入睡|躺很久才睡|闔眼.*又張開|翻來覆去|無法進入睡眠|入睡困難',
      'interrupted': r'半夜.*醒|夜裡.*醒|反覆醒|維持睡眠|睡眠中斷',
      'earlyWake': r'太早醒|提早醒|早醒',
      'lightSleep': r'淺眠|睡很淺',
      'dreams': r'多夢|惡夢|噩夢',
      'insufficient': r'睡眠不足|沒睡飽|睡不夠',
      'fragmented': r'斷斷續續|睡睡醒醒',
      'nocturia': r'夜尿|半夜.*上廁所',
    };
    for (final clause in clauses) {
      if (RegExp(r'昨天|前天|昨晚').hasMatch(clause)) continue;
      for (final rule in sleepRules.entries) {
        if (RegExp(rule.value).hasMatch(clause)) sleepFlags.add(rule.key);
      }
    }
    final explicitSleepTimes = _explicitSleepTimes(clauses);

    final symptomSet = <String>{..._sanitizeSymptoms(symptoms)};
    const symptomRules = <String, String>{
      '疲倦': r'疲倦|疲憊|很累|好累|很倦',
      '想吐': r'想吐|噁心',
      '頭痛': r'頭痛|頭疼',
      '心悸': r'心悸|心跳很快',
      '胃痛': r'胃痛|胃不舒服',
    };
    for (final rule in symptomRules.entries) {
      if (RegExp(rule.value).hasMatch(text)) symptomSet.add(rule.key);
    }

    return InneraAiRecordDraft(
      dateKey: dateKey,
      overallMood: parsedOverall ?? overallMood,
      emotions: emotionByName.values.toList(),
      symptoms: _sanitizeSymptoms(symptomSet.toList()),
      sleep: AiSleepDraft(
        sleepTime: sleep.sleepTime,
        wakeTime: explicitSleepTimes.wakeTime ?? sleep.wakeTime,
        finalWakeTime: explicitSleepTimes.finalWakeTime ?? sleep.finalWakeTime,
        quality: sleep.quality,
        midWakeList: sleep.midWakeList,
        flags: sleepFlags.toList(),
        naps: sleep.naps,
      ),
      events: events,
      rawUserEntries: rawUserEntries,
      diaryText: diaryText,
      missingFields: {
        ...missingFields.where((item) => !item.contains('情緒')),
        ...emotionByName.values
            .where((item) => item.score == null)
            .map((item) => '${item.name}強度'),
      }.toList(),
      updatedAt: DateTime.now(),
      confirmed: false,
      hasExistingRecord: hasExistingRecord,
    );
  }

  InneraAiRecordDraft withEmotionScore(String key, int score) {
    return InneraAiRecordDraft(
      dateKey: dateKey,
      overallMood: overallMood,
      emotions: emotions
          .map((item) => item.dedupeKey == key
              ? item.copyWith(score: score.clamp(1, 5))
              : item)
          .toList(),
      symptoms: symptoms,
      sleep: sleep,
      events: events,
      rawUserEntries: rawUserEntries,
      diaryText: diaryText,
      missingFields:
          missingFields.where((item) => !item.contains(key)).toList(),
      updatedAt: DateTime.now(),
      confirmed: false,
      hasExistingRecord: hasExistingRecord,
    );
  }

  InneraAiRecordDraft withEmotionDimension(
    String key,
    EmotionDimensionDefinition dimension,
  ) {
    final byDimension = <String, AiEmotionDraft>{};
    for (final item in emotions) {
      final updated =
          item.dedupeKey == key ? item.copyWith(dimension: dimension) : item;
      final existing = byDimension[updated.dedupeKey];
      byDimension[updated.dedupeKey] =
          updated.score == null && existing?.score != null
              ? existing!
              : updated;
    }
    return InneraAiRecordDraft(
      dateKey: dateKey,
      overallMood: overallMood,
      emotions: byDimension.values.toList(),
      symptoms: symptoms,
      sleep: sleep,
      events: events,
      rawUserEntries: rawUserEntries,
      diaryText: diaryText,
      missingFields: missingFields,
      updatedAt: DateTime.now(),
      confirmed: false,
      hasExistingRecord: hasExistingRecord,
    );
  }

  InneraAiRecordDraft withoutEmotion(String key) => InneraAiRecordDraft(
        dateKey: dateKey,
        overallMood: overallMood,
        emotions: emotions.where((item) => item.dedupeKey != key).toList(),
        symptoms: symptoms,
        sleep: sleep,
        events: events,
        rawUserEntries: rawUserEntries,
        diaryText: diaryText,
        missingFields:
            missingFields.where((item) => !item.contains(key)).toList(),
        updatedAt: DateTime.now(),
        confirmed: false,
        hasExistingRecord: hasExistingRecord,
      );

  InneraAiRecordDraft _withRawEntry(String? rawUserEntry) {
    final entry = rawUserEntry?.trim();
    if (entry == null || entry.isEmpty) return this;
    return InneraAiRecordDraft(
      dateKey: dateKey,
      overallMood: overallMood,
      emotions: emotions,
      symptoms: symptoms,
      sleep: sleep,
      events: events,
      rawUserEntries: [...rawUserEntries, entry],
      diaryText: diaryText,
      missingFields: missingFields,
      updatedAt: DateTime.now(),
      confirmed: false,
      hasExistingRecord: hasExistingRecord,
    );
  }

  InneraAiRecordDraft copyWith({bool? confirmed}) => InneraAiRecordDraft(
        dateKey: dateKey,
        overallMood: overallMood,
        emotions: emotions,
        symptoms: symptoms,
        sleep: sleep,
        events: events,
        rawUserEntries: rawUserEntries,
        diaryText: diaryText,
        missingFields: missingFields,
        updatedAt: DateTime.now(),
        confirmed: confirmed ?? this.confirmed,
        hasExistingRecord: hasExistingRecord,
      );

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static List<String> _strings(dynamic value) => value is List
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
      : const [];
  static List<String> _sanitizeSymptoms(List<String> values) {
    final sleepPattern = RegExp(
      r'睡不著|入睡困難|難入睡|半夜.*醒|反覆醒|早醒|淺眠|多夢|惡夢|噩夢|睡眠不足|睡不夠|睡睡醒醒|睡眠中斷|夜尿',
    );
    return values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && !sleepPattern.hasMatch(item))
        .toSet()
        .toList();
  }

  static String? _timeContext(String clause) {
    if (clause.contains('早上') || clause.contains('早晨')) return '早上';
    if (clause.contains('中午')) return '中午';
    if (clause.contains('下午')) return '下午';
    if (clause.contains('晚上') || clause.contains('今晚')) return '晚上';
    if (clause.contains('剛剛') || clause.contains('現在')) return '當下';
    return null;
  }

  static ({String? wakeTime, String? finalWakeTime}) _explicitSleepTimes(
    List<String> clauses,
  ) {
    String? wakeTime;
    String? finalWakeTime;
    for (final clause in clauses) {
      if (RegExp(r'昨天|前天|昨晚').hasMatch(clause)) continue;
      wakeTime ??= _clockBeforeAction(
        clause,
        r'起床|離床|下床|開始活動',
      );
      final awakening = _clockBeforeAction(
        clause,
        r'醒來|醒了|醒著|清醒|睜眼|睜開眼',
      );
      final returnedToSleep = RegExp(
        r'(?:醒來|醒了|醒著|清醒|睜眼|睜開眼)[^，。！？\n]{0,16}(?:又睡|再睡|睡回去|繼續睡)',
      ).hasMatch(clause);
      if (!returnedToSleep) finalWakeTime ??= awakening;
    }
    return (wakeTime: wakeTime, finalWakeTime: finalWakeTime);
  }

  static String? _clockBeforeAction(String clause, String actionPattern) {
    final match = RegExp(
      '(凌晨|清晨|早上|上午|下午|晚上)?\\s*'
      '(\\d{1,2})(?:[:：]([0-5]\\d)|點(?:(半)|([0-5]?\\d)\\s*分?)?)'
      '\\s*(?:多|左右)?'
      '[^0-9０-９，。！？\\n]{0,12}(?:$actionPattern)',
    ).firstMatch(clause);
    if (match == null) return null;
    var hour = int.tryParse(match.group(2) ?? '');
    if (hour == null || hour > 23) return null;
    final period = match.group(1);
    if ((period == '下午' || period == '晚上') && hour < 12) hour += 12;
    if (period == '凌晨' && hour == 12) hour = 0;
    final minute = match.group(4) != null
        ? 30
        : int.tryParse(match.group(3) ?? match.group(5) ?? '') ?? 0;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static Map<String, dynamic>? _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;
  static double? _doubleInRange(dynamic value) {
    final score = (value as num?)?.toDouble();
    return score != null && score >= 1 && score <= 5 ? score : null;
  }

  static DateTime? _date(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is String
          ? DateTime.tryParse(value)
          : null;
}
