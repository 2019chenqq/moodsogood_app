import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_helper.dart';

/// ------------------------------------------------------
/// 1. 小睡模型
/// ------------------------------------------------------
class NapItem {
  final TimeOfDay start;
  final TimeOfDay end;

  const NapItem({required this.start, required this.end});

  int get durationMinutes => DateHelper.calcDurationMinutes(start, end);

  Map<String, dynamic> toMap() {
    return {
      'start': DateHelper.formatTime(start),
      'end': DateHelper.formatTime(end),
      'minutes': durationMinutes,
    };
  }

  factory NapItem.fromMap(Map<String, dynamic> map) {
    return NapItem(
      start: DateHelper.parseTime(map['start']) ??
          const TimeOfDay(hour: 0, minute: 0),
      end: DateHelper.parseTime(map['end']) ??
          const TimeOfDay(hour: 0, minute: 0),
    );
  }

  NapItem copyWith({TimeOfDay? start, TimeOfDay? end}) =>
      NapItem(start: start ?? this.start, end: end ?? this.end);
}

/// 夜間醒來紀錄。「再次睡著」與「估計清醒分鐘」均為選填。
class NightAwakeningItem {
  final TimeOfDay start;
  final TimeOfDay? end;
  final int? estimatedDurationMinutes;
  final String? note;

  const NightAwakeningItem({
    required this.start,
    this.end,
    this.estimatedDurationMinutes,
    this.note,
  });

  int? get effectiveDurationMinutes {
    if (end != null) {
      final minutes = DateHelper.calcDurationMinutes(start, end!);
      return minutes > 0 ? minutes : null;
    }
    final estimate = estimatedDurationMinutes;
    return estimate != null && estimate > 0 ? estimate : null;
  }

  Map<String, dynamic> toMap() => {
        'start': DateHelper.formatTime(start),
        'end': end == null ? null : DateHelper.formatTime(end),
        'estimatedDurationMinutes': estimatedDurationMinutes,
        'note': note?.trim() ?? '',
      };

  factory NightAwakeningItem.fromMap(Map<String, dynamic> map) {
    return NightAwakeningItem(
      start: DateHelper.parseTime(map['start'])!,
      end: DateHelper.parseTime(map['end']),
      estimatedDurationMinutes:
          (map['estimatedDurationMinutes'] as num?)?.toInt(),
      note: map['note']?.toString(),
    );
  }

  NightAwakeningItem copyWith({
    TimeOfDay? start,
    TimeOfDay? end,
    bool clearEnd = false,
    int? estimatedDurationMinutes,
    bool clearEstimatedDuration = false,
    String? note,
  }) {
    return NightAwakeningItem(
      start: start ?? this.start,
      end: clearEnd ? null : (end ?? this.end),
      estimatedDurationMinutes: clearEstimatedDuration
          ? null
          : (estimatedDurationMinutes ?? this.estimatedDurationMinutes),
      note: note ?? this.note,
    );
  }
}

/// ------------------------------------------------------
/// 2. 睡眠資料模型
/// ------------------------------------------------------
class SleepData {
  final TimeOfDay? sleepTime; // 準備睡覺（舊欄位，保留相容性）
  final TimeOfDay? estimatedSleepTime; // 推估實際睡著時間（選填）
  final TimeOfDay? wakeTime; // 離床活動
  final TimeOfDay? finalWakeTime; // 🔥 新增：甦醒時刻 (睜開眼)
  final String? midWakeList; // 🔥 新增：半夜醒來時間 (文字)
  final List<NightAwakeningItem> nightAwakenings;
  final int? quality;
  final bool tookHypnotic;
  final String? hypnoticName;
  final String? hypnoticDose;
  final List<String> flags;
  final String? note;
  final List<NapItem> naps;

  const SleepData({
    this.sleepTime,
    this.estimatedSleepTime,
    this.wakeTime,
    this.finalWakeTime, // 🔥 新增
    this.midWakeList, // 🔥 新增
    this.nightAwakenings = const [],
    this.quality,
    this.tookHypnotic = false,
    this.hypnoticName,
    this.hypnoticDose,
    this.flags = const [],
    this.note,
    this.naps = const [],
  });
  // ⬆️ 注意：這裡只有 ); 結束建構子，不要加 } 結束 Class

  factory SleepData.empty() => const SleepData();

  TimeOfDay? get effectiveSleepStart => estimatedSleepTime ?? sleepTime;

  // 自動計算夜間睡眠時數 (回傳小時，例如 7.5)
  double? get durationHours {
    // 優先使用 finalWakeTime 計算，如果沒有才用 wakeTime (離床)
    final end = finalWakeTime ?? wakeTime;
    final start = effectiveSleepStart;
    if (start == null || end == null) return null;
    final mins = DateHelper.calcDurationMinutes(start, end);
    final result = double.parse((mins / 60).toStringAsFixed(1));
    return result;
  }

  // 🔥 新增：取得主要睡眠標籤 (用於列表顯示)
  String? get mainTag => flags.isNotEmpty ? flags.first : null;

  Map<String, dynamic> toMap() {
    return {
      'sleepTime': sleepTime != null ? DateHelper.formatTime(sleepTime) : null,
      'estimatedSleepTime': estimatedSleepTime != null
          ? DateHelper.formatTime(estimatedSleepTime)
          : null,
      'wakeTime': wakeTime != null ? DateHelper.formatTime(wakeTime) : null,
      'finalWakeTime': finalWakeTime != null
          ? DateHelper.formatTime(finalWakeTime)
          : null, // 🔥
      'midWakeList': midWakeList ?? '', // 🔥
      'nightAwakenings': nightAwakenings.map((item) => item.toMap()).toList(),
      'quality': quality,
      'tookHypnotic': tookHypnotic,
      'hypnoticName': hypnoticName ?? '',
      'hypnoticDose': hypnoticDose ?? '',
      'flags': flags,
      'note': note ?? '',
      'naps': naps.map((e) => e.toMap()).toList(),
    };
  }

  factory SleepData.fromMap(Map<String, dynamic>? map) {
    if (map == null) return SleepData.empty();
    final sleepTimeStr = map['sleepTime'];
    final wakeTimeStr = map['wakeTime'];
    final finalWakeTimeStr = map['finalWakeTime'];
    return SleepData(
      sleepTime: DateHelper.parseTime(sleepTimeStr),
      estimatedSleepTime: DateHelper.parseTime(map['estimatedSleepTime']),
      wakeTime: DateHelper.parseTime(wakeTimeStr),
      finalWakeTime: DateHelper.parseTime(finalWakeTimeStr), // 🔥
      midWakeList: map['midWakeList'] as String?, // 🔥
      nightAwakenings: (map['nightAwakenings'] as List?)
              ?.whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .where((item) => DateHelper.parseTime(item['start']) != null)
              .map(NightAwakeningItem.fromMap)
              .toList() ??
          const [],
      quality: (map['quality'] as num?)?.toInt(),
      tookHypnotic: map['tookHypnotic'] == true,
      hypnoticName: map['hypnoticName'] as String?,
      hypnoticDose: map['hypnoticDose'] as String?,
      flags: (map['flags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      note: map['note'] as String?,
      naps: (map['naps'] as List?)
              ?.map((e) => NapItem.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
} // ✅ 正確的 Class 結束位置在這裡

/// ------------------------------------------------------
/// 3. 情緒模型
/// ------------------------------------------------------
class Emotion {
  final String name;
  final int? value;

  const Emotion({required this.name, this.value});

  Map<String, dynamic> toMap() => {'name': name, 'value': value};

  factory Emotion.fromMap(Map<String, dynamic> map) {
    final rawValue = map['value'];
    return Emotion(
      name: (map['name'] ?? '').toString(),
      value: rawValue is num ? rawValue.toInt() : null,
    );
  }
}

class DailyStateItem {
  const DailyStateItem({required this.id, required this.name, this.value});

  final String id;
  final String name;
  final int? value;

  DailyStateItem copyWith({int? value, bool clearValue = false}) =>
      DailyStateItem(
        id: id,
        name: name,
        value: clearValue ? null : value ?? this.value,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'value': value};

  factory DailyStateItem.fromJson(Map<String, dynamic> json) {
    final rawValue = json['value'];
    final parsed = rawValue is num ? rawValue.toInt() : null;
    return DailyStateItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      value: parsed != null && parsed >= 1 && parsed <= 5 ? parsed : null,
    );
  }
}

enum MeasurementTiming {
  afterWaking,
  beforeBreakfast,
  afterMeal,
  beforeSleep,
  other
}

extension MeasurementTimingDisplay on MeasurementTiming {
  String get displayName => switch (this) {
        MeasurementTiming.afterWaking => '起床後',
        MeasurementTiming.beforeBreakfast => '早餐前',
        MeasurementTiming.afterMeal => '飯後',
        MeasurementTiming.beforeSleep => '睡前',
        MeasurementTiming.other => '其他時間',
      };
}

class BodyMeasurement {
  const BodyMeasurement({
    this.weightKg,
    this.bodyFatPercent,
    this.waistCm,
    this.measuredAt,
    this.measurementTiming,
  });

  final double? weightKg;
  final double? bodyFatPercent;
  final double? waistCm;
  final DateTime? measuredAt;
  final MeasurementTiming? measurementTiming;

  bool get hasData =>
      weightKg != null ||
      bodyFatPercent != null ||
      waistCm != null ||
      measurementTiming != null;

  bool get isValid =>
      _inRange(weightKg, 20, 300) &&
      _inRange(bodyFatPercent, 1, 70) &&
      _inRange(waistCm, 30, 250);

  Map<String, dynamic> toJson() => {
        'weightKg': weightKg,
        'bodyFatPercent': bodyFatPercent,
        'waistCm': waistCm,
        'measuredAt': measuredAt?.toIso8601String(),
        'measurementTiming': measurementTiming?.name,
      };

  factory BodyMeasurement.fromJson(Map<String, dynamic> json) {
    final timingName = json['measurementTiming']?.toString();
    final timings = MeasurementTiming.values.where((e) => e.name == timingName);
    return BodyMeasurement(
      weightKg: _asDouble(json['weightKg']),
      bodyFatPercent: _asDouble(json['bodyFatPercent']),
      waistCm: _asDouble(json['waistCm']),
      measuredAt: _asDate(json['measuredAt']),
      measurementTiming: timings.isEmpty ? null : timings.first,
    );
  }

  static bool _inRange(double? value, double min, double max) =>
      value == null || (value >= min && value <= max);

  static double? _asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }
}

/// ------------------------------------------------------
/// 4. 每日紀錄總模型
/// ------------------------------------------------------
class DailyRecord {
  final String id;
  final DateTime date;

  final List<Emotion> emotions;
  final List<String> symptoms;
  final Map<String, int> stateChanges;
  final bool symptomSectionCompleted;
  final bool emotionSectionCompleted;
  final bool stateSectionCompleted;
  final BodyMeasurement? bodyMeasurement;
  final SleepData sleep;

  final double? overallMood;

  /// 情緒量表版本：5 = 新版 5 點量表，10 = 舊版歷史紀錄。
  final int moodScale;

  final bool isPeriod; // 是否是生理期的一天
  final String? periodStartId; // 若這一天是經期「開始」，存這一天的 docId
  final String? periodEndId; // 若這一天是經期「結束」，存這一天的 docId

  final DateTime? updatedAt;

  const DailyRecord({
    required this.id,
    required this.date,
    this.emotions = const [],
    this.symptoms = const [],
    this.stateChanges = const {},
    this.symptomSectionCompleted = false,
    this.emotionSectionCompleted = false,
    this.stateSectionCompleted = false,
    this.bodyMeasurement,
    this.sleep = const SleepData(),
    this.overallMood,
    this.moodScale = 5,
    this.isPeriod = false,
    this.periodStartId,
    this.periodEndId,
    this.updatedAt,
  });

  /// New records always use the current five-point scale.
  static int resolveMoodScaleForNewRecord() => 5;

  /// Only explicitly marked legacy records retain the ten-point scale.
  static int resolveStoredRecordMoodScale(Map<String, dynamic> record) =>
      (record['moodScale'] as num?)?.toInt() == 10 ? 10 : 5;

  Map<String, dynamic> toFirestore() {
    return {
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'emotions': emotions.map((e) => e.toMap()).toList(),
      'symptoms': symptoms,
      'stateChanges': stateChanges,
      'symptomSectionCompleted': symptomSectionCompleted,
      'emotionSectionCompleted': emotionSectionCompleted,
      'stateSectionCompleted': stateSectionCompleted,
      'bodyMeasurement': bodyMeasurement?.toJson(),
      'sleep': sleep.toMap(),
      'overallMood': overallMood,
      'moodScale': moodScale,
      'isPeriod': isPeriod,
      'periodStartId': periodStartId,
      'periodEndId': periodEndId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory DailyRecord.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return DailyRecord.fromData(doc.id, doc.data() ?? {});
  }

  factory DailyRecord.fromData(String id, Map<String, dynamic> data) {
    final emotions = _parseEmotions(data['emotions']);
    final periodData = data['periodData'] is Map
        ? (data['periodData'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final rawSymptoms = data['symptoms'] ?? data['bodySymptoms'];
    final rawSleep = data['sleep'];
    final symptoms = rawSymptoms is List
        ? rawSymptoms.map((e) => e.toString()).toList()
        : const <String>[];
    final stateChanges = _parseStateChanges(data['stateChanges']);
    final sleep = SleepData.fromMap(
      rawSleep is Map ? rawSleep.cast<String, dynamic>() : null,
    );

    return DailyRecord(
      id: id,
      date: _asDate(data['date']) ?? DateTime.tryParse(id) ?? DateTime.now(),
      emotions: emotions,
      symptoms: symptoms,
      stateChanges: stateChanges,
      symptomSectionCompleted: _resolveSectionCompletion(
        data['symptomSectionCompleted'],
        symptoms.any((item) => item.trim().isNotEmpty),
      ),
      emotionSectionCompleted: _resolveSectionCompletion(
        data['emotionSectionCompleted'],
        emotions.any((emotion) => emotion.value != null),
      ),
      stateSectionCompleted: _resolveSectionCompletion(
        data['stateSectionCompleted'],
        stateChanges.isNotEmpty || sleep.quality != null,
      ),
      bodyMeasurement: data['bodyMeasurement'] is Map
          ? BodyMeasurement.fromJson(
              (data['bodyMeasurement'] as Map).cast<String, dynamic>(),
            )
          : null,
      sleep: sleep,
      overallMood: _parseOverallMood(data['overallMood'], emotions),
      moodScale: data.containsKey('moodScale')
          ? resolveStoredRecordMoodScale(data)
          : 10,
      isPeriod: data['isPeriod'] == true || periodData['isPeriod'] == true,
      periodStartId: data['periodStartId'] as String? ??
          periodData['periodStartId'] as String?,
      periodEndId: data['periodEndId'] as String? ??
          periodData['periodEndId'] as String?,
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  static List<Emotion> _parseEmotions(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Emotion.fromMap(e.cast<String, dynamic>()))
          .where((e) => e.name.trim().isNotEmpty)
          .toList();
    }

    if (raw is Map) {
      return raw.entries
          .where((e) => e.key.toString() != '整體情緒')
          .map((e) {
            final value = e.value;
            return Emotion(
              name: e.key.toString(),
              value: value is num ? value.toInt() : null,
            );
          })
          .where((e) => e.name.trim().isNotEmpty)
          .toList();
    }

    return const [];
  }

  static Map<String, int> _parseStateChanges(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, int>{};
    for (final entry in raw.entries) {
      final value = entry.value is num ? (entry.value as num).toInt() : null;
      if (value != null && value >= 1 && value <= 5) {
        result[entry.key.toString()] = value;
      }
    }
    return result;
  }

  static bool _resolveSectionCompletion(dynamic explicit, bool legacyContent) {
    if (explicit is bool) return explicit;
    return legacyContent;
  }

  static double? _parseOverallMood(dynamic raw, List<Emotion> emotions) {
    if (raw is num) return raw.toDouble();
    final values = emotions
        .map((e) => e.value)
        .whereType<int>()
        .where((value) => value > 0)
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
