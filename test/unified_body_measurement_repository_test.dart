import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/unified_body_measurement_repository.dart';
import 'package:moodsogood_app/models/body_measurement_record.dart';
import 'package:moodsogood_app/models/daily_record.dart';

void main() {
  group('BodyMeasurementRecord', () {
    test('1. stores 75.5 kg without changing nullable fields', () {
      final record = _record('a', DateTime(2026, 8, 9, 8), weightKg: 75.5);
      final decoded = BodyMeasurementRecord.fromMap('a', record.toMap());

      expect(decoded.weightKg, 75.5);
      expect(decoded.bodyFatPercent, isNull);
      expect(decoded.waistCm, isNull);
      expect(decoded.isValid, isTrue);
    });

    test('2. stores 40.2 percent body fat', () {
      final decoded = BodyMeasurementRecord.fromMap(
        'a',
        _record('a', DateTime(2026, 8, 9, 8), bodyFatPercent: 40.2).toMap(),
      );
      expect(decoded.bodyFatPercent, 40.2);
      expect(decoded.isValid, isTrue);
    });

    test('3. stores 92.3 cm waist', () {
      final decoded = BodyMeasurementRecord.fromMap(
        'a',
        _record('a', DateTime(2026, 8, 9, 8), waistCm: 92.3).toMap(),
      );
      expect(decoded.waistCm, 92.3);
      expect(decoded.isValid, isTrue);
    });

    test('4. multiple timestamp records on one day remain separate', () {
      final records = [
        UnifiedBodyMeasurementRepository.fromCurrent(
          _record('morning', DateTime(2026, 8, 9, 8), weightKg: 75.5),
        ),
        UnifiedBodyMeasurementRepository.fromCurrent(
          _record('evening', DateTime(2026, 8, 9, 20), weightKg: 76.0),
        ),
      ];

      expect(records, hasLength(2));
      expect(records.map((item) => item.id), ['morning', 'evening']);
      expect(records.map((item) => item.timestamp?.hour), [8, 20]);
    });

    test('5. other timing keeps custom text', () {
      final record = _record(
        'a',
        DateTime(2026, 8, 9, 15),
        weightKg: 75.5,
        timing: MeasurementTiming.other,
        otherTimingText: '運動後',
      );
      final decoded = BodyMeasurementRecord.fromMap('a', record.toMap());

      expect(decoded.measurementTiming, MeasurementTiming.other);
      expect(decoded.otherTimingText, '運動後');
      expect(decoded.isValid, isTrue);
    });

    test('6. legacy DailyRecord remains day precision without fake time', () {
      final legacy = UnifiedBodyMeasurementRepository.fromLegacy(
        DailyRecord(
          id: '2026-08-08',
          date: DateTime(2026, 8, 8),
          bodyMeasurement: const BodyMeasurement(weightKg: 74.5),
        ),
      );

      expect(legacy.source, BodyMeasurementSource.legacyDailyRecord);
      expect(legacy.precision, BodyMeasurementPrecision.day);
      expect(legacy.timestamp, isNull);
      expect(legacy.measurement.weightKg, 74.5);
    });

    test('7. daily trend selects latest new measurement', () {
      final date = DateTime(2026, 8, 9);
      final trend = UnifiedBodyMeasurementRepository.selectDailyTrend([
        UnifiedBodyMeasurementRepository.fromLegacy(
          DailyRecord(
            id: 'legacy',
            date: date,
            bodyMeasurement: const BodyMeasurement(weightKg: 74),
          ),
        ),
        UnifiedBodyMeasurementRepository.fromCurrent(
          _record('morning', DateTime(2026, 8, 9, 8), weightKg: 75),
        ),
        UnifiedBodyMeasurementRepository.fromCurrent(
          _record('evening', DateTime(2026, 8, 9, 20), weightKg: 76),
        ),
      ]);

      expect(trend, hasLength(1));
      expect(trend.single.id, 'evening');
      expect(trend.single.measurement.weightKg, 76);
    });

    test('8. legacy and new trend dates remain continuous', () {
      final trend = UnifiedBodyMeasurementRepository.selectDailyTrend([
        UnifiedBodyMeasurementRepository.fromLegacy(
          DailyRecord(
            id: '2026-08-08',
            date: DateTime(2026, 8, 8),
            bodyMeasurement: const BodyMeasurement(weightKg: 74.5),
          ),
        ),
        UnifiedBodyMeasurementRepository.fromCurrent(
          _record('new', DateTime(2026, 8, 9, 8), weightKg: 75.5),
        ),
      ]);

      expect(trend.map((item) => item.date), [
        DateTime(2026, 8, 8),
        DateTime(2026, 8, 9),
      ]);
      expect(trend.map((item) => item.measurement.weightKg), [74.5, 75.5]);
    });
  });
}

BodyMeasurementRecord _record(
  String id,
  DateTime timestamp, {
  double? weightKg,
  double? bodyFatPercent,
  double? waistCm,
  MeasurementTiming? timing,
  String? otherTimingText,
}) {
  return BodyMeasurementRecord(
    id: id,
    timestamp: timestamp,
    weightKg: weightKg,
    bodyFatPercent: bodyFatPercent,
    waistCm: waistCm,
    measurementTiming: timing,
    otherTimingText: otherTimingText,
  );
}
