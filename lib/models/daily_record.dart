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

/// ------------------------------------------------------
/// 2. 睡眠資料模型
/// ------------------------------------------------------
class SleepData {
  final TimeOfDay? sleepTime; // 準備睡覺
  final TimeOfDay? wakeTime; // 離床活動
  final TimeOfDay? finalWakeTime; // 🔥 新增：甦醒時刻 (睜開眼)
  final String? midWakeList; // 🔥 新增：半夜醒來時間 (文字)
  final int? quality;
  final bool tookHypnotic;
  final String? hypnoticName;
  final String? hypnoticDose;
  final List<String> flags;
  final String? note;
  final List<NapItem> naps;

  const SleepData({
    this.sleepTime,
    this.wakeTime,
    this.finalWakeTime, // 🔥 新增
    this.midWakeList, // 🔥 新增
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

  // 🔥 升級：自動計算夜間睡眠時數 (回傳小時，例如 7.5)
  double? get durationHours {
    // 優先使用 finalWakeTime 計算，如果沒有才用 wakeTime (離床)
    final end = finalWakeTime ?? wakeTime;
    if (sleepTime == null || end == null) return null;
    final mins = DateHelper.calcDurationMinutes(sleepTime!, end);
    final result = double.parse((mins / 60).toStringAsFixed(1));
    debugPrint(
        '🛏️ durationHours 計算：sleepTime=$sleepTime, wakeTime=$end, mins=$mins, result=$result');
    return result;
  }

  // 🔥 新增：取得主要睡眠標籤 (用於列表顯示)
  String? get mainTag => flags.isNotEmpty ? flags.first : null;

  Map<String, dynamic> toMap() {
    return {
      'sleepTime': sleepTime != null ? DateHelper.formatTime(sleepTime) : null,
      'wakeTime': wakeTime != null ? DateHelper.formatTime(wakeTime) : null,
      'finalWakeTime': finalWakeTime != null
          ? DateHelper.formatTime(finalWakeTime)
          : null, // 🔥
      'midWakeList': midWakeList ?? '', // 🔥
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
    debugPrint(
        '🛏️ SleepData.fromMap: sleepTime=$sleepTimeStr, wakeTime=$wakeTimeStr, finalWakeTime=$finalWakeTimeStr');
    return SleepData(
      sleepTime: DateHelper.parseTime(sleepTimeStr),
      wakeTime: DateHelper.parseTime(wakeTimeStr),
      finalWakeTime: DateHelper.parseTime(finalWakeTimeStr), // 🔥
      midWakeList: map['midWakeList'] as String?, // 🔥
      quality: map['quality'] as int?,
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

/// ------------------------------------------------------
/// 4. 每日紀錄總模型
/// ------------------------------------------------------
class DailyRecord {
  final String id;
  final DateTime date;

  final List<Emotion> emotions;
  final List<String> symptoms;
  final SleepData sleep;

  final double? overallMood;

  /// 情緒量表版本：5 = 新版 5 點量表，10 = 舊版 10 點量表（預設）
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
    this.sleep = const SleepData(),
    this.overallMood,
    this.moodScale = 10, // 預設 10 點量表（相容舊資料）
    this.isPeriod = false,
    this.periodStartId,
    this.periodEndId,
    this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'emotions': emotions.map((e) => e.toMap()).toList(),
      'symptoms': symptoms,
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
    final data = doc.data() ?? {};
    final emotions = _parseEmotions(data['emotions']);

    return DailyRecord(
      id: doc.id,
      date:
          _asDate(data['date']) ?? DateTime.tryParse(doc.id) ?? DateTime.now(),
      emotions: emotions,
      symptoms:
          (data['symptoms'] as List?)?.map((e) => e.toString()).toList() ?? [],
      sleep: SleepData.fromMap(data['sleep'] as Map<String, dynamic>?),
      overallMood: _parseOverallMood(data['overallMood'], emotions),
      moodScale: (data['moodScale'] as num?)?.toInt() ?? 10,
      isPeriod: data['isPeriod'] == true,
      periodStartId: data['periodStartId'] as String?,
      periodEndId: data['periodEndId'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
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
