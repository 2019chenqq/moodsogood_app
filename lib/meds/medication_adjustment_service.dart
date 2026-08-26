import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'medication_local_db.dart';
import 'medication_subjective_reminder_service.dart';
import 'medication_subjective_tracking_cycle.dart';

/// The single definition of a clinically meaningful medication change.
class MedicationChangeDetector {
  const MedicationChangeDetector._();

  static List<Map<String, dynamic>> detect({
    required String medDocId,
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
    String source = 'medicationEdit',
  }) {
    if (medDocId.trim().isEmpty) {
      throw ArgumentError.value(medDocId, 'medDocId', 'must not be empty');
    }

    final name = _text(after['name'] ?? before['name'], fallback: '未命名藥物');
    final oldTimes = _strings(before['times']);
    final newTimes = _strings(after['times']);
    final oldUnit = _nullableText(before['unit']);
    final newUnit = _nullableText(after['unit']);

    final doseChanged =
        !_sameNumber(_resolvedDose(before), _resolvedDose(after)) ||
            !_sameNumber(before['dosePerUnit'], after['dosePerUnit']) ||
            !_sameNumber(before['pillCount'], after['pillCount']) ||
            !_sameNumber(before['concentrationMg'], after['concentrationMg']) ||
            !_sameNumber(before['concentrationMl'], after['concentrationMl']) ||
            !_sameNumber(before['intakeMl'], after['intakeMl']) ||
            !_sameText(oldUnit, newUnit);
    final scheduleChanged = !_sameStrings(oldTimes, newTimes) ||
        !_sameNumber(before['intervalDays'], after['intervalDays']) ||
        !_sameText(
          _nullableText(before['scheduleType']) ?? 'daily',
          _nullableText(after['scheduleType']) ?? 'daily',
        ) ||
        !_sameNumber(
          before['scheduleIntervalDays'],
          after['scheduleIntervalDays'],
        ) ||
        !_sameStrings(
          _strings(before['weekdays']),
          _strings(after['weekdays']),
        );
    final oldActive = _bool(before['isActive'], fallback: true);
    final newActive = _bool(after['isActive'], fallback: true);

    Map<String, dynamic> base(String type) => <String, dynamic>{
          'medDocId': medDocId,
          'name': name,
          'type': type,
          'oldDose': _resolvedDose(before),
          'newDose': _resolvedDose(after),
          'oldDosePerUnit': _number(before['dosePerUnit']),
          'newDosePerUnit': _number(after['dosePerUnit']),
          'oldPillCount': _number(before['pillCount']),
          'newPillCount': _number(after['pillCount']),
          'oldTimes': oldTimes,
          'newTimes': newTimes,
          'oldScheduleType': before['scheduleType'] ?? 'daily',
          'newScheduleType': after['scheduleType'] ?? 'daily',
          'oldScheduleIntervalDays': before['scheduleIntervalDays'],
          'newScheduleIntervalDays': after['scheduleIntervalDays'],
          'oldWeekdays': before['weekdays'] ?? const <int>[],
          'newWeekdays': after['weekdays'] ?? const <int>[],
          'oldUnit': oldUnit,
          'newUnit': newUnit,
          'unit': newUnit ?? oldUnit,
          'source': source,
        };

    final items = <Map<String, dynamic>>[];
    if (doseChanged) {
      items.add(base('doseChanged'));
    }
    if (!doseChanged && scheduleChanged) {
      items.add(base('scheduleChanged'));
    }
    if (oldActive != newActive) {
      items.add(base(newActive ? 'resumed' : 'stopped'));
    }
    return items;
  }

  static Map<String, dynamic> addedItem({
    required String medDocId,
    required Map<String, dynamic> medication,
    String source = 'standaloneMedicationCreate',
  }) {
    if (medDocId.trim().isEmpty) {
      throw ArgumentError.value(medDocId, 'medDocId', 'must not be empty');
    }
    return <String, dynamic>{
      'medDocId': medDocId,
      'name': _text(medication['name'], fallback: '未命名藥物'),
      'type': 'added',
      'oldDose': null,
      'newDose': _resolvedDose(medication),
      'oldDosePerUnit': null,
      'newDosePerUnit': _number(medication['dosePerUnit']),
      'oldPillCount': null,
      'newPillCount': _number(medication['pillCount']),
      'oldTimes': const <String>[],
      'newTimes': _strings(medication['times']),
      'oldScheduleType': null,
      'newScheduleType': medication['scheduleType'] ?? 'daily',
      'oldScheduleIntervalDays': null,
      'newScheduleIntervalDays': medication['scheduleIntervalDays'],
      'oldWeekdays': const <int>[],
      'newWeekdays': medication['weekdays'] ?? const <int>[],
      'oldUnit': null,
      'newUnit': _nullableText(medication['unit']),
      'unit': _nullableText(medication['unit']),
      'oldIsActive': false,
      'newIsActive': _bool(medication['isActive'], fallback: true),
      'source': source,
    };
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  static double? _resolvedDose(Map<String, dynamic> medication) {
    final total = _number(medication['dose']);
    if (total != null) return total;
    final dosePerUnit = _number(medication['dosePerUnit']);
    final pillCount = _number(medication['pillCount']);
    if (dosePerUnit == null || pillCount == null) return null;
    return dosePerUnit * pillCount;
  }

  static bool _sameNumber(dynamic left, dynamic right) {
    final a = _number(left);
    final b = _number(right);
    if (a == null || b == null) return a == b;
    return (a - b).abs() < 0.0001;
  }

  static String _text(dynamic value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static bool _sameText(String? left, String? right) =>
      (left ?? '').trim().toLowerCase() == (right ?? '').trim().toLowerCase();

  static List<String> _strings(dynamic value) {
    final values = value is List
        ? value.map((entry) => entry.toString())
        : value is String
            ? value.split(',')
            : const <String>[];
    return values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static bool _bool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return fallback;
  }
}

class MedicationAdjustmentService {
  MedicationAdjustmentService({MedicationLocalDB? localDb})
      : _localDb = localDb ?? MedicationLocalDB();

  final MedicationLocalDB _localDb;
  static const Duration episodeJoinWindow = Duration(hours: 48);

  /// Rebuilds the latest episode from immutable adjustment events. Consecutive
  /// events no more than 48 hours apart belong to the same treatment episode.
  Future<void> repairMissingLatestTrackingCycles({required String uid}) async {
    final records = await _localDb.getAdjustmentRecords(uid);
    records.sort((left, right) {
      final a = _date(left['effectiveDateTime']) ??
          _date(left['date']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final b = _date(right['effectiveDateTime']) ??
          _date(right['date']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return b.compareTo(a);
    });
    final eligible = <_EpisodeAdjustment>[];
    for (final record in records) {
      final source = (record['source'] ?? '').toString();
      if (!shouldCreateSubjectiveTrackingCycle(source)) continue;
      final changeRecordId = (record['id'] ?? '').toString().trim();
      final changeDate =
          _date(record['effectiveDateTime']) ?? _date(record['date']);
      final rawItems = record['items'];
      if (changeRecordId.isEmpty || changeDate == null || rawItems is! List) {
        continue;
      }
      final items = rawItems
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList();
      final adjustmentTypes = items
          .map((item) => item['type']?.toString() ?? '')
          .where((type) => type.isNotEmpty)
          .toSet()
          .toList();
      if (!adjustmentTypes.any(_isEpisodeAdjustmentType)) continue;
      eligible.add(_EpisodeAdjustment(
        changeRecordId: changeRecordId,
        date: changeDate,
        items: items,
      ));
    }
    if (eligible.isEmpty) return;

    final episode = <_EpisodeAdjustment>[eligible.first];
    for (final adjustment in eligible.skip(1)) {
      if (episode.last.date.difference(adjustment.date) > episodeJoinWindow) {
        break;
      }
      episode.add(adjustment);
    }
    final latest = episode.first;
    final oldest = episode.last;
    final allItems = episode.expand((item) => item.items).toList();
    final base = _representativeCycle(
      changeRecordId: latest.changeRecordId,
      changeDate: latest.date,
      items: allItems,
    );
    if (base == null) return;
    final episodeId = 'episode_${Uri.encodeComponent(oldest.changeRecordId)}';
    final changeRecordIds = episode.map((item) => item.changeRecordId).toList();
    final medicationIds = allItems
        .map((item) => item['medDocId']?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    final adjustmentTypes = allItems
        .map((item) => item['type']?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    final expected = base.asEpisode(
      id: episodeId,
      episodeId: episodeId,
      episodeStartDate: oldest.date,
      lastAdjustmentDate: latest.date,
      latestChangeRecordId: latest.changeRecordId,
      changeRecordIds: changeRecordIds,
      medicationIds: medicationIds,
      adjustmentTypes: adjustmentTypes,
    );
    await _localDb.endActiveSubjectiveTrackingCyclesExceptCycle(
      uid: uid,
      keepCycleId: expected.id,
      endedAt: latest.date,
      episodeId: episodeId,
    );
    await _localDb.saveSubjectiveTrackingCycle(uid, expected);
    debugPrint(
      '[MedicationSubjective] episodeId=$episodeId '
      'changeRecordIds=${changeRecordIds.join(',')} '
      'episodeStartDate=${oldest.date.toIso8601String()} '
      'day0=${latest.date.toIso8601String()} '
      'medicationIds=${medicationIds.join(',')} '
      'adjustmentTypes=${adjustmentTypes.join(',')} trackingActive=true',
    );
  }

  static bool _isEpisodeAdjustmentType(String type) => const {
        'added',
        'doseChanged',
        'scheduleChanged',
        'resumed',
        'stopped',
      }.contains(type);

  Future<bool> recordAdded({
    required String uid,
    required String medDocId,
    required Map<String, dynamic> medication,
    required DateTime effectiveDate,
    String source = 'standaloneMedicationCreate',
  }) {
    return recordItems(
      uid: uid,
      effectiveDate: effectiveDate,
      source: source,
      note: '新增藥物',
      items: [
        MedicationChangeDetector.addedItem(
          medDocId: medDocId,
          medication: medication,
          source: source,
        ),
      ],
    );
  }

  Future<bool> recordDetectedChanges({
    required String uid,
    required String medDocId,
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
    required DateTime effectiveDate,
    String source = 'medicationEdit',
    String? note,
  }) async {
    final items = MedicationChangeDetector.detect(
      medDocId: medDocId,
      before: before,
      after: after,
      source: source,
    );
    if (items.isEmpty) return false;
    return recordItems(
      uid: uid,
      effectiveDate: effectiveDate,
      source: source,
      note: note,
      items: items,
    );
  }

  Future<bool> recordItems({
    required String uid,
    required DateTime effectiveDate,
    DateTime? adjustmentDateTime,
    required List<Map<String, dynamic>> items,
    required String source,
    String? note,
  }) async {
    if (items.isEmpty) return false;
    for (final item in items) {
      if ((item['medDocId'] ?? '').toString().trim().isEmpty) {
        throw ArgumentError('Every medication adjustment item needs medDocId.');
      }
    }

    // Keep the available time precision. Medication check-in can then apply a
    // change only to dose slots at or after the actual adjustment time.
    final date = effectiveDate;
    final adjustedAt = adjustmentDateTime ?? DateTime.now();
    final existing = await _localDb.getAdjustmentRecords(uid);
    final newItems =
        items.where((item) => !_alreadyRecorded(existing, date, item)).toList();
    if (newItems.isEmpty) return false;

    final signature = _canonical(newItems);
    final docId =
        'auto_${_dateKey(date)}_${_fnv1a(signature).toRadixString(16)}';
    await _localDb.addAdjustmentRecord(uid, docId, {
      'date': adjustedAt.toIso8601String(),
      'adjustmentDateTime': adjustedAt.toIso8601String(),
      'effectiveDateTime': date.toIso8601String(),
      'note': note,
      'source': source,
      'items': newItems,
      'createdAt': DateTime.now().toIso8601String(),
    });
    if (shouldCreateSubjectiveTrackingCycle(source)) {
      await repairMissingLatestTrackingCycles(uid: uid);
    }
    try {
      await MedicationSubjectiveReminderService().syncForCurrentUser(uid: uid);
    } catch (error) {
      debugPrint('Medication subjective reminder sync deferred: $error');
    }
    return true;
  }

  static bool shouldCreateSubjectiveTrackingCycle(String source) {
    final normalized = source.trim().toLowerCase();
    return normalized != 'medicationstartdatefallback' &&
        !normalized.startsWith('synthetic');
  }

  MedicationSubjectiveTrackingCycle? _representativeCycle({
    required String changeRecordId,
    required DateTime changeDate,
    required List<Map<String, dynamic>> items,
  }) {
    final byMedication = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final medicationId = item['medDocId']?.toString().trim() ?? '';
      if (medicationId.isEmpty) continue;
      byMedication.putIfAbsent(medicationId, () => []).add(item);
    }
    final medicationIds = byMedication.keys.toList()..sort();
    for (final medicationId in medicationIds) {
      final medicationItems = byMedication[medicationId]!;
      final cycle = MedicationTrackingCycleFactory.fromAdjustmentItems(
        changeRecordId: changeRecordId,
        changeDate: changeDate,
        medicationId: medicationId,
        items: medicationItems,
      );
      if (cycle != null) return cycle;
    }
    return null;
  }

  bool _alreadyRecorded(
    List<Map<String, dynamic>> records,
    DateTime date,
    Map<String, dynamic> candidate,
  ) {
    for (final record in records) {
      final recordDate =
          _date(record['effectiveDateTime']) ?? _date(record['date']);
      if (recordDate == null || !_sameDay(recordDate, date)) continue;
      final rawItems = record['items'];
      if (rawItems is! List) continue;
      for (final raw in rawItems.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        if (item['medDocId']?.toString() != candidate['medDocId']?.toString() ||
            item['type']?.toString() != candidate['type']?.toString()) {
          continue;
        }
        if (candidate['type'] == 'added' ||
            _canonical(item) == _canonical(candidate)) {
          return true;
        }
      }
    }
    return false;
  }

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(
        value?.toString().trim().replaceAll('/', '-') ?? '');
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  static String _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '$key:${_canonical(value[key])}').join(',')}}';
    }
    if (value is List) return '[${value.map(_canonical).join(',')}]';
    if (value is num) return value.toDouble().toString();
    return value?.toString().trim() ?? 'null';
  }

  static int _fnv1a(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

class MedicationTrackingCycleFactory {
  const MedicationTrackingCycleFactory._();

  static MedicationSubjectiveTrackingCycle? fromAdjustmentItems({
    required String changeRecordId,
    required DateTime changeDate,
    required String medicationId,
    required List<Map<String, dynamic>> items,
  }) {
    if (medicationId.trim().isEmpty || items.isEmpty) return null;

    Map<String, dynamic>? selected;
    MedicationTrackingChangeType? changeType;

    selected = _firstOfType(items, 'resumed');
    if (selected != null) {
      changeType = MedicationTrackingChangeType.resumed;
    } else {
      selected = _firstOfType(items, 'doseChanged');
      if (selected != null) {
        final oldDose = _number(selected['oldDose']);
        final newDose = _number(selected['newDose']);
        if (oldDose != null && newDose != null && oldDose != newDose) {
          changeType = newDose > oldDose
              ? MedicationTrackingChangeType.doseIncreased
              : MedicationTrackingChangeType.doseDecreased;
        } else {
          // Compound and legacy medication records may not expose one
          // comparable total dose. The adjustment is still a real tracking
          // event even when its direction cannot be derived safely.
          changeType = MedicationTrackingChangeType.doseAdjusted;
        }
      }
      if (changeType == null) {
        selected = _firstOfType(items, 'added');
        if (selected != null) {
          changeType = MedicationTrackingChangeType.added;
        }
      }
      if (changeType == null) {
        selected = _firstOfType(items, 'scheduleChanged');
        if (selected != null) {
          changeType = MedicationTrackingChangeType.scheduleChanged;
        }
      }
      if (changeType == null) {
        selected = _firstOfType(items, 'stopped');
        if (selected != null) {
          changeType = MedicationTrackingChangeType.stopped;
        }
      }
    }

    if (selected == null || changeType == null) return null;
    final medicationName = selected['name']?.toString().trim() ?? '';
    if (medicationName.isEmpty) return null;

    return MedicationSubjectiveTrackingCycle(
      id: MedicationSubjectiveTrackingCycle.cycleId(
        changeRecordId,
        medicationId,
      ),
      medicationId: medicationId,
      changeRecordId: changeRecordId,
      changeDate: changeDate,
      medicationName: medicationName,
      changeType: changeType,
      oldDose: _number(selected['oldDose']),
      newDose: _number(selected['newDose']),
      doseUnit: _text(selected['newUnit'] ?? selected['unit']),
      oldTimes: _strings(selected['oldTimes']),
      newTimes: _strings(selected['newTimes']),
      active: true,
    );
  }

  static Map<String, dynamic>? _firstOfType(
    List<Map<String, dynamic>> items,
    String type,
  ) {
    for (final item in items) {
      if (item['type']?.toString() == type) return item;
    }
    return null;
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String? _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<String> _strings(dynamic value) => value is Iterable
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];
}

class _EpisodeAdjustment {
  const _EpisodeAdjustment({
    required this.changeRecordId,
    required this.date,
    required this.items,
  });

  final String changeRecordId;
  final DateTime date;
  final List<Map<String, dynamic>> items;
}
