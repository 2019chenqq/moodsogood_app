import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/health_data_encryption_service.dart';
import 'med_symptom_compare_models.dart';
import 'medication_local_db.dart';
import 'medication_subjective_response.dart';

class MedicationCompareRepository {
  MedicationCompareRepository({MedicationLocalDB? localDb})
      : _localDb = localDb ?? MedicationLocalDB();

  final MedicationLocalDB _localDb;

  Future<void> syncAll(String uid) async {
    await syncMedications(uid);
    await syncAdjustmentRecords(uid);
  }

  Future<void> syncMedications(String uid) async {
    final documents = await HealthDataEncryptionService.getEncrypted(
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications'),
    );
    for (final document in documents) {
      final data = document.data;
      await _localDb.addMedication(uid, {
        'id': document.id,
        'name': _text(data['name']),
        'dose': _number(data['dose']),
        'dosePerUnit': _number(data['dosePerUnit']),
        'pillCount': _number(data['pillCount']),
        'concentrationMg': _number(data['concentrationMg']),
        'concentrationMl': _number(data['concentrationMl']),
        'intakeMl': _number(data['intakeMl']),
        'unit': _text(data['unit']),
        'type': _text(data['type']),
        'intervalDays': _integer(data['intervalDays']),
        'scheduleType': _text(data['scheduleType']).isEmpty
            ? 'daily'
            : _text(data['scheduleType']),
        'scheduleIntervalDays': _integer(data['scheduleIntervalDays']),
        'scheduleAnchorDate': toIsoDate(data['scheduleAnchorDate']),
        'weekdays': _integers(data['weekdays']),
        'times': _strings(data['times']),
        'purposes': _strings(data['purposes']),
        'note': _nullableText(data['note']),
        'startDate': toIsoDate(data['startDate']),
        'isActive': data['isActive'] != false,
        'bodySymptoms': _strings(data['bodySymptoms']),
        'purposeOther': _nullableText(data['purposeOther']),
        'createdAt': toIsoDate(data['createdAt']),
        'updatedAt': toIsoDate(data['updatedAt']),
        'lastChangeAt': toIsoDate(data['lastChangeAt']),
      });
    }
  }

  List<int> _integers(dynamic value) => value is Iterable
      ? value
          .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
          .whereType<int>()
          .toList()
      : const <int>[];

  Future<void> syncAdjustmentRecords(String uid) async {
    final documents = await HealthDataEncryptionService.getEncrypted(
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medAdjustments')
          .orderBy('date', descending: true),
    );
    for (final document in documents) {
      final data = document.data;
      await _localDb.addAdjustmentRecord(uid, document.id, {
        'date': toIsoDate(data['date']) ?? data['date']?.toString(),
        'effectiveDateTime': toIsoDate(data['effectiveDateTime']),
        'adjustmentDateTime': toIsoDate(data['adjustmentDateTime']),
        'note': _nullableText(data['note']),
        'source': _nullableText(data['source']),
        'items': _safeItems(data['items']),
        'createdAt': toIsoDate(data['createdAt']),
      });
    }
  }

  Future<List<Map<String, dynamic>>> getMedications(String uid) =>
      _localDb.getMedicationsForDisplay(uid);

  Future<List<MedicationAdjustmentEvent>> getAdjustmentEvents(
      String uid) async {
    final records = await _localDb.getAdjustmentRecords(uid);
    return records.expand(MedicationAdjustmentEvent.fromRecord).toList()
      ..sort((left, right) =>
          right.effectiveDateTime.compareTo(left.effectiveDateTime));
  }

  Future<List<MedicationCompareOption>> getCompareOptions(
    String uid,
    List<MedicationAdjustmentEvent> events,
  ) async {
    final medications = await getMedications(uid);
    return mergeMedicationCompareOptions(medications, events);
  }

  Future<List<MedicationSubjectiveResponse>> getSubjectiveResponses({
    required String uid,
    required String changeRecordId,
    String? medicationId,
  }) =>
      _localDb.getSubjectiveResponses(
        uid: uid,
        changeRecordId: changeRecordId,
        medicationId: medicationId,
      );

  static String? toIsoDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is String) return value;
    return null;
  }

  static List<Map<String, dynamic>> _safeItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) {
      final mapped = <String, dynamic>{};
      item.forEach((key, value) {
        final name = key.toString();
        if (value == null || value is String || value is num || value is bool) {
          mapped[name] = value;
        } else if (value is List) {
          mapped[name] = value.map((entry) => entry.toString()).toList();
        } else {
          debugPrint('略過 medAdjustment 不支援欄位：$name (${value.runtimeType})');
        }
      });
      return mapped;
    }).toList();
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';
  static String? _nullableText(dynamic value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  static double? _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static int? _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static List<String> _strings(dynamic value) => value is List
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];
}
