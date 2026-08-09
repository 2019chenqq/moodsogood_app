import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/body_measurement_record.dart';
import '../models/daily_record.dart';
import '../utils/health_data_encryption_service.dart';

enum BodyMeasurementSource { bodyMeasurementRecord, legacyDailyRecord }

enum BodyMeasurementPrecision { timestamp, day }

class UnifiedBodyMeasurement {
  const UnifiedBodyMeasurement({
    required this.source,
    required this.precision,
    required this.date,
    required this.measurement,
    this.timestamp,
    this.id,
  });

  final BodyMeasurementSource source;
  final BodyMeasurementPrecision precision;
  final DateTime date;
  final DateTime? timestamp;
  final String? id;
  final BodyMeasurement measurement;
}

class UnifiedBodyMeasurementRepository {
  UnifiedBodyMeasurementRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<UnifiedBodyMeasurement>> getByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startDay = DateTime(start.year, start.month, start.day);
    final endExclusive =
        DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
    final user = _firestore.collection('users').doc(userId);
    final results = await Future.wait([
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('bodyMeasurements')
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDay),
            )
            .where('timestamp', isLessThan: Timestamp.fromDate(endExclusive)),
      ),
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('dailyRecords')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('date', isLessThan: Timestamp.fromDate(endExclusive)),
      ),
    ]);
    final current = results[0].map(
      (doc) => fromCurrent(BodyMeasurementRecord.fromMap(doc.id, doc.data)),
    );
    final legacy = results[1]
        .map((doc) => DailyRecord.fromData(doc.id, doc.data))
        .where((record) => record.bodyMeasurement?.hasData == true)
        .map(fromLegacy);
    return [
      ...legacy,
      ...current
    ]..sort((a, b) => (a.timestamp ?? a.date).compareTo(b.timestamp ?? b.date));
  }

  static UnifiedBodyMeasurement fromCurrent(BodyMeasurementRecord record) =>
      UnifiedBodyMeasurement(
        source: BodyMeasurementSource.bodyMeasurementRecord,
        precision: BodyMeasurementPrecision.timestamp,
        date: _day(record.timestamp),
        timestamp: record.timestamp,
        id: record.id,
        measurement: record.toLegacyValue(),
      );

  static UnifiedBodyMeasurement fromLegacy(DailyRecord record) =>
      UnifiedBodyMeasurement(
        source: BodyMeasurementSource.legacyDailyRecord,
        precision: BodyMeasurementPrecision.day,
        date: _day(record.date),
        timestamp: null,
        id: record.id,
        measurement: record.bodyMeasurement!,
      );

  static List<UnifiedBodyMeasurement> selectDailyTrend(
    Iterable<UnifiedBodyMeasurement> records,
  ) {
    final byDay = <String, UnifiedBodyMeasurement>{};
    final sorted = records.toList()
      ..sort(
          (a, b) => (a.timestamp ?? a.date).compareTo(b.timestamp ?? b.date));
    for (final record in sorted) {
      final key = _dateKey(record.date);
      final existing = byDay[key];
      if (record.source == BodyMeasurementSource.bodyMeasurementRecord ||
          existing == null) {
        byDay[key] = record;
      }
    }
    return byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}';
}
