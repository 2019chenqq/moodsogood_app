import 'package:cloud_firestore/cloud_firestore.dart';

enum AiDraftSource {
  explicitUserInput,
  aiExtracted,
  existingRecord,
  defaultPendingConfirmation,
}

class AiEmotionDraft {
  const AiEmotionDraft({
    required this.name,
    required this.score,
    this.source = AiDraftSource.aiExtracted,
  });

  final String name;
  final int score;
  final AiDraftSource source;

  Map<String, dynamic> toMap() => {
        'name': name,
        'score': score.clamp(1, 5),
        'source': source.name,
      };

  static AiEmotionDraft? tryFromMap(Map<String, dynamic> map) {
    final name = (map['name'] ?? '').toString().trim();
    final score = (map['score'] as num?)?.toInt();
    if (name.isEmpty || score == null || score < 1 || score > 5) return null;
    return AiEmotionDraft(
      name: name,
      score: score,
      source: AiDraftSource.values.firstWhere(
        (value) => value.name == map['source'],
        orElse: () => AiDraftSource.aiExtracted,
      ),
    );
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
    final emotions = (map['emotions'] as List?)
            ?.whereType<Map>()
            .map((item) =>
                AiEmotionDraft.tryFromMap(Map<String, dynamic>.from(item)))
            .whereType<AiEmotionDraft>()
            .toList() ??
        const <AiEmotionDraft>[];
    return InneraAiRecordDraft(
      dateKey: (map['dateKey'] ?? map['date'] ?? '').toString(),
      overallMood: _doubleInRange(map['overallMood']),
      emotions: emotions,
      symptoms: _strings(map['symptoms']),
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
        'emotions': emotions.map((item) => item.toMap()).toList(),
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
        'emotions': emotions.map((item) => item.toMap()).toList(),
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
      for (final emotion in emotions) emotion.name: emotion,
    };
    for (final emotion in parsed.emotions) {
      emotionByName[emotion.name] = emotion;
    }
    final entries = <String>[...rawUserEntries];
    if (rawUserEntry != null && rawUserEntry.trim().isNotEmpty) {
      entries.add(rawUserEntry.trim());
    }
    return InneraAiRecordDraft(
      dateKey: dateKey,
      overallMood: parsed.overallMood ?? overallMood,
      emotions: emotionByName.values.toList(),
      symptoms: {...symptoms, ...parsed.symptoms}.toList(),
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

  /// Preserves only emotion scores the user explicitly wrote in the chat.
  /// This is a local fallback when an AI response omits recordDraft.emotions.
  InneraAiRecordDraft mergeExplicitEmotionScores(String rawUserEntry) {
    final text = rawUserEntry.trim();
    if (text.isEmpty) return this;

    const emotionNames = <String>[
      '焦慮',
      '懊惱',
      '低落',
      '難過',
      '沮喪',
      '憂鬱',
      '憤怒',
      '生氣',
      '煩躁',
      '緊張',
      '害怕',
      '孤單',
      '內疚',
      '自責',
      '開心',
      '平靜',
    ];
    final emotionByName = <String, AiEmotionDraft>{
      for (final emotion in emotions) emotion.name: emotion,
    };
    var foundExplicitScore = false;

    for (final name in emotionNames) {
      final escapedName = RegExp.escape(name);
      final scoreAfterName = RegExp(
        '$escapedName[^，。！？\\n]{0,16}?([1-5])\\s*分',
      );
      final scoreBeforeName = RegExp(
        '([1-5])\\s*分[^，。！？\\n]{0,16}?$escapedName',
      );
      final match =
          scoreAfterName.firstMatch(text) ?? scoreBeforeName.firstMatch(text);
      final score = match == null ? null : int.tryParse(match.group(1) ?? '');
      if (score != null) {
        foundExplicitScore = true;
        emotionByName[name] = AiEmotionDraft(
          name: name,
          score: score,
          source: AiDraftSource.explicitUserInput,
        );
      }
    }

    if (!foundExplicitScore) return this;
    return InneraAiRecordDraft(
      dateKey: dateKey,
      overallMood: overallMood,
      emotions: emotionByName.values.toList(),
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
