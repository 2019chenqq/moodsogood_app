import 'package:cloud_firestore/cloud_firestore.dart';

class MedicationLocalDB {
  static final MedicationLocalDB _instance = MedicationLocalDB._internal();

  factory MedicationLocalDB() => _instance;

  MedicationLocalDB._internal();

  CollectionReference<Map<String, dynamic>> _medications(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications');

  CollectionReference<Map<String, dynamic>> _adjustments(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medAdjustments');

  Future<void> addMedication(String uid, Map<String, dynamic> data) async {
    final id = data['id']?.toString();
    if (id == null || id.isEmpty) {
      throw ArgumentError('Medication id is required.');
    }
    await _medications(uid).doc(id).set(
          _toCloudMedication(data),
          SetOptions(merge: true),
        );
  }

  Future<void> updateMedication(
    String uid,
    String docId,
    Map<String, dynamic> data,
  ) async {
    await _medications(uid).doc(docId).set(
          _toCloudMedication(data),
          SetOptions(merge: true),
        );
  }

  Future<void> updateMedicationStatus(
    String uid,
    String docId, {
    required bool isActive,
    String? updatedAt,
    String? lastChangeAt,
  }) async {
    await _medications(uid).doc(docId).set({
      'isActive': isActive,
      'updatedAt': _asTimestamp(updatedAt) ?? FieldValue.serverTimestamp(),
      if (lastChangeAt != null) 'lastChangeAt': _asTimestamp(lastChangeAt),
    }, SetOptions(merge: true));
  }

  Future<void> deleteMedication(String uid, String docId) async {
    await _medications(uid).doc(docId).delete();
  }

  Future<List<Map<String, dynamic>>> getMedications(String uid) async {
    final snapshot = await _medications(uid).get();
    final records =
        snapshot.docs.map((doc) => _fromCloud(doc.id, doc.data())).toList();
    records.sort((a, b) {
      final activeCompare = (b['isActive'] == true ? 1 : 0)
          .compareTo(a['isActive'] == true ? 1 : 0);
      if (activeCompare != 0) return activeCompare;
      return (b['updatedAt'] ?? '').toString().compareTo(
            (a['updatedAt'] ?? '').toString(),
          );
    });
    return records;
  }

  Future<Map<String, dynamic>?> getMedication(
    String uid,
    String docId,
  ) async {
    final doc = await _medications(uid).doc(docId).get();
    final data = doc.data();
    return data == null ? null : _fromCloud(doc.id, data);
  }

  Future<List<Map<String, dynamic>>> getMedicationsForDisplay(String uid) {
    return getMedications(uid);
  }

  Future<void> clearAll() async {
    throw UnsupportedError(
      'Cloud medications must be deleted for an explicit user account.',
    );
  }

  Future<void> addAdjustmentRecord(
    String uid,
    String docId,
    Map<String, dynamic> data,
  ) async {
    await _adjustments(uid).doc(docId).set({
      ...data,
      'date': _asTimestamp(data['date']) ?? data['date'],
      'createdAt':
          _asTimestamp(data['createdAt']) ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> getAdjustmentRecords(String uid) async {
    final snapshot =
        await _adjustments(uid).orderBy('date', descending: true).get();
    return snapshot.docs
        .map((doc) => {
              'id': doc.id,
              ..._normalizeMap(doc.data()),
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAdjustmentRecordsForDisplay(
    String uid,
  ) {
    return getAdjustmentRecords(uid);
  }

  Future<void> applyAdjustmentToMedication(
    String uid,
    String medId, {
    required double dosePerUnit,
    required double pillCount,
    required String unit,
  }) async {
    final totalDose = _roundDose(dosePerUnit * pillCount);
    await _medications(uid).doc(medId).set({
      'dose': totalDose,
      'dosePerUnit': dosePerUnit,
      'pillCount': pillCount,
      'unit': unit,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastChangeAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Map<String, dynamic> _toCloudMedication(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data)..remove('id');
    for (final field in [
      'startDate',
      'createdAt',
      'updatedAt',
      'lastChangeAt',
      'lastChangedAt',
      'resumedAt',
    ]) {
      if (copy[field] != null) {
        copy[field] = _asTimestamp(copy[field]) ?? copy[field];
      }
    }
    copy['updatedAt'] ??= FieldValue.serverTimestamp();
    copy['createdAt'] ??= FieldValue.serverTimestamp();
    return copy;
  }

  Map<String, dynamic> _fromCloud(
    String id,
    Map<String, dynamic> data,
  ) {
    return {
      'id': id,
      ..._normalizeMap(data),
      'times': _asStringList(data['times']),
      'purposes': _asStringList(data['purposes']),
      'bodySymptoms': _asStringList(data['bodySymptoms']),
      'isActive': data['isActive'] != false,
    };
  }

  Map<String, dynamic> _normalizeMap(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) return MapEntry(key, value.toDate().toString());
      return MapEntry(key, value);
    });
  }

  List<String> _asStringList(dynamic value) {
    if (value is Iterable) return value.map((item) => item.toString()).toList();
    if (value is String && value.isNotEmpty) {
      return value.split(',').map((item) => item.trim()).toList();
    }
    return const [];
  }

  Timestamp? _asTimestamp(dynamic value) {
    if (value is Timestamp) return value;
    if (value is DateTime) return Timestamp.fromDate(value);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return Timestamp.fromDate(parsed);
    }
    return null;
  }

  double _roundDose(double value) => (value * 10).round() / 10;
}
