import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/date_helper.dart';
import 'daily_record.dart';

class SleepMedication {
  const SleepMedication({
    this.taken = false,
    this.name,
    this.dose,
  });

  final bool taken;
  final String? name;
  final String? dose;

  Map<String, dynamic> toMap() => {
        'taken': taken,
        'name': name?.trim() ?? '',
        'dose': dose?.trim() ?? '',
      };

  factory SleepMedication.fromMap(Map<String, dynamic>? map) {
    return SleepMedication(
      taken: map?['taken'] == true,
      name: map?['name']?.toString(),
      dose: map?['dose']?.toString(),
    );
  }
}

class SleepRecord {
  const SleepRecord({
    required this.date,
    this.bedTime,
    this.sleepStart,
    this.wakeTime,
    this.activityWakeTime,
    this.durationMinutes,
    this.quality,
    this.sleepConditions = const [],
    this.naps = const [],
    this.sleepMedication = const SleepMedication(),
    this.nightAwakenings = const [],
    this.legacyMidWakeText,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  final DateTime date;
  final TimeOfDay? bedTime;
  final TimeOfDay? sleepStart;
  final TimeOfDay? wakeTime;
  final TimeOfDay? activityWakeTime;
  final int? durationMinutes;
  final int? quality;
  final List<String> sleepConditions;
  final List<NapItem> naps;
  final SleepMedication sleepMedication;
  final List<NightAwakeningItem> nightAwakenings;
  final String? legacyMidWakeText;
  final String? note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasData =>
      bedTime != null ||
      sleepStart != null ||
      wakeTime != null ||
      activityWakeTime != null ||
      quality != null ||
      sleepConditions.isNotEmpty ||
      naps.isNotEmpty ||
      nightAwakenings.isNotEmpty ||
      sleepMedication.taken ||
      legacyMidWakeText?.trim().isNotEmpty == true ||
      note?.trim().isNotEmpty == true;

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'bedTime': _format(bedTime),
        'sleepStart': _format(sleepStart),
        'wakeTime': _format(wakeTime),
        'activityWakeTime': _format(activityWakeTime),
        'duration': durationMinutes,
        'quality': quality,
        'sleepConditions': sleepConditions,
        'naps': naps.map((item) => item.toMap()).toList(),
        'sleepMedication': sleepMedication.toMap(),
        'nightAwakenings': nightAwakenings.map((item) => item.toMap()).toList(),
        'legacyMidWakeText': legacyMidWakeText?.trim() ?? '',
        'note': note?.trim() ?? '',
      };

  factory SleepRecord.fromMap(Map<String, dynamic> map) {
    final start = DateHelper.parseTime(
      map['sleepStart'] ?? map['estimatedSleepTime'] ?? map['sleepTime'],
    );
    final wake = DateHelper.parseTime(map['finalWakeTime'] ?? map['wakeTime']);
    final duration =
        (map['duration'] as num?)?.toInt() ?? _durationMinutes(start, wake);
    final medicationMap = map['sleepMedication'] is Map
        ? (map['sleepMedication'] as Map).cast<String, dynamic>()
        : null;
    final medication = medicationMap == null
        ? SleepMedication(
            taken: map['tookHypnotic'] == true,
            name: map['hypnoticName']?.toString(),
            dose: map['hypnoticDose']?.toString(),
          )
        : SleepMedication.fromMap(medicationMap);
    final rawConditions = map['sleepConditions'] ?? map['flags'];

    return SleepRecord(
      date: _asDate(map['date']) ?? DateTime.now(),
      bedTime: DateHelper.parseTime(map['bedTime'] ?? map['sleepTime']),
      sleepStart: start,
      wakeTime: DateHelper.parseTime(map['finalWakeTime'] ?? map['wakeTime']),
      activityWakeTime:
          DateHelper.parseTime(map['activityWakeTime'] ?? map['wakeTime']),
      durationMinutes: duration,
      quality: (map['quality'] as num?)?.toInt(),
      sleepConditions:
          (rawConditions as List?)?.map((item) => item.toString()).toList() ??
              const [],
      naps: (map['naps'] as List?)
              ?.whereType<Map>()
              .map((item) => NapItem.fromMap(item.cast<String, dynamic>()))
              .toList() ??
          const [],
      sleepMedication: medication,
      nightAwakenings: (map['nightAwakenings'] as List?)
              ?.whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .where((item) => DateHelper.parseTime(item['start']) != null)
              .map(NightAwakeningItem.fromMap)
              .toList() ??
          const [],
      legacyMidWakeText:
          (map['legacyMidWakeText'] ?? map['midWakeList'])?.toString(),
      note: map['note']?.toString(),
      createdAt: _asDate(map['createdAt']),
      updatedAt: _asDate(map['updatedAt']),
    );
  }

  factory SleepRecord.fromSleepData(DateTime date, SleepData data) {
    final start = data.effectiveSleepStart;
    final wake = data.finalWakeTime ?? data.wakeTime;
    return SleepRecord(
      date: DateTime(date.year, date.month, date.day),
      bedTime: data.sleepTime,
      sleepStart: start,
      wakeTime: wake,
      activityWakeTime: data.wakeTime,
      durationMinutes: _durationMinutes(start, wake),
      quality: data.quality,
      sleepConditions: List.unmodifiable(data.flags),
      naps: List.unmodifiable(data.naps),
      sleepMedication: SleepMedication(
        taken: data.tookHypnotic,
        name: data.hypnoticName,
        dose: data.hypnoticDose,
      ),
      nightAwakenings: List.unmodifiable(data.nightAwakenings),
      legacyMidWakeText: data.midWakeList,
      note: data.note,
    );
  }

  SleepData toSleepData() => SleepData(
        sleepTime: bedTime,
        estimatedSleepTime: sleepStart == bedTime ? null : sleepStart,
        wakeTime: activityWakeTime,
        finalWakeTime: wakeTime,
        midWakeList: legacyMidWakeText,
        nightAwakenings: nightAwakenings,
        quality: quality,
        tookHypnotic: sleepMedication.taken,
        hypnoticName: sleepMedication.name,
        hypnoticDose: sleepMedication.dose,
        flags: sleepConditions,
        note: note,
        naps: naps,
      );

  static String? _format(TimeOfDay? value) =>
      value == null ? null : DateHelper.formatTime(value);

  static int? _durationMinutes(TimeOfDay? start, TimeOfDay? wake) {
    if (start == null || wake == null) return null;
    return DateHelper.calcDurationMinutes(start, wake);
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
