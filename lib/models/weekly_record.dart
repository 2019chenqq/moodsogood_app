import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklyRecord {
  const WeeklyRecord({
    required this.id,
    required this.weekStart,
    required this.weekEnd,
    required this.overallState,
    this.energyLevel,
    this.feeling,
    this.note,
    this.comparison,
    this.emotions = const [],
    this.primaryEmotion,
    this.primaryEmotionIntensity,
    this.sleepQuality,
    this.poorSleepDays,
    this.sleepIssues = const [],
    this.symptoms = const [],
    this.functionImpacts = const {},
    this.majorChanges = const [],
    this.eventNote,
    this.safetyFlags = const [],
    this.nextWeekFocus,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final DateTime weekStart;
  final DateTime weekEnd;
  final int overallState;
  final int? energyLevel;
  final String? feeling;
  final String? note;
  final String? comparison;
  final List<String> emotions;
  final String? primaryEmotion;
  final int? primaryEmotionIntensity;
  final int? sleepQuality;
  final String? poorSleepDays;
  final List<String> sleepIssues;
  final List<WeeklySymptom> symptoms;
  final Map<String, int> functionImpacts;
  final List<String> majorChanges;
  final String? eventNote;
  final List<String> safetyFlags;
  final String? nextWeekFocus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get visitSummary {
    final parts = <String>[
      '本週整體狀態為 $overallState 分',
      if (comparison != null) '較上週$comparison',
      if (emotions.isNotEmpty) '主要情緒為${emotions.take(3).join('、')}',
      if (primaryEmotion != null && primaryEmotionIntensity != null)
        '$primaryEmotion的影響強度為 $primaryEmotionIntensity 分',
      if (sleepQuality != null) '睡眠品質為 $sleepQuality 分',
      if (poorSleepDays != null) '約有 $poorSleepDays 睡不好',
      if (sleepIssues.isNotEmpty) '主要睡眠狀況為${sleepIssues.take(3).join('、')}',
      if (symptoms.isNotEmpty)
        '明顯症狀為${symptoms.map((item) => item.name).take(3).join('、')}',
      if (functionImpacts.isNotEmpty)
        '日常功能受影響項目為${functionImpacts.keys.take(3).join('、')}',
      if (majorChanges.isNotEmpty && !majorChanges.contains('沒有明顯變化'))
        '本週變化包含${majorChanges.take(3).join('、')}',
    ];
    return '${parts.join('。')}。';
  }

  factory WeeklyRecord.fromData(String id, Map<String, dynamic> data) {
    return WeeklyRecord(
      id: id,
      weekStart:
          _asDate(data['weekStart']) ?? DateTime.tryParse(id) ?? DateTime.now(),
      weekEnd: _asDate(data['weekEnd']) ?? DateTime.now(),
      overallState: (data['overallState'] as num?)?.toInt() ?? 3,
      energyLevel: (data['energyLevel'] as num?)?.toInt(),
      feeling: _optionalText(data['feeling']),
      note: _optionalText(data['note']),
      comparison: _optionalText(data['comparison']),
      emotions: _stringList(data['emotions']),
      primaryEmotion: _optionalText(data['primaryEmotion']),
      primaryEmotionIntensity:
          (data['primaryEmotionIntensity'] as num?)?.toInt(),
      sleepQuality: (data['sleepQuality'] as num?)?.toInt(),
      poorSleepDays: _optionalText(data['poorSleepDays']),
      sleepIssues: _stringList(data['sleepIssues']),
      symptoms: (data['symptoms'] as List?)
              ?.whereType<Map>()
              .map((item) => WeeklySymptom.fromMap(
                    item.cast<String, dynamic>(),
                  ))
              .where((item) => item.name.isNotEmpty)
              .toList() ??
          const [],
      functionImpacts: (data['functionImpacts'] as Map?)?.map(
            (key, value) => MapEntry(
              key.toString(),
              (value as num?)?.toInt() ?? 1,
            ),
          ) ??
          const {},
      majorChanges: _stringList(data['majorChanges']),
      eventNote: _optionalText(data['eventNote']),
      safetyFlags: _stringList(data['safetyFlags']),
      nextWeekFocus: _optionalText(data['nextWeekFocus']),
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _optionalText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<String> _stringList(dynamic value) {
    return (value as List?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList() ??
        const [];
  }
}

class WeeklySymptom {
  const WeeklySymptom({
    required this.name,
    this.intensity = 3,
    this.frequency = '數天',
  });

  final String name;
  final int intensity;
  final String frequency;

  Map<String, dynamic> toMap() => {
        'name': name,
        'intensity': intensity.clamp(1, 5),
        'frequency': frequency,
      };

  factory WeeklySymptom.fromMap(Map<String, dynamic> map) {
    return WeeklySymptom(
      name: map['name']?.toString().trim() ?? '',
      intensity: ((map['intensity'] as num?)?.toInt() ?? 3).clamp(1, 5),
      frequency: map['frequency']?.toString() ?? '數天',
    );
  }
}
