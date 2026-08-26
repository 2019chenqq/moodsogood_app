import 'package:cloud_firestore/cloud_firestore.dart';

import '../daily/emotion_dimensions.dart';
import '../daily/daily_state_dimensions.dart';
import '../daily/symptom_definitions.dart';
import '../models/daily_record.dart';
import 'innera_ai_health_event_draft.dart';

enum AiDraftSource {
  explicitUserInput,
  aiExtracted,
  inferred,
  existingRecord,
  defaultPendingConfirmation,
}

enum AiEmotionSubjectType { user, other, shared, unknown }

final RegExp _otherEmotionSubjectPattern = RegExp(
  r'爸爸|爸媽|媽媽|母親|父親|弟弟|妹妹|哥哥|姊姊|姐姐|家人|朋友|同事|同學|老師|醫師|醫生|護理師|伴侶|男友|女友|先生|太太|孩子|兒子|女兒|對方|他們|她們|他|她',
);
final RegExp _explicitUserEmotionPattern = RegExp(
  r'我(?:自己|本人|也|還|真的|其實|現在|今天|當下|開始|感到|感覺|覺得|變得|很|好|超|有點|有些|有一點|心裡|心情)?|讓我|害我|使我|令我|我的',
);
final RegExp _sharedEmotionPattern = RegExp(r'我們(?:都|一起)?|我也(?:一樣|開始|覺得|感到)?');
final RegExp _speechOrMediaPattern = RegExp(
  r'說|表示|告訴|問|寫著|提到|看起來|覺得我|歌詞|歌曲|電影|影集|文章|貼文|新聞|小說',
);
final RegExp _quotedTextPattern = RegExp(r'[「『\"“].+[」』\"”]');

bool _emotionInsideQuote(String text, String emotion) {
  if (emotion.trim().isEmpty) return false;
  return RegExp(
          r'[「『\"“][^」』\"”]*' + RegExp.escape(emotion) + r'[^」』\"”]*[」』\"”]')
      .hasMatch(text);
}

({AiEmotionSubjectType type, String? text, bool quoted}) _emotionSubjectFromMap(
    Map<String, dynamic> map, String rawText) {
  final evidence = (map['evidence'] ?? '').toString().trim();
  final source = map['source']?.toString();
  final explicitUser = _explicitUserEmotionPattern.hasMatch(evidence);
  final shared = _sharedEmotionPattern.hasMatch(evidence);
  final otherMatch = _otherEmotionSubjectPattern.firstMatch(evidence);
  final emotionIndex = evidence.indexOf(rawText);
  final evidenceBeforeEmotion =
      emotionIndex >= 0 ? evidence.substring(0, emotionIndex) : evidence;
  final userBeforeEmotion = evidenceBeforeEmotion.lastIndexOf('我');
  final otherMatches = _otherEmotionSubjectPattern.allMatches(
    evidenceBeforeEmotion,
  );
  final otherBeforeEmotion = otherMatches.isEmpty
      ? -1
      : otherMatches.map((match) => match.start).reduce(
            (left, right) => left > right ? left : right,
          );
  final otherOwnsEmotion =
      otherBeforeEmotion >= 0 && otherBeforeEmotion > userBeforeEmotion;
  final quoted = map['isQuotedSpeech'] == true ||
      _emotionInsideQuote(evidence, rawText) ||
      (otherMatch != null && _speechOrMediaPattern.hasMatch(evidence));
  final requested = AiEmotionSubjectType.values.where(
    (value) => value.name == map['subjectType']?.toString(),
  );
  var type = requested.isEmpty ? null : requested.first;
  if (source == AiDraftSource.existingRecord.name) {
    type = AiEmotionSubjectType.user;
  } else if (quoted && !shared) {
    type = AiEmotionSubjectType.other;
  } else if ((otherOwnsEmotion || (otherMatch != null && !explicitUser)) &&
      !shared) {
    type = AiEmotionSubjectType.other;
  } else if (shared) {
    type = AiEmotionSubjectType.shared;
  } else {
    // Conservative migration for old drafts: an absent subject is never
    // silently treated as the user unless first-person evidence exists.
    type ??=
        explicitUser ? AiEmotionSubjectType.user : AiEmotionSubjectType.unknown;
  }
  final requestedText = map['subjectText']?.toString().trim();
  return (
    type: type,
    text: requestedText?.isNotEmpty == true
        ? requestedText
        : type == AiEmotionSubjectType.other
            ? otherMatch?.group(0)
            : explicitUser
                ? '我'
                : null,
    quoted: quoted,
  );
}

const _symptomPatterns = <String, String>{
  '疲倦': r'疲倦|疲憊|很累|好累|很倦|倦怠',
  '動力不足': r'動力不足|沒有動力|沒動力|缺乏動力|提不起勁',
  '一直想吃東西': r'食慾增加|食慾變大|食量增加|吃得比平常多|一直想吃東西|看到什麼都想吃',
  '容易飢餓': r'容易飢餓|很快又餓',
  '吃完仍不滿足': r'吃完仍不滿足|吃完還想吃',
  '食慾降低': r'食慾下降|食慾降低|食慾不振|沒有食慾|沒胃口|吃不下',
  '噁心反胃': r'想吐|噁心|反胃',
  '白天嗜睡': r'白天嗜睡|睏倦|嗜睡',
  '頭痛': r'頭痛|頭疼',
  '心悸': r'心悸|心跳很快',
  '胃痛': r'胃痛|胃不舒服',
};

Set<String> _symptomNamesFromText(String text) => {
      for (final rule in _symptomPatterns.entries)
        if (RegExp(rule.value).hasMatch(text)) rule.key,
    };

bool mentionsPreviousDaySleep(String text) {
  const sleepTerms = r'睡眠|入睡|起床|睡覺|難睡|難入睡|睡不著|睡不好|沒睡好|早醒|半夜.*醒|睡睡醒醒';
  return RegExp('昨天[^，。！？\\n]{0,20}($sleepTerms)').hasMatch(text) ||
      RegExp('($sleepTerms)[^，。！？\\n]{0,20}昨天').hasMatch(text) ||
      RegExp('昨晚[^，。！？\\n]{0,20}($sleepTerms)').hasMatch(text) ||
      RegExp('($sleepTerms)[^，。！？\\n]{0,20}昨晚').hasMatch(text);
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
    this.subjectType = AiEmotionSubjectType.unknown,
    this.subjectText,
    this.isQuotedSpeech = false,
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
  final AiEmotionSubjectType subjectType;
  final String? subjectText;
  final bool isQuotedSpeech;

  String get name => normalizedDimensionName ?? rawText;
  String get dedupeKey => normalizedDimensionId ?? 'raw:${rawText.trim()}';
  bool get hasValidDimension =>
      normalizedDimensionId != null &&
      kEmotionDimensionsById[normalizedDimensionId]?.displayName ==
          normalizedDimensionName;
  bool get isEligibleUserEmotion =>
      subjectType == AiEmotionSubjectType.user ||
      (subjectType == AiEmotionSubjectType.shared &&
          !isQuotedSpeech &&
          _explicitUserEmotionPattern.hasMatch(evidence ?? ''));

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
        'subjectType': subjectType.name,
        'subjectText': subjectText,
        'isQuotedSpeech': isQuotedSpeech,
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
    final subject = _emotionSubjectFromMap(map, rawText);
    final isInferred = sourceName == 'inferred';
    return AiEmotionDraft(
      rawText: rawText.isEmpty ? dimension!.displayName : rawText,
      normalizedDimensionId: dimension?.id,
      normalizedDimensionName: dimension?.displayName,
      score: score,
      source: AiDraftSource.values.firstWhere(
        (value) => value.name == sourceName,
        orElse: () => sourceName == 'explicit'
            ? AiDraftSource.explicitUserInput
            : isInferred
                ? AiDraftSource.inferred
                : AiDraftSource.aiExtracted,
      ),
      mentioned: map['mentioned'] != false,
      needsFollowUp: map['needsFollowUp'] == true || score == null,
      needsConfirmation:
          isInferred || map['needsConfirmation'] == true || dimension == null,
      confidence: (isInferred
              ? (rawConfidence ?? 0).clamp(0, .75)
              : rawConfidence?.clamp(0, 1)) ??
          (dimension?.displayName == rawText
              ? 1
              : (dimension == null ? 0 : .9)),
      timeContext: _text(map['timeContext']),
      evidence: _text(map['evidence']),
      subjectType: subject.type,
      subjectText: subject.text,
      isQuotedSpeech: subject.quoted,
    );
  }

  AiEmotionDraft copyWith({
    int? score,
    bool clearScore = false,
    EmotionDimensionDefinition? dimension,
    AiEmotionSubjectType? subjectType,
    String? subjectText,
    bool? isQuotedSpeech,
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
        subjectType: subjectType ?? this.subjectType,
        subjectText: subjectText ?? this.subjectText,
        isQuotedSpeech: isQuotedSpeech ?? this.isQuotedSpeech,
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
    this.stateChanges = const {},
    this.bodyMeasurement,
    this.sleep = const AiSleepDraft(),
    this.events = const [],
    this.eventDrafts = const [],
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
  final Map<String, int> stateChanges;
  final BodyMeasurement? bodyMeasurement;
  final AiSleepDraft sleep;
  final List<String> events;
  final List<InneraAiHealthEventDraft> eventDrafts;
  final List<String> rawUserEntries;
  final String diaryText;
  String get diaryTextDraft => diaryText;
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
    final eventSet = <String>{..._strings(map['events'])};
    final excludedEmotionTerms = <String>{};
    final symptomSet = <String>{
      ..._sanitizeSymptoms(_strings(map['symptoms'])),
    };
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
      if (parsed == null) continue;
      final migratedSymptoms = _symptomNamesFromText(
        '${parsed.rawText} ${parsed.evidence ?? ''}',
      );
      if (migratedSymptoms.isNotEmpty) {
        symptomSet.addAll(migratedSymptoms);
        continue;
      }
      if (!parsed.isEligibleUserEmotion) {
        excludedEmotionTerms.add(parsed.rawText);
        if (parsed.normalizedDimensionName != null) {
          excludedEmotionTerms.add(parsed.normalizedDimensionName!);
        }
        if (parsed.subjectType == AiEmotionSubjectType.other) {
          final event = parsed.evidence?.trim() ?? '';
          if (event.isNotEmpty) eventSet.add(event);
        }
        continue;
      }
      emotionByName[parsed.dedupeKey] = parsed;
    }
    return InneraAiRecordDraft(
      dateKey: (map['dateKey'] ?? map['date'] ?? '').toString(),
      overallMood: _doubleInRange(map['overallMood']),
      emotions: emotionByName.values.toList(),
      symptoms: symptomSet.toList(),
      stateChanges: _stateChanges(map['stateChanges']),
      bodyMeasurement: _bodyMeasurement(map['bodyMeasurement']),
      sleep: AiSleepDraft.fromMap(_map(map['sleep'])),
      events: eventSet.toList(),
      eventDrafts: mergeEquivalentHealthEventDrafts(
        (map['eventDrafts'] as List?)
                ?.whereType<Map>()
                .map((item) => InneraAiHealthEventDraft.fromMap(
                      Map<String, dynamic>.from(item),
                    ))
                .where((item) => item.id.isNotEmpty && item.hasContent) ??
            const <InneraAiHealthEventDraft>[],
      ),
      rawUserEntries: _strings(map['rawUserEntries']),
      diaryText:
          (map['diaryText'] ?? map['diaryTextDraft'] ?? '').toString().trim(),
      missingFields: _strings(map['missingFields'])
          .where(
            (field) => !excludedEmotionTerms.any(field.contains),
          )
          .toList(),
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
        'stateChanges': stateChanges,
        'bodyMeasurement': bodyMeasurement?.toJson(),
        'sleep': sleep.toMap(),
        'events': events,
        'eventDrafts': eventDrafts.map((item) => item.toMap()).toList(),
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
        'stateChanges': stateChanges,
        'bodyMeasurement': bodyMeasurement?.toJson(),
        'sleep': sleep.toMap(),
        'events': events,
        'eventDrafts': eventDrafts.map((item) => item.toMap()).toList(),
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
    final symptomSet = <String>{...symptoms, ...parsed.symptoms};
    final emotionByName = <String, AiEmotionDraft>{};
    for (final emotion in emotions) {
      final migratedSymptoms = _symptomNamesFromText(
        '${emotion.rawText} ${emotion.evidence ?? ''}',
      );
      if (migratedSymptoms.isNotEmpty) {
        symptomSet.addAll(migratedSymptoms);
      } else {
        emotionByName[emotion.dedupeKey] = emotion;
      }
    }
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
    final eventDraftMap = <String, InneraAiHealthEventDraft>{
      for (final item in eventDrafts) item.id: item,
    };
    final allowsEventTimeCorrection = rawUserEntry != null &&
        RegExp(
          r'(?:剛剛那筆|剛才那筆|前面那筆|上一筆|前一筆|那筆)[^，。！？]{0,24}(?:其實|不是|改成|應該是)|(?:時間|時段)[^，。！？]{0,12}(?:說錯|修正|改成)',
        ).hasMatch(rawUserEntry);
    for (final item in parsed.eventDrafts) {
      eventDraftMap[item.id] = eventDraftMap[item.id]?.merge(
            item,
            allowEventTimeUpdate: allowsEventTimeCorrection,
          ) ??
          item;
    }
    return InneraAiRecordDraft(
      dateKey: dateKey,
      overallMood: parsed.overallMood ?? overallMood,
      emotions: emotionByName.values.toList(),
      symptoms: _sanitizeSymptoms(symptomSet.toList()),
      stateChanges: {...stateChanges, ...parsed.stateChanges},
      bodyMeasurement: _mergeBodyMeasurements(
        bodyMeasurement,
        parsed.bodyMeasurement,
      ),
      sleep: sleep.merge(parsed.sleep),
      events: {...events, ...parsed.events}.toList(),
      eventDrafts: mergeEquivalentHealthEventDrafts(eventDraftMap.values),
      rawUserEntries: entries,
      diaryText: parsed.diaryText.isNotEmpty ? parsed.diaryText : diaryText,
      missingFields:
          parsed.missingFields.isEmpty ? missingFields : parsed.missingFields,
      updatedAt: DateTime.now(),
      confirmed: false,
      hasExistingRecord: hasExistingRecord,
    );
  }

  InneraAiRecordDraft mergeExplicitHealthEventFacts(
    String rawUserEntry,
    DateTime messageTime,
  ) =>
      InneraAiRecordDraft(
        dateKey: dateKey,
        overallMood: overallMood,
        emotions: emotions,
        symptoms: symptoms,
        stateChanges: stateChanges,
        bodyMeasurement: bodyMeasurement,
        sleep: sleep,
        events: events,
        eventDrafts: mergeExplicitHealthEventDrafts(
          existing: eventDrafts,
          text: rawUserEntry,
          messageTime: messageTime,
        ),
        rawUserEntries: rawUserEntries,
        diaryText: diaryText,
        missingFields: missingFields,
        updatedAt: DateTime.now(),
        confirmed: false,
        hasExistingRecord: hasExistingRecord,
      );

  /// Deterministic compatibility fallback for explicit facts. The backend
  /// remains authoritative; these declarative rules prevent a partial/older
  /// AI response from dropping mentioned emotions or misclassifying sleep.
  InneraAiRecordDraft mergeExplicitRecordFacts(String rawUserEntry) {
    final text = rawUserEntry.trim();
    if (text.isEmpty) return this;

    final symptomSet = <String>{..._sanitizeSymptoms(symptoms)};
    final clauses = _splitEmotionClauses(text);
    final eventSet = <String>{...events};
    final emotionByName = <String, AiEmotionDraft>{};
    for (final emotion in emotions) {
      final migratedSymptoms = _symptomNamesFromText(
        '${emotion.rawText} ${emotion.evidence ?? ''}',
      );
      if (migratedSymptoms.isNotEmpty) {
        symptomSet.addAll(migratedSymptoms);
      } else if (emotion.isEligibleUserEmotion) {
        final temporalScope = _temporalScopeForEmotion(emotion, clauses);
        emotionByName[emotion.dedupeKey] = temporalScope.matched
            ? _emotionWithTimeContext(emotion, temporalScope.timeContext)
            : emotion;
      } else if (emotion.subjectType == AiEmotionSubjectType.other &&
          emotion.evidence?.trim().isNotEmpty == true) {
        eventSet.add(emotion.evidence!.trim());
      }
    }
    EmotionDimensionDefinition? observedUserEmotion;
    for (final clause in clauses) {
      final clauseSubject = _subjectForExplicitClause(clause);
      if (clauseSubject == AiEmotionSubjectType.other) {
        eventSet.add(clause.trim());
      }
      var foundEmotion = false;
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
        foundEmotion = true;
        if (clauseSubject != AiEmotionSubjectType.user &&
            clauseSubject != AiEmotionSubjectType.shared) {
          eventSet.add(clause.trim());
          observedUserEmotion = _speechOrMediaPattern.hasMatch(clause) &&
                  _explicitUserEmotionPattern.hasMatch(clause)
              ? dimension
              : observedUserEmotion;
          continue;
        }
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
          timeContext: _timeContext(clause),
          evidence: clause.trim(),
          subjectType: clauseSubject,
          subjectText: '我',
          isQuotedSpeech: false,
        );
      }
      if (!foundEmotion &&
          observedUserEmotion != null &&
          RegExp(r'我(?:自己)?也?(?:覺得|感覺)(?:是|有|一樣)?|我也這麼覺得').hasMatch(clause)) {
        final dimension = observedUserEmotion;
        final existing = emotionByName[dimension.id];
        emotionByName[dimension.id] = AiEmotionDraft(
          rawText: dimension.displayName,
          normalizedDimensionId: dimension.id,
          normalizedDimensionName: dimension.displayName,
          score: existing?.score,
          source: AiDraftSource.explicitUserInput,
          mentioned: true,
          needsFollowUp: existing?.score == null,
          needsConfirmation: false,
          confidence: .9,
          timeContext: _timeContext(clause),
          evidence: clause.trim(),
          subjectType: AiEmotionSubjectType.user,
          subjectText: '我',
          isQuotedSpeech: false,
        );
        observedUserEmotion = null;
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

    symptomSet.addAll(_symptomNamesFromText(text));
    final explicitStateChanges = _explicitStateChanges(text);
    final explicitBodyMeasurement = _explicitBodyMeasurement(text);

    return InneraAiRecordDraft(
      dateKey: dateKey,
      overallMood: parsedOverall ?? overallMood,
      emotions: emotionByName.values.toList(),
      symptoms: _sanitizeSymptoms(symptomSet.toList()),
      stateChanges: {...stateChanges, ...explicitStateChanges},
      bodyMeasurement: _mergeBodyMeasurements(
        bodyMeasurement,
        explicitBodyMeasurement,
      ),
      sleep: AiSleepDraft(
        sleepTime: sleep.sleepTime,
        wakeTime: explicitSleepTimes.wakeTime ?? sleep.wakeTime,
        finalWakeTime: explicitSleepTimes.finalWakeTime ?? sleep.finalWakeTime,
        quality: sleep.quality,
        midWakeList: sleep.midWakeList,
        flags: sleepFlags.toList(),
        naps: sleep.naps,
      ),
      events: eventSet.toList(),
      eventDrafts: eventDrafts,
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

  /// Re-applies deterministic extraction to persisted raw entries after rule
  /// updates, so users do not need to type the same content again.
  InneraAiRecordDraft reconcileExplicitRecordFacts() {
    var reconciled = this;
    for (final entry in rawUserEntries) {
      reconciled = reconciled.mergeExplicitRecordFacts(entry);
    }
    return reconciled;
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
      stateChanges: stateChanges,
      bodyMeasurement: bodyMeasurement,
      sleep: sleep,
      events: events,
      eventDrafts: eventDrafts,
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
      stateChanges: stateChanges,
      bodyMeasurement: bodyMeasurement,
      sleep: sleep,
      events: events,
      eventDrafts: eventDrafts,
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
        stateChanges: stateChanges,
        bodyMeasurement: bodyMeasurement,
        sleep: sleep,
        events: events,
        eventDrafts: eventDrafts,
        rawUserEntries: rawUserEntries,
        diaryText: diaryText,
        missingFields:
            missingFields.where((item) => !item.contains(key)).toList(),
        updatedAt: DateTime.now(),
        confirmed: false,
        hasExistingRecord: hasExistingRecord,
      );

  InneraAiRecordDraft withStateChange(String id, int? value) {
    if (!kDailyStateDimensionsById.containsKey(id)) return this;
    final updated = <String, int>{...stateChanges};
    if (value == null) {
      updated.remove(id);
    } else {
      updated[id] = value.clamp(1, 5);
    }
    return _copyWithRecordFields(stateChanges: updated);
  }

  InneraAiRecordDraft withBodyMeasurement(BodyMeasurement? value) =>
      _copyWithRecordFields(
        bodyMeasurement: value?.hasData == true ? value : null,
        replaceBodyMeasurement: true,
      );

  InneraAiRecordDraft withEventSummary(String eventId, String summary) =>
      InneraAiRecordDraft(
        dateKey: dateKey,
        overallMood: overallMood,
        emotions: emotions,
        symptoms: symptoms,
        stateChanges: stateChanges,
        bodyMeasurement: bodyMeasurement,
        sleep: sleep,
        events: events,
        eventDrafts: eventDrafts
            .map((item) =>
                item.id == eventId ? item.copyWith(note: summary.trim()) : item)
            .toList(),
        rawUserEntries: rawUserEntries,
        diaryText: diaryText,
        missingFields: missingFields,
        updatedAt: DateTime.now(),
        confirmed: false,
        hasExistingRecord: hasExistingRecord,
      );

  InneraAiRecordDraft withEventSymptomSeverity(
    String eventId,
    String symptom,
    int? severity,
  ) =>
      InneraAiRecordDraft(
        dateKey: dateKey,
        overallMood: overallMood,
        emotions: emotions,
        symptoms: symptoms,
        stateChanges: stateChanges,
        bodyMeasurement: bodyMeasurement,
        sleep: sleep,
        events: events,
        eventDrafts: eventDrafts
            .map(
              (item) => item.id == eventId
                  ? item.withSymptomSeverity(symptom, severity)
                  : item,
            )
            .toList(),
        rawUserEntries: rawUserEntries,
        diaryText: diaryText,
        missingFields: missingFields,
        updatedAt: DateTime.now(),
        confirmed: false,
        hasExistingRecord: hasExistingRecord,
      );

  InneraAiRecordDraft withEventEmotionScore(
    String eventId,
    String emotionKey,
    int score,
  ) =>
      _withUpdatedEvent(
        eventId,
        (event) => event.withEmotionScore(emotionKey, score),
      );

  InneraAiRecordDraft withEventEmotionDimension(
    String eventId,
    String emotionKey,
    EmotionDimensionDefinition dimension,
  ) =>
      _withUpdatedEvent(
        eventId,
        (event) => event.withEmotionDimension(emotionKey, dimension),
      );

  InneraAiRecordDraft withoutEventEmotion(
    String eventId,
    String emotionKey,
  ) =>
      _withUpdatedEvent(
        eventId,
        (event) => event.withoutEmotion(emotionKey),
      );

  InneraAiRecordDraft withEventStateChange(
    String eventId,
    String stateId,
    int? value,
  ) =>
      _withUpdatedEvent(
        eventId,
        (event) => event.withStateChange(stateId, value),
      );

  InneraAiRecordDraft _withUpdatedEvent(
    String eventId,
    InneraAiHealthEventDraft Function(InneraAiHealthEventDraft) update,
  ) =>
      InneraAiRecordDraft(
        dateKey: dateKey,
        overallMood: overallMood,
        emotions: emotions,
        symptoms: symptoms,
        stateChanges: stateChanges,
        bodyMeasurement: bodyMeasurement,
        sleep: sleep,
        events: events,
        eventDrafts: eventDrafts
            .map((item) => item.id == eventId ? update(item) : item)
            .toList(),
        rawUserEntries: rawUserEntries,
        diaryText: diaryText,
        missingFields: missingFields,
        updatedAt: DateTime.now(),
        confirmed: false,
        hasExistingRecord: hasExistingRecord,
      );

  InneraAiRecordDraft _copyWithRecordFields({
    Map<String, int>? stateChanges,
    BodyMeasurement? bodyMeasurement,
    bool replaceBodyMeasurement = false,
  }) =>
      InneraAiRecordDraft(
        dateKey: dateKey,
        overallMood: overallMood,
        emotions: emotions,
        symptoms: symptoms,
        stateChanges: stateChanges ?? this.stateChanges,
        bodyMeasurement:
            replaceBodyMeasurement ? bodyMeasurement : this.bodyMeasurement,
        sleep: sleep,
        events: events,
        eventDrafts: eventDrafts,
        rawUserEntries: rawUserEntries,
        diaryText: diaryText,
        missingFields: missingFields,
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
      stateChanges: stateChanges,
      bodyMeasurement: bodyMeasurement,
      sleep: sleep,
      events: events,
      eventDrafts: eventDrafts,
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
        stateChanges: stateChanges,
        bodyMeasurement: bodyMeasurement,
        sleep: sleep,
        events: events,
        eventDrafts: eventDrafts,
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
        .map(normalizeSymptomName)
        .where((item) => item.isNotEmpty && !sleepPattern.hasMatch(item))
        .toSet()
        .toList();
  }

  static Map<String, int> _stateChanges(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, int>{};
    for (final entry in value.entries) {
      if (!kDailyStateDimensionsById.containsKey(entry.key.toString())) {
        continue;
      }
      final score = (entry.value as num?)?.toInt();
      if (score != null && score >= 1 && score <= 5) {
        result[entry.key.toString()] = score;
      }
    }
    return result;
  }

  static BodyMeasurement? _bodyMeasurement(dynamic value) {
    if (value is! Map) return null;
    final parsed = BodyMeasurement.fromJson(value.cast<String, dynamic>());
    return parsed.hasData && parsed.isValid ? parsed : null;
  }

  static BodyMeasurement? _mergeBodyMeasurements(
    BodyMeasurement? existing,
    BodyMeasurement? patch,
  ) {
    if (patch == null) return existing;
    final measurementTiming =
        patch.measurementTiming ?? existing?.measurementTiming;
    final customMeasurementTime = measurementTiming == MeasurementTiming.other
        ? patch.effectiveCustomMeasurementTime ??
            (existing?.measurementTiming == MeasurementTiming.other
                ? existing?.effectiveCustomMeasurementTime
                : null)
        : null;
    final merged = BodyMeasurement(
      weightKg: patch.weightKg ?? existing?.weightKg,
      bodyFatPercent: patch.bodyFatPercent ?? existing?.bodyFatPercent,
      waistCm: patch.waistCm ?? existing?.waistCm,
      measuredAt: patch.measuredAt ?? existing?.measuredAt,
      measurementTiming: measurementTiming == MeasurementTiming.other &&
              customMeasurementTime == null
          ? null
          : measurementTiming,
      customMeasurementTime: customMeasurementTime,
    );
    return merged.hasData && merged.isValid ? merged : existing;
  }

  static Map<String, int> _explicitStateChanges(String text) {
    final result = <String, int>{};
    const terms = <String, String>{
      'energy_change': r'能量|精神|精力',
      'appetite_change': r'食慾|胃口',
      'activity_change': r'活動量|活動程度',
    };
    for (final entry in terms.entries) {
      final match = RegExp('(?:${entry.value})[^，、。！？\\n]{0,12}([1-5１-５])\\s*分')
          .firstMatch(text);
      final raw = match?.group(1);
      if (raw == null) continue;
      const fullWidth = '１２３４５';
      final score = int.tryParse(raw) ?? fullWidth.indexOf(raw) + 1;
      if (score >= 1 && score <= 5) result[entry.key] = score;
    }
    return result;
  }

  static BodyMeasurement? _explicitBodyMeasurement(String text) {
    const number = r'(?<![\d.])(\d{1,3}(?:\.\d)?)(?![\d.])';
    final weight =
        RegExp('$number\\s*(?:公斤|kg)', caseSensitive: false).firstMatch(text);
    final bodyFat =
        RegExp('(?:體脂(?:率)?)[^\\d]{0,4}$number\\s*%').firstMatch(text);
    final waist =
        RegExp('(?:腰圍)[^\\d]{0,4}$number\\s*(?:公分|cm)', caseSensitive: false)
            .firstMatch(text);
    final weightKg = _measurementInRange(weight?.group(1), 20, 300);
    final bodyFatPercent = _measurementInRange(bodyFat?.group(1), 1, 70);
    final waistCm = _measurementInRange(waist?.group(1), 30, 250);

    MeasurementTiming? timing;
    if (text.contains('晚餐後')) {
      timing = MeasurementTiming.afterDinner;
    } else if (text.contains('午餐後')) {
      timing = MeasurementTiming.afterLunch;
    } else if (text.contains('早餐後')) {
      timing = MeasurementTiming.afterBreakfast;
    } else if (RegExp(r'起床(?:後)?(?:量|測)?').hasMatch(text)) {
      timing = MeasurementTiming.afterWaking;
    } else if (text.contains('睡前')) {
      timing = MeasurementTiming.beforeSleep;
    }

    String? customMeasurementTime;
    if (timing == null) {
      final customTiming = RegExp(
        r'(?:運動|洗澡|回家|下班|服藥|吃藥)後|(?:早上|上午|中午|下午|傍晚|晚上|凌晨)\s*\d{1,2}(?::\d{2}|點(?:半)?)?(?:左右)?',
      ).firstMatch(text);
      if (customTiming != null) {
        timing = MeasurementTiming.other;
        customMeasurementTime = customTiming.group(0)?.trim();
      }
    }
    final measurement = BodyMeasurement(
      weightKg: weightKg,
      bodyFatPercent: bodyFatPercent,
      waistCm: waistCm,
      measurementTiming: timing,
      customMeasurementTime: customMeasurementTime,
    );
    return measurement.hasData && measurement.isValid ? measurement : null;
  }

  static double? _measurementInRange(String? raw, double min, double max) {
    if (raw == null) return null;
    final value = double.tryParse(raw);
    if (value == null || value < min || value > max) return null;
    return (value * 10).roundToDouble() / 10;
  }

  static String? _timeContext(String clause) {
    if (RegExp(r'昨天|昨晚').hasMatch(clause)) return '昨天';
    if (clause.contains('前天')) return '前天';
    if (RegExp(r'今天|今日').hasMatch(clause)) return null;
    if (clause.contains('早上') || clause.contains('早晨')) return '早上';
    if (clause.contains('中午')) return '中午';
    if (clause.contains('下午')) return '下午';
    if (clause.contains('晚上') || clause.contains('今晚')) return '晚上';
    if (clause.contains('剛剛') || clause.contains('現在')) return '當下';
    return null;
  }

  static ({bool matched, String? timeContext}) _temporalScopeForEmotion(
    AiEmotionDraft emotion,
    List<String> clauses,
  ) {
    final dimension = emotion.normalizedDimensionId == null
        ? null
        : kEmotionDimensionsById[emotion.normalizedDimensionId];
    final terms = <String>{
      emotion.rawText.trim(),
      if (emotion.normalizedDimensionName != null)
        emotion.normalizedDimensionName!.trim(),
      ...?dimension?.aliases,
    }.where((term) => term.isNotEmpty).toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final clause in clauses.reversed) {
      final comparableClause = _temporalComparable(clause);
      final matches = terms.any((term) {
        final comparableTerm = _temporalComparable(term);
        return comparableTerm.isNotEmpty &&
            comparableClause.contains(comparableTerm);
      });
      if (!matches) continue;
      return (matched: true, timeContext: _timeContext(clause));
    }
    return (matched: false, timeContext: null);
  }

  static String _temporalComparable(String value) => value.replaceAll(
        RegExp(r'\s+|也|有點|還是|仍然|還|很|真的'),
        '',
      );

  static AiEmotionDraft _emotionWithTimeContext(
    AiEmotionDraft emotion,
    String? timeContext,
  ) =>
      AiEmotionDraft(
        rawText: emotion.rawText,
        normalizedDimensionId: emotion.normalizedDimensionId,
        normalizedDimensionName: emotion.normalizedDimensionName,
        score: emotion.score,
        source: emotion.source,
        mentioned: emotion.mentioned,
        needsFollowUp: emotion.needsFollowUp,
        needsConfirmation: emotion.needsConfirmation,
        confidence: emotion.confidence,
        timeContext: timeContext,
        evidence: emotion.evidence,
        subjectType: emotion.subjectType,
        subjectText: emotion.subjectText,
        isQuotedSpeech: emotion.isQuotedSpeech,
      );

  static List<String> _splitEmotionClauses(String text) => text
      .replaceAll(RegExp(r'但|可是|不過|然而'), '，')
      .split(RegExp(r'[，。！？；\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  static AiEmotionSubjectType _subjectForExplicitClause(String clause) {
    final hasUser = _explicitUserEmotionPattern.hasMatch(clause);
    final hasShared = _sharedEmotionPattern.hasMatch(clause);
    final hasOther = _otherEmotionSubjectPattern.hasMatch(clause);
    final quotedOrMedia = _quotedTextPattern.hasMatch(clause) ||
        (hasOther && _speechOrMediaPattern.hasMatch(clause));
    if (quotedOrMedia && !hasShared) return AiEmotionSubjectType.other;
    if (hasShared) return AiEmotionSubjectType.shared;
    final explicitUserFeeling = RegExp(
      r'害我|讓我|使我|令我|我(?:自己|也|開始|覺得|感到|感覺|很|好|超|有點|有些|心裡|心情)',
    ).hasMatch(clause);
    if (hasOther && !explicitUserFeeling) return AiEmotionSubjectType.other;
    if (hasUser) return AiEmotionSubjectType.user;
    // A direct, unquoted emotion in today's first-person diary conversation
    // commonly omits 「我」; this is current input, not old-draft migration.
    return AiEmotionSubjectType.user;
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
