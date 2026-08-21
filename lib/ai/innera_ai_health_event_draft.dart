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
  final Map<String, int> stateChanges;
  final List<String> rawUserEntries;
  final String note;

  bool get hasContent =>
      emotions.isNotEmpty ||
      symptoms.isNotEmpty ||
      stateChanges.isNotEmpty ||
      note.trim().isNotEmpty;

  String get timeLabel {
    final context = timeContext?.trim();
    if (context?.isNotEmpty == true) return context!;
    final time = eventTime;
    if (time == null) return '時間待確認';
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
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
        'symptoms': symptoms,
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
      timeContext: patch.timeContext ?? timeContext,
      timePrecision: patch.timePrecision == AiEventTimePrecision.unspecified
          ? timePrecision
          : patch.timePrecision,
      emotions: emotionMap.values.toList(),
      symptoms: {...symptoms, ...patch.symptoms}.toList(),
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
        stateChanges: stateChanges,
        rawUserEntries: rawUserEntries,
        note: note ?? this.note,
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
    final hasEventContent = symptoms.isNotEmpty || _hasStateDescription(clause);
    if (!hasEventContent) continue;

    if (time != null) {
      activeId = time.id;
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
      rawUserEntries: [clause],
      note: clause,
    );
    drafts[activeId] = drafts[activeId]?.merge(patch) ?? patch;
  }
  return drafts.values.where((item) => item.hasContent).toList();
}

({
  String id,
  DateTime? eventTime,
  String context,
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
    return (
      id: 'context-${rule.value}',
      eventTime: null,
      context: rule.value,
      precision: AiEventTimePrecision.approximate,
    );
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
