import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/daily_check_in.dart';
import '../models/daily_record.dart';
import '../models/health_event.dart';
import '../models/unified_health_data.dart';
import '../utils/health_data_encryption_service.dart';
import '../utils/state_change_normalizer.dart';

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
    bool preserveSourceEvidence = false,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    final startDay = _day(start);
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    final endExclusive = _day(end).add(const Duration(days: 1));
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
              isLessThan: Timestamp.fromDate(endExclusive),
            ),
      ),
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('dailyCheckIns')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDay)),
      ),
    ]);

    final legacyRecords = results[0]
        .map((doc) => DailyRecord.fromData(doc.id, doc.data))
        .toList();
    final healthEvents =
        results[1].map((doc) => HealthEvent.fromMap(doc.id, doc.data)).toList();
    final dailyCheckIns =
        results[2].map((doc) => DailyCheckIn.fromData(doc.data)).toList();
    if (preserveSourceEvidence) {
      final values = <UnifiedHealthData>[
        ...legacyRecords.map(fromLegacyDailyRecord),
        ...healthEvents.map(fromHealthEvent),
        ...dailyCheckIns.map(fromDailyCheckIn),
      ]..sort((a, b) {
          final dateOrder = a.date.compareTo(b.date);
          if (dateOrder != 0) return dateOrder;
          final left = a.timestamp;
          final right = b.timestamp;
          if (left == null && right == null) return 0;
          if (left == null) return -1;
          if (right == null) return 1;
          return left.compareTo(right);
        });
      return values;
    }
    return normalize(
      legacyRecords: legacyRecords,
      healthEvents: healthEvents,
      dailyCheckIns: dailyCheckIns,
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

    final newerItemsByDay = <String, _PresentItems>{};
    for (final item in events) {
      newerItemsByDay.putIfAbsent(item.dateKey, _PresentItems.new).add(item);
    }
    for (final item in checkIns) {
      newerItemsByDay.putIfAbsent(item.dateKey, _PresentItems.new).add(item);
    }

    final compatibleLegacy = legacy.map((item) {
      final newer = newerItemsByDay[item.dateKey];
      return item.copyWith(
        emotions: newer == null
            ? null
            : item.emotions
                .where((value) => !newer.emotions.contains(_scoredKey(value)))
                .toList(growable: false),
        symptoms: newer == null
            ? null
            : item.symptoms
                .where((value) => !newer.symptoms.contains(_nameKey(value)))
                .toList(growable: false),
        stateChanges: newer == null
            ? null
            : Map.unmodifiable(
                Map.fromEntries(
                  item.stateChanges.entries.where(
                    (entry) => !newer.stateChanges.contains(
                      _stateKey(entry.key, entry.value),
                    ),
                  ),
                ),
              ),
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
      stateChanges:
          Map.unmodifiable(normalizeStateChanges(record.stateChanges)),
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
      stateChanges: Map.unmodifiable(normalizeStateChanges(event.stateChanges)),
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

String _scoredKey(UnifiedScoredValue value) =>
    '${value.name.trim()}\u0000${value.value ?? ''}';

String _nameKey(UnifiedScoredValue value) => value.name.trim();

String _stateKey(String key, int value) =>
    '${normalizeStateChangeKey(key)}\u0000$value';

class _PresentItems {
  final Set<String> emotions = <String>{};
  final Set<String> symptoms = <String>{};
  final Set<String> stateChanges = <String>{};
  bool healthStatus = false;

  void add(UnifiedHealthData item) {
    emotions.addAll(item.emotions.map(_scoredKey));
    symptoms.addAll(item.symptoms.map(_nameKey));
    stateChanges.addAll(
      item.stateChanges.entries.map(
        (entry) => _stateKey(entry.key, entry.value),
      ),
    );
    healthStatus = healthStatus || item.healthStatus != null;
  }
}
