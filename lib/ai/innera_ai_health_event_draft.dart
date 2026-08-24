import '../daily/emotion_dimensions.dart';
import 'innera_ai_record_draft.dart';

enum AiEventTimePrecision { exact, approximate, unspecified }

class InneraAiHealthEventDraft {
  const InneraAiHealthEventDraft({
    required this.id,
    this.eventTime,
    this.timeContext,
    this.timePrecision = AiEventTimePrecision.unspecified,
    this.emotions = const [],
    this.symptoms = const [],
    this.symptomSeverities = const {},
    this.stateChanges = const {},
    this.rawUserEntries = const [],
    this.note = '',
  });

  final String id;
  final DateTime? eventTime;
  final String? timeContext;
  final AiEventTimePrecision timePrecision;
  final List<AiEmotionDraft> emotions;
  final List<String> symptoms;
  final Map<String, int> symptomSeverities;
  final Map<String, int> stateChanges;
  final List<String> rawUserEntries;
  final String note;

  bool get hasContent =>
      emotions.isNotEmpty ||
      symptoms.isNotEmpty ||
      stateChanges.isNotEmpty ||
      note.trim().isNotEmpty;

  String get timeLabel {
    final time = eventTime;
    if (time != null) {
      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    }
    final context = timeContext?.trim();
    if (context?.isNotEmpty == true) return context!;
    return '時間待確認';
  }

  factory InneraAiHealthEventDraft.fromMap(Map<String, dynamic> map) {
    final rawTime = map['eventTime']?.toString();
    final precisionName = map['timePrecision']?.toString();
    return InneraAiHealthEventDraft(
      id: (map['id'] ?? '').toString().trim(),
      eventTime: rawTime == null ? null : DateTime.tryParse(rawTime),
      timeContext: _text(map['timeContext']),
      timePrecision: AiEventTimePrecision.values.firstWhere(
        (value) => value.name == precisionName,
        orElse: () => AiEventTimePrecision.unspecified,
      ),
      emotions: (map['emotionMentions'] as List?)
              ?.whereType<Map>()
              .map((item) => AiEmotionDraft.tryFromMap(
                    Map<String, dynamic>.from(item),
                  ))
              .whereType<AiEmotionDraft>()
              .toList() ??
          const [],
      symptoms: _strings(map['symptoms']),
      symptomSeverities: _symptomSeverities(map['symptoms']),
      stateChanges: _stateChanges(map['stateChanges']),
      rawUserEntries: _strings(map['rawUserEntries']),
      note: (map['note'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'eventTime': eventTime?.toIso8601String(),
        'timeContext': timeContext,
        'timePrecision': timePrecision.name,
        'emotionMentions': emotions.map((item) => item.toMap()).toList(),
        'symptoms': symptoms
            .map((name) => {
                  'name': name,
                  'severity': symptomSeverities[name],
                })
            .toList(),
        'stateChanges': stateChanges,
        'rawUserEntries': rawUserEntries,
        'note': note,
      };

  InneraAiHealthEventDraft merge(InneraAiHealthEventDraft patch) {
    final emotionMap = <String, AiEmotionDraft>{
      for (final item in emotions) item.dedupeKey: item,
    };
    for (final item in patch.emotions) {
      final existing = emotionMap[item.dedupeKey];
      emotionMap[item.dedupeKey] =
          item.score == null && existing?.score != null ? existing! : item;
    }
    return InneraAiHealthEventDraft(
      id: id,
      eventTime: patch.eventTime ?? eventTime,
      timeContext: patch.eventTime != null
          ? patch.timeContext
          : patch.timeContext ?? timeContext,
      timePrecision: patch.timePrecision == AiEventTimePrecision.unspecified
          ? timePrecision
          : patch.timePrecision,
      emotions: emotionMap.values.toList(),
      symptoms: {...symptoms, ...patch.symptoms}.toList(),
      symptomSeverities: {
        ...symptomSeverities,
        ...patch.symptomSeverities,
      },
      stateChanges: {...stateChanges, ...patch.stateChanges},
      rawUserEntries: {
        ...rawUserEntries,
        ...patch.rawUserEntries,
      }.toList(),
      note: patch.note.isNotEmpty ? patch.note : note,
    );
  }

  InneraAiHealthEventDraft copyWith({String? note}) => InneraAiHealthEventDraft(
        id: id,
        eventTime: eventTime,
        timeContext: timeContext,
        timePrecision: timePrecision,
        emotions: emotions,
        symptoms: symptoms,
        symptomSeverities: symptomSeverities,
        stateChanges: stateChanges,
        rawUserEntries: rawUserEntries,
        note: note ?? this.note,
      );

  InneraAiHealthEventDraft withSymptomSeverity(
    String symptom,
    int? severity,
  ) {
    if (!symptoms.contains(symptom)) return this;
    final updated = <String, int>{...symptomSeverities};
    if (severity == null) {
      updated.remove(symptom);
    } else {
      updated[symptom] = severity.clamp(1, 5);
    }
    return InneraAiHealthEventDraft(
      id: id,
      eventTime: eventTime,
      timeContext: timeContext,
      timePrecision: timePrecision,
      emotions: emotions,
      symptoms: symptoms,
      symptomSeverities: updated,
      stateChanges: stateChanges,
      rawUserEntries: rawUserEntries,
      note: note,
    );
  }

  InneraAiHealthEventDraft withEmotionScore(String key, int score) =>
      _copyWithEmotions(
        emotions
            .map(
              (item) => item.dedupeKey == key
                  ? item.copyWith(score: score.clamp(1, 5))
                  : item,
            )
            .toList(),
      );

  InneraAiHealthEventDraft withEmotionDimension(
    String key,
    EmotionDimensionDefinition dimension,
  ) =>
      _copyWithEmotions(
        emotions
            .map(
              (item) => item.dedupeKey == key
                  ? item.copyWith(dimension: dimension)
                  : item,
            )
            .toList(),
      );

  InneraAiHealthEventDraft withoutEmotion(String key) => _copyWithEmotions(
        emotions.where((item) => item.dedupeKey != key).toList(),
      );

  InneraAiHealthEventDraft withStateChange(String id, int? value) {
    if (!const {
      'energy_change',
      'appetite_change',
      'activity_change',
    }.contains(id)) {
      return this;
    }
    final updated = <String, int>{...stateChanges};
    if (value == null) {
      updated.remove(id);
    } else {
      updated[id] = value.clamp(1, 5);
    }
    return InneraAiHealthEventDraft(
      id: this.id,
      eventTime: eventTime,
      timeContext: timeContext,
      timePrecision: timePrecision,
      emotions: emotions,
      symptoms: symptoms,
      symptomSeverities: symptomSeverities,
      stateChanges: updated,
      rawUserEntries: rawUserEntries,
      note: note,
    );
  }

  InneraAiHealthEventDraft _copyWithEmotions(
    List<AiEmotionDraft> updatedEmotions,
  ) =>
      InneraAiHealthEventDraft(
        id: id,
        eventTime: eventTime,
        timeContext: timeContext,
        timePrecision: timePrecision,
        emotions: updatedEmotions,
        symptoms: symptoms,
        symptomSeverities: symptomSeverities,
        stateChanges: stateChanges,
        rawUserEntries: rawUserEntries,
        note: note,
      );

  static String? _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<String> _strings(dynamic value) => value is List
      ? value
          .map((item) => item is Map ? item['name'] : item)
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];

  static Map<String, int> _stateChanges(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, int>{};
    for (final entry in value.entries) {
      final score = (entry.value as num?)?.toInt();
      if (score != null && score >= 1 && score <= 5) {
        result[entry.key.toString()] = score;
      }
    }
    return result;
  }

  static Map<String, int> _symptomSeverities(dynamic value) {
    if (value is! List) return const {};
    final result = <String, int>{};
    for (final item in value.whereType<Map>()) {
      final name = item['name']?.toString().trim() ?? '';
      final severity = (item['severity'] as num?)?.toInt();
      if (name.isNotEmpty &&
          severity != null &&
          severity >= 1 &&
          severity <= 5) {
        result[name] = severity;
      }
    }
    return result;
  }
}

List<InneraAiHealthEventDraft> mergeEquivalentHealthEventDrafts(
  Iterable<InneraAiHealthEventDraft> drafts,
) {
  final result = <InneraAiHealthEventDraft>[];
  for (final draft in drafts) {
    final index = result.indexWhere(
      (existing) =>
          existing.id == draft.id || _isSameEventMinute(existing, draft),
    );
    if (index < 0) {
      result.add(draft);
    } else {
      result[index] = result[index].merge(draft);
    }
  }
  return result;
}

bool _isSameEventMinute(
  InneraAiHealthEventDraft left,
  InneraAiHealthEventDraft right,
) {
  final leftTime = left.eventTime;
  final rightTime = right.eventTime;
  if (leftTime == null || rightTime == null) return false;
  return leftTime.year == rightTime.year &&
      leftTime.month == rightTime.month &&
      leftTime.day == rightTime.day &&
      leftTime.hour == rightTime.hour &&
      leftTime.minute == rightTime.minute;
}

List<InneraAiHealthEventDraft> mergeExplicitHealthEventDrafts({
  required List<InneraAiHealthEventDraft> existing,
  required String text,
  required DateTime messageTime,
}) {
  final drafts = <String, InneraAiHealthEventDraft>{
    for (final item in existing) item.id: item,
  };
  String? activeId = existing.isEmpty ? null : existing.last.id;
  final clauses = text
      .replaceAll(RegExp(r'但是|可是|不過|然而'), '，')
      .split(RegExp(r'[，。！？；\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty);

  for (final clause in clauses) {
    if (_isPreviousNightSleepClause(clause)) continue;
    final time = _eventTimeFromClause(clause, messageTime);
    final symptoms = _symptomsFromClause(clause);
    final stateChanges = _stateChangesFromClause(clause);
    final standaloneSeverity = _explicitSeverityFromClause(clause);
    if (symptoms.isEmpty &&
        stateChanges.isEmpty &&
        standaloneSeverity != null &&
        activeId != null) {
      final active = drafts[activeId];
      if (active != null && active.symptoms.isNotEmpty) {
        final patch = InneraAiHealthEventDraft(
          id: activeId,
          symptomSeverities: {
            for (final symptom in active.symptoms) symptom: standaloneSeverity,
          },
          rawUserEntries: [clause],
        );
        drafts[activeId] = active.merge(patch);
      }
      continue;
    }
    final hasEventContent = symptoms.isNotEmpty ||
        stateChanges.isNotEmpty ||
        _hasStateDescription(clause);
    if (!hasEventContent) continue;

    if (time != null) {
      activeId = _matchingEventId(drafts.values, time) ?? time.id;
    } else if (RegExp(r'那時候|當時|那個時候').hasMatch(clause)) {
      activeId ??= existing.isEmpty ? null : existing.last.id;
    }
    activeId ??= 'message-${messageTime.microsecondsSinceEpoch}';

    final patch = InneraAiHealthEventDraft(
      id: activeId,
      eventTime: time?.eventTime,
      timeContext: time?.context,
      timePrecision: time?.precision ?? AiEventTimePrecision.unspecified,
      symptoms: symptoms,
      symptomSeverities: _symptomSeveritiesFromClause(clause, symptoms),
      stateChanges: stateChanges,
      rawUserEntries: [clause],
      note: clause,
    );
    drafts[activeId] = drafts[activeId]?.merge(patch) ?? patch;
  }
  return mergeEquivalentHealthEventDrafts(
    drafts.values.where((item) => item.hasContent),
  );
}

({
  String id,
  DateTime? eventTime,
  String? context,
  AiEventTimePrecision precision,
})? _eventTimeFromClause(String clause, DateTime messageTime) {
  final clock = RegExp(
    r'(凌晨|早上|上午|中午|下午|傍晚|晚上)?\s*([0-9一二三四五六七八九十兩]{1,3})\s*[點时時](?:([0-9一二三四五六七八九十兩]{1,3})\s*分?)?\s*(左右|前後|約)?',
  ).firstMatch(clause);
  if (clock != null) {
    var hour = _chineseClockNumber(clock.group(2));
    final minute = _chineseClockNumber(clock.group(3)) ?? 0;
    if (hour == null || hour > 23 || minute > 59) return null;
    final displayHour = hour;
    final period = clock.group(1);
    if (period == null) {
      final prefix = clause.substring(0, clock.start).trim();
      if (!prefix.endsWith('今天') && !prefix.endsWith('今日')) return null;
    }
    if ((period == '下午' || period == '傍晚' || period == '晚上') && hour < 12) {
      hour += 12;
    }
    if (period == '凌晨' && hour == 12) hour = 0;
    final approximate = clock.group(4) != null;
    final label = '${period ?? '今天'} $displayHour 點'
        '${clock.group(3) == null ? '' : ' $minute 分'}'
        '${approximate ? '左右' : ''}';
    return (
      id: 'time-${hour.toString().padLeft(2, '0')}${minute.toString().padLeft(2, '0')}',
      eventTime: DateTime(
        messageTime.year,
        messageTime.month,
        messageTime.day,
        hour,
        minute,
      ),
      context: label,
      precision: approximate
          ? AiEventTimePrecision.approximate
          : AiEventTimePrecision.exact,
    );
  }

  const contextRules = <String, String>{
    '今天凌晨': '今天凌晨',
    '凌晨': '今天凌晨',
    '今天早上': '今天早上',
    '早上': '今天早上',
    '中午': '中午',
    '下午': '下午',
    '傍晚': '傍晚',
    '晚上': '晚上',
    '今天稍早': '今天稍早',
    '起床後': '起床後',
    '起床的時候': '起床後',
    '吃飯後': '吃飯後',
    '運動後': '運動後',
    '剛剛': '剛剛',
    '現在': '現在',
  };
  for (final rule in contextRules.entries) {
    if (!clause.contains(rule.key)) continue;
    if (rule.value == '現在' || rule.value == '剛剛') {
      final eventTime = DateTime(
        messageTime.year,
        messageTime.month,
        messageTime.day,
        messageTime.hour,
        messageTime.minute,
      );
      return (
        id: 'time-${messageTime.hour.toString().padLeft(2, '0')}'
            '${messageTime.minute.toString().padLeft(2, '0')}',
        eventTime: eventTime,
        context: null,
        precision: AiEventTimePrecision.approximate,
      );
    }
    return (
      id: 'context-${rule.value}',
      eventTime: null,
      context: rule.value,
      precision: AiEventTimePrecision.approximate,
    );
  }
  return null;
}

String? _matchingEventId(
  Iterable<InneraAiHealthEventDraft> drafts,
  ({
    String id,
    DateTime? eventTime,
    String? context,
    AiEventTimePrecision precision,
  }) time,
) {
  for (final draft in drafts.toList().reversed) {
    final draftTime = draft.eventTime;
    final nextTime = time.eventTime;
    if (draftTime != null &&
        nextTime != null &&
        draftTime.year == nextTime.year &&
        draftTime.month == nextTime.month &&
        draftTime.day == nextTime.day &&
        draftTime.hour == nextTime.hour &&
        draftTime.minute == nextTime.minute) {
      return draft.id;
    }
  }
  final nextPeriod = _timePeriod(time.context);
  if (nextPeriod != null && time.eventTime != null) {
    for (final draft in drafts.toList().reversed) {
      if (draft.eventTime == null &&
          _timePeriod(draft.timeContext) == nextPeriod) {
        return draft.id;
      }
    }
  }
  if (time.context != null) return null;
  for (final draft in drafts.toList().reversed) {
    final context = draft.timeContext?.trim().toLowerCase();
    if (draft.id.toLowerCase() == 'now' ||
        context == 'now' ||
        context == '現在' ||
        context == '剛剛') {
      return draft.id;
    }
  }
  return null;
}

String? _timePeriod(String? value) {
  final text = value?.trim().toLowerCase() ?? '';
  if (text.contains('早上') || text.contains('早晨') || text == 'morning') {
    return 'morning';
  }
  if (text.contains('中午') || text == 'noon') return 'noon';
  if (text.contains('下午') || text == 'afternoon') return 'afternoon';
  if (text.contains('晚上') || text == 'evening' || text == 'night') {
    return 'evening';
  }
  return null;
}

int? _chineseClockNumber(String? value) {
  if (value == null || value.isEmpty) return null;
  final arabic = int.tryParse(value);
  if (arabic != null) return arabic;
  const digits = <String, int>{
    '零': 0,
    '一': 1,
    '二': 2,
    '兩': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (value == '十') return 10;
  final tenIndex = value.indexOf('十');
  if (tenIndex >= 0) {
    final tens = tenIndex == 0 ? 1 : digits[value.substring(0, tenIndex)];
    final ones = tenIndex == value.length - 1
        ? 0
        : digits[value.substring(tenIndex + 1)];
    if (tens == null || ones == null) return null;
    return tens * 10 + ones;
  }
  return digits[value];
}

bool _isPreviousNightSleepClause(String clause) =>
    RegExp(r'昨晚|昨天晚上').hasMatch(clause) &&
    RegExp(r'睡|入睡|醒|睡眠').hasMatch(clause);

bool _hasStateDescription(String clause) => RegExp(
      r'比較好|好多了|不舒服|沒精神|沒有精神|狀態|焦慮|低落|難過|生氣|煩躁|平靜|開心|興奮',
    ).hasMatch(clause);

List<String> _symptomsFromClause(String clause) {
  const rules = <String, String>{
    '頭痛': r'頭痛|頭疼|頭很痛',
    '疲倦': r'疲倦|疲憊|很累|好累|超累|沒精神|沒有精神|提不起勁',
    '心悸': r'心悸|心跳很快',
    '噁心反胃': r'噁心|反胃|想吐',
    '胃痛': r'胃痛|胃不舒服',
    '食慾降低': r'沒食慾|沒有食慾|食慾降低|吃不下',
  };
  return [
    for (final rule in rules.entries)
      if (RegExp(rule.value).hasMatch(clause)) rule.key,
  ];
}

Map<String, int> _symptomSeveritiesFromClause(
  String clause,
  List<String> symptoms,
) {
  if (symptoms.isEmpty) return const {};
  final severity = _explicitSeverityFromClause(clause);
  if (severity == null) return const {};
  return {for (final symptom in symptoms) symptom: severity};
}

Map<String, int> _stateChangesFromClause(String clause) {
  const terms = <String, String>{
    'energy_change': r'能量|精神|精力|體力',
    'appetite_change': r'食慾|胃口',
    'activity_change': r'活動量|活動程度',
  };
  final result = <String, int>{};
  for (final entry in terms.entries) {
    final match = RegExp(
      '(?:${entry.value})[^，、。！？\\n]{0,12}([1-5１-５一二三四五兩])\\s*分',
    ).firstMatch(clause);
    final score = _scoreFromText(match?.group(1));
    if (score != null) result[entry.key] = score;
  }
  return result;
}

int? _explicitSeverityFromClause(String clause) {
  final match = RegExp(r'([1-5１-５])\s*分').firstMatch(clause);
  return _scoreFromText(match?.group(1));
}

int? _scoreFromText(String? raw) {
  if (raw == null) return null;
  const fullWidth = '１２３４５';
  const chinese = <String, int>{
    '一': 1,
    '二': 2,
    '兩': 2,
    '三': 3,
    '四': 4,
    '五': 5,
  };
  final score = int.tryParse(raw) ??
      chinese[raw] ??
      (fullWidth.contains(raw) ? fullWidth.indexOf(raw) + 1 : -1);
  return score >= 1 && score <= 5 ? score : null;
}
