import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_record.dart';
import '../models/sleep_record.dart';
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
        _sleepRecordService = sleepRecordService ?? SleepRecordService();

  final FirebaseFirestore _firestore;
  final SleepRecordService _sleepRecordService;

  Future<UnifiedSleepRecord?> getForDate({
    required String userId,
    required DateTime date,
  }) async {
    final current = await _sleepRecordService.get(userId: userId, date: date);
    if (current != null) {
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
    final sleep = DailyRecord.fromData(legacyDoc.id, data).sleep;
    final record = SleepRecord.fromSleepData(date, sleep);
    if (!record.hasData) return null;
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
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    final user = _firestore.collection('users').doc(userId);
    final results = await Future.wait([
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('sleepRecords')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDay)),
      ),
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('dailyRecords')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDay)),
      ),
    ]);
    final current = results[0]
        .map((doc) => SleepRecord.fromMap(doc.data))
        .where((record) => record.hasData);
    final legacy = results[1]
        .map((doc) => DailyRecord.fromData(doc.id, doc.data))
        .where((record) =>
            SleepRecord.fromSleepData(record.date, record.sleep).hasData)
        .map((record) => SleepRecord.fromSleepData(record.date, record.sleep));
    return resolve(current: current, legacy: legacy);
  }

  static List<UnifiedSleepRecord> resolve({
    Iterable<SleepRecord> current = const [],
    Iterable<SleepRecord> legacy = const [],
  }) {
    final byDate = <String, UnifiedSleepRecord>{};
    for (final record in legacy) {
      byDate[SleepRecordService.dateId(record.date)] = UnifiedSleepRecord(
        record: record,
        source: SleepRecordSource.legacyDailyRecord,
      );
    }
    for (final record in current) {
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
