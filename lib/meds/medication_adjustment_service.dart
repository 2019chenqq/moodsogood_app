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
        !_sameNumber(before['intervalDays'], after['intervalDays']);
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

    final date =
        DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day);
    final existing = await _localDb.getAdjustmentRecords(uid);
    final newItems =
        items.where((item) => !_alreadyRecorded(existing, date, item)).toList();
    if (newItems.isEmpty) return false;

    final signature = _canonical(newItems);
    final docId =
        'auto_${_dateKey(date)}_${_fnv1a(signature).toRadixString(16)}';
    await _localDb.addAdjustmentRecord(uid, docId, {
      'date': date.toIso8601String(),
      'note': note,
      'source': source,
      'items': newItems,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _updateSubjectiveTrackingCycles(
      uid: uid,
      changeRecordId: docId,
      changeDate: date,
      items: newItems,
    );
    try {
      await MedicationSubjectiveReminderService().syncForCurrentUser(uid: uid);
    } catch (error) {
      debugPrint('Medication subjective reminder sync deferred: $error');
    }
    return true;
  }

  Future<void> _updateSubjectiveTrackingCycles({
    required String uid,
    required String changeRecordId,
    required DateTime changeDate,
    required List<Map<String, dynamic>> items,
  }) async {
    final byMedication = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final medicationId = item['medDocId']?.toString().trim() ?? '';
      byMedication.putIfAbsent(medicationId, () => []).add(item);
    }

    for (final entry in byMedication.entries) {
      final medicationId = entry.key;
      final medicationItems = entry.value;
      final stopped = medicationItems.any(
        (item) => item['type']?.toString() == 'stopped',
      );
      if (stopped) {
        await _localDb.endActiveSubjectiveTrackingCycles(
          uid: uid,
          medicationId: medicationId,
          endedAt: changeDate,
          reason: 'medicationStopped',
        );
        continue;
      }

      final cycle = MedicationTrackingCycleFactory.fromAdjustmentItems(
        changeRecordId: changeRecordId,
        changeDate: changeDate,
        medicationId: medicationId,
        items: medicationItems,
      );
      if (cycle == null) continue;

      await _localDb.endActiveSubjectiveTrackingCycles(
        uid: uid,
        medicationId: medicationId,
        endedAt: changeDate,
        reason: 'supersededByMedicationChange',
        supersededByChangeRecordId: changeRecordId,
      );
      await _localDb.saveSubjectiveTrackingCycle(uid, cycle);
    }
  }

  bool _alreadyRecorded(
    List<Map<String, dynamic>> records,
    DateTime date,
    Map<String, dynamic> candidate,
  ) {
    for (final record in records) {
      final recordDate = _date(record['date']);
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
        if (oldDose == null || newDose == null || oldDose == newDose) {
          return null;
        }
        changeType = newDose > oldDose
            ? MedicationTrackingChangeType.doseIncreased
            : MedicationTrackingChangeType.doseDecreased;
      } else {
        selected = _firstOfType(items, 'added');
        if (selected != null) {
          changeType = MedicationTrackingChangeType.added;
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
}
