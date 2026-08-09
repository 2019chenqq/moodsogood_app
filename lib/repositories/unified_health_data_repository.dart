import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/daily_check_in.dart';
import '../models/daily_record.dart';
import '../models/health_event.dart';
import '../models/unified_health_data.dart';
import '../utils/health_data_encryption_service.dart';

class UnifiedHealthDataRepository {
  UnifiedHealthDataRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<List<UnifiedHealthData>> getByDateRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    final startDay = _day(start);
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    final user = _firestore.collection('users').doc(uid);

    final results = await Future.wait([
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('dailyRecords')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDay)),
      ),
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('healthEvents')
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDay),
            )
            .where(
              'timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(endDay),
            ),
      ),
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('dailyCheckIns')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDay)),
      ),
    ]);

    return normalize(
      legacyRecords: results[0]
          .map((doc) => DailyRecord.fromData(doc.id, doc.data))
          .toList(),
      healthEvents: results[1]
          .map((doc) => HealthEvent.fromMap(doc.id, doc.data))
          .toList(),
      dailyCheckIns:
          results[2].map((doc) => DailyCheckIn.fromData(doc.data)).toList(),
    );
  }

  static List<UnifiedHealthData> normalize({
    Iterable<DailyRecord> legacyRecords = const [],
    Iterable<HealthEvent> healthEvents = const [],
    Iterable<DailyCheckIn> dailyCheckIns = const [],
  }) {
    final legacy = legacyRecords.map(fromLegacyDailyRecord).toList();
    final events = healthEvents.map(fromHealthEvent).toList();
    final checkIns = dailyCheckIns.map(fromDailyCheckIn).toList();
    final checkInDays = {for (final item in checkIns) item.dateKey};

    final newFieldsByDay = <String, _PresentFields>{};
    for (final item in events) {
      newFieldsByDay.putIfAbsent(item.dateKey, _PresentFields.new).add(item);
    }
    for (final item in checkIns) {
      newFieldsByDay.putIfAbsent(item.dateKey, _PresentFields.new).add(item);
    }

    final compatibleLegacy = legacy.map((item) {
      final newer = newFieldsByDay[item.dateKey];
      return item.copyWith(
        emotions: newer?.emotions == true ? const [] : null,
        symptoms: newer?.symptoms == true ? const [] : null,
        stateChanges: newer?.stateChanges == true ? const {} : null,
        clearOverallMood: checkInDays.contains(item.dateKey),
        clearHealthStatus: newer?.healthStatus == true,
      );
    });

    final output = <UnifiedHealthData>[
      ...compatibleLegacy,
      ...events,
      ...checkIns,
    ];
    output.sort((a, b) {
      final aTime = a.timestamp ?? a.date;
      final bTime = b.timestamp ?? b.date;
      return aTime.compareTo(bTime);
    });
    return List.unmodifiable(output);
  }

  static UnifiedHealthData fromLegacyDailyRecord(DailyRecord record) {
    return UnifiedHealthData(
      source: UnifiedHealthDataSource.legacyDailyRecord,
      precision: UnifiedHealthDataPrecision.day,
      date: _day(record.date),
      emotions: record.emotions
          .map((item) => UnifiedScoredValue(name: item.name, value: item.value))
          .toList(growable: false),
      symptoms: record.symptoms
          .map((name) => UnifiedScoredValue(name: name))
          .toList(growable: false),
      stateChanges: Map.unmodifiable(record.stateChanges),
      overallMood: record.overallMood,
    );
  }

  static UnifiedHealthData fromHealthEvent(HealthEvent event) {
    return UnifiedHealthData(
      source: UnifiedHealthDataSource.healthEvent,
      precision: UnifiedHealthDataPrecision.timestamp,
      date: _day(event.timestamp),
      timestamp: event.timestamp,
      emotions: event.emotions
          .map(
            (item) =>
                UnifiedScoredValue(name: item.name, value: item.intensity),
          )
          .toList(growable: false),
      symptoms: event.symptoms
          .map(
            (item) => UnifiedScoredValue(name: item.name, value: item.severity),
          )
          .toList(growable: false),
      stateChanges: Map.unmodifiable(event.stateChanges),
    );
  }

  static UnifiedHealthData fromDailyCheckIn(DailyCheckIn checkIn) {
    return UnifiedHealthData(
      source: UnifiedHealthDataSource.dailyCheckIn,
      precision: UnifiedHealthDataPrecision.day,
      date: _day(checkIn.date),
      overallMood: checkIn.overallMood.toDouble(),
      healthStatus: checkIn.healthStatus,
    );
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _PresentFields {
  bool emotions = false;
  bool symptoms = false;
  bool stateChanges = false;
  bool healthStatus = false;

  void add(UnifiedHealthData item) {
    emotions = emotions || item.emotions.isNotEmpty;
    symptoms = symptoms || item.symptoms.isNotEmpty;
    stateChanges = stateChanges || item.stateChanges.isNotEmpty;
    healthStatus = healthStatus || item.healthStatus != null;
  }
}
