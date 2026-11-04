import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_record.dart';
import '../models/sleep_record.dart';
import '../models/sleep_record_date.dart';
import '../utils/health_data_encryption_service.dart';
import 'sleep_record_service.dart';

enum SleepRecordSource { sleepRecord, legacyDailyRecord }

class UnifiedSleepRecord {
  const UnifiedSleepRecord({required this.record, required this.source});

  final SleepRecord record;
  final SleepRecordSource source;
}

class UnifiedSleepRepository {
  UnifiedSleepRepository({
    FirebaseFirestore? firestore,
    SleepRecordService? sleepRecordService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _sleepRecordService =
            sleepRecordService ?? SleepRecordService(firestore: firestore);

  final FirebaseFirestore _firestore;
  final SleepRecordService _sleepRecordService;

  Future<UnifiedSleepRecord?> getForDate({
    required String userId,
    required DateTime date,
  }) async {
    final current = await _sleepRecordService.get(userId: userId, date: date);
    if (current != null && current.hasData) {
      return UnifiedSleepRecord(
        record: current,
        source: SleepRecordSource.sleepRecord,
      );
    }
    final legacyDoc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('dailyRecords')
        .doc(SleepRecordService.dateId(date))
        .get();
    final raw = legacyDoc.data();
    if (raw == null) return null;
    final data = await HealthDataEncryptionService.decryptData(raw);
    final record = _legacySleepRecord(legacyDoc.id, data);
    if (record == null ||
        !record.hasData ||
        SleepRecordService.dateId(record.date) !=
            SleepRecordService.dateId(date)) {
      return null;
    }
    return UnifiedSleepRecord(
      record: record,
      source: SleepRecordSource.legacyDailyRecord,
    );
  }

  Future<List<UnifiedSleepRecord>> getByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(end.year, end.month, end.day + 1);
    if (!startDay.isBefore(endExclusive)) return const [];
    final user = _firestore.collection('users').doc(userId);
    Future<List<HealthDocument>> read(String collection) async {
      final reference = user.collection(collection);
      final results = await Future.wait([
        HealthDataEncryptionService.getEncrypted(reference
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('date', isLessThan: Timestamp.fromDate(endExclusive))),
        // Date queries cannot discover missing, invalid or string date fields.
        HealthDataEncryptionService.getEncrypted(reference
            .where(FieldPath.documentId,
                isGreaterThanOrEqualTo: SleepRecordService.dateId(startDay))
            .where(FieldPath.documentId,
                isLessThan: SleepRecordService.dateId(endExclusive))),
      ]);
      return {
        for (final doc in results.expand((items) => items)) doc.id: doc,
      }.values.toList();
    }

    final results =
        await Future.wait([read('sleepRecords'), read('dailyRecords')]);
    final current = results[0].map((doc) {
      final date = sleepRecordDocumentDate(doc.data['date'], doc.id);
      return date == null
          ? null
          : SleepRecord.fromMap({...doc.data, 'date': date});
    }).whereType<SleepRecord>();
    final legacy = results[1]
        .map((doc) => _legacySleepRecord(doc.id, doc.data))
        .whereType<SleepRecord>();
    bool inRange(SleepRecord record) {
      final day =
          DateTime(record.date.year, record.date.month, record.date.day);
      return !day.isBefore(startDay) && day.isBefore(endExclusive);
    }

    return resolve(
      current: current.where(inRange),
      legacy: legacy.where(inRange),
    );
  }

  static SleepRecord? _legacySleepRecord(String id, Map<String, dynamic> data) {
    final date = sleepRecordDocumentDate(data['date'], id);
    if (date == null) return null;
    final rawSleep = data['sleep'];
    return SleepRecord.fromSleepData(
      date,
      SleepData.fromMap(
          rawSleep is Map ? rawSleep.cast<String, dynamic>() : null),
    );
  }

  static List<UnifiedSleepRecord> resolve({
    Iterable<SleepRecord> current = const [],
    Iterable<SleepRecord> legacy = const [],
  }) {
    final byDate = <String, UnifiedSleepRecord>{};
    for (final record in legacy) {
      if (!record.hasData) continue;
      byDate[SleepRecordService.dateId(record.date)] = UnifiedSleepRecord(
        record: record,
        source: SleepRecordSource.legacyDailyRecord,
      );
    }
    for (final record in current) {
      if (!record.hasData) continue;
      byDate[SleepRecordService.dateId(record.date)] = UnifiedSleepRecord(
        record: record,
        source: SleepRecordSource.sleepRecord,
      );
    }
    final output = byDate.values.toList()
      ..sort((a, b) => a.record.date.compareTo(b.record.date));
    return List.unmodifiable(output);
  }

  static List<DailyRecord> overlayForInsights({
    required Iterable<DailyRecord> dailyRecords,
    required Iterable<UnifiedSleepRecord> sleepRecords,
  }) {
    final byDate = {
      for (final record in dailyRecords)
        SleepRecordService.dateId(record.date): record,
    };
    for (final item in sleepRecords) {
      final sleep = item.record.toSleepData();
      final key = SleepRecordService.dateId(item.record.date);
      final existing = byDate[key];
      byDate[key] = DailyRecord(
        id: existing?.id ?? key,
        date: item.record.date,
        emotions: existing?.emotions ?? const [],
        symptoms: existing?.symptoms ?? const [],
        stateChanges: existing?.stateChanges ?? const {},
        symptomSectionCompleted: existing?.symptomSectionCompleted ?? false,
        emotionSectionCompleted: existing?.emotionSectionCompleted ?? false,
        stateSectionCompleted: existing?.stateSectionCompleted ?? false,
        bodyMeasurement: existing?.bodyMeasurement,
        sleep: sleep,
        overallMood: existing?.overallMood,
        moodScale: existing?.moodScale ?? 5,
        isPeriod: existing?.isPeriod ?? false,
        periodStartId: existing?.periodStartId,
        periodEndId: existing?.periodEndId,
        updatedAt: existing?.updatedAt,
      );
    }
    final output = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return output;
  }
}
