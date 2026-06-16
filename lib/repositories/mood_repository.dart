import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../daily/models/local_record.dart';

class MoodRepository {
  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _records =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('moodRecords');

  Future<List<LocalRecord>> getTrendData(int? days) async {
    Query<Map<String, dynamic>> query = _records.orderBy('date');
    if (days != null) {
      final fromDate = DateTime.now().subtract(Duration(days: days));
      query = query.where(
        'date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate),
      );
    }
    final snapshot = await query.get();
    return snapshot.docs.map(_fromDocument).toList();
  }

  Future<void> saveRecord(LocalRecord record, bool isPro) async {
    final docId = _dateId(record.date);
    await _records.doc(docId).set({
      'date': Timestamp.fromDate(
        DateTime(record.date.year, record.date.month, record.date.day),
      ),
      'overallMood': record.overallMood,
      'note': record.note,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    record.id = docId;
    record.updatedAt = DateTime.now();
  }

  Future<Map<String, double>> getMonthlyAverages() async {
    final records = await getTrendData(null);
    final grouped = <String, List<double>>{};
    for (final record in records) {
      final mood = record.overallMood;
      if (mood == null) continue;
      final key =
          '${record.date.year}-${record.date.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(mood);
    }
    return grouped.map(
      (key, scores) => MapEntry(
        key,
        scores.reduce((a, b) => a + b) / scores.length,
      ),
    );
  }

  LocalRecord _fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawDate = data['date'];
    final date = rawDate is Timestamp
        ? rawDate.toDate()
        : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();
    return LocalRecord(
      id: doc.id,
      date: date,
      overallMood: (data['overallMood'] as num?)?.toDouble(),
      note: data['note'] as String?,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  String _dateId(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
