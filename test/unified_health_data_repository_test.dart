import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/daily_check_in.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/models/unified_health_data.dart';
import 'package:moodsogood_app/repositories/unified_health_data_repository.dart';
import 'package:moodsogood_app/services/health_co_occurrence_service.dart';

void main() {
  group('UnifiedHealthDataRepository compatibility', () {
    test('1. legacy DailyRecord only keeps day precision and no timestamp', () {
      final record = _legacyRecord();

      final result = UnifiedHealthDataRepository.normalize(
        legacyRecords: [record],
      );

      expect(result, hasLength(1));
      expect(result.single.source, UnifiedHealthDataSource.legacyDailyRecord);
      expect(result.single.precision, UnifiedHealthDataPrecision.day);
      expect(result.single.date, DateTime(2026, 8, 9));
      expect(result.single.timestamp, isNull);
      expect(result.single.overallMood, 2.5);

      final coOccurrence = const HealthCoOccurrenceService().calculate(result);
      expect(coOccurrence.eventCoOccurrences, isEmpty);
      expect(
        coOccurrence.legacySameDayRecords[
            HealthCoOccurrenceService.pairKey('焦慮', '頭痛')],
        1,
      );
    });

    test('2. new HealthEvent only preserves true timestamp', () {
      final timestamp = DateTime(2026, 8, 9, 14, 37);
      final event = HealthEvent(
        id: 'event-1',
        timestamp: timestamp,
        emotions: const [HealthEventEmotion(name: '焦慮', intensity: 4)],
        symptoms: const [HealthEventSymptom(name: '頭痛', severity: 3)],
      );

      final result = UnifiedHealthDataRepository.normalize(
        healthEvents: [event],
      );

      expect(result.single.source, UnifiedHealthDataSource.healthEvent);
      expect(result.single.precision, UnifiedHealthDataPrecision.timestamp);
      expect(result.single.timestamp, timestamp);
      final coOccurrence = const HealthCoOccurrenceService().calculate(result);
      expect(
        coOccurrence
            .eventCoOccurrences[HealthCoOccurrenceService.pairKey('焦慮', '頭痛')],
        1,
      );
      expect(coOccurrence.legacySameDayRecords, isEmpty);
    });

    test('3. same-day new data suppresses only overlapping legacy fields', () {
      final event = HealthEvent(
        id: 'event-1',
        timestamp: DateTime(2026, 8, 9, 14, 37),
        emotions: const [HealthEventEmotion(name: '平靜', intensity: 4)],
      );

      final result = UnifiedHealthDataRepository.normalize(
        legacyRecords: [_legacyRecord()],
        healthEvents: [event],
      );
      final legacy = result.singleWhere(
        (item) => item.source == UnifiedHealthDataSource.legacyDailyRecord,
      );

      expect(legacy.emotions, hasLength(1));
      expect(legacy.symptoms.single.name, '頭痛');
      expect(legacy.stateChanges, {'energy_change': 2});
      expect(legacy.timestamp, isNull);
    });

    test('4. DailyCheckIn overallMood wins over legacy overallMood', () {
      final checkIn = DailyCheckIn(
        date: DateTime(2026, 8, 9),
        overallMood: 5,
        healthStatus: 4,
        noSpecialEvent: false,
      );

      final result = UnifiedHealthDataRepository.normalize(
        legacyRecords: [_legacyRecord()],
        dailyCheckIns: [checkIn],
      );
      final legacy = result.singleWhere(
        (item) => item.source == UnifiedHealthDataSource.legacyDailyRecord,
      );
      final baseline = result.singleWhere(
        (item) => item.source == UnifiedHealthDataSource.dailyCheckIn,
      );

      expect(legacy.overallMood, isNull);
      expect(baseline.overallMood, 5);
      expect(baseline.healthStatus, 4);
      expect(result.where((item) => item.overallMood != null), hasLength(1));
    });
  });
}

DailyRecord _legacyRecord() {
  return DailyRecord(
    id: '2026-08-09',
    date: DateTime(2026, 8, 9),
    emotions: const [Emotion(name: '焦慮', value: 4)],
    symptoms: const ['頭痛'],
    stateChanges: const {'energy': 2},
    overallMood: 2.5,
  );
}
