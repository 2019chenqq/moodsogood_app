import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/health_event_repository.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/models/unified_health_data.dart';
import 'package:moodsogood_app/repositories/unified_health_data_repository.dart';
import 'package:moodsogood_app/utils/state_change_normalizer.dart';

void main() {
  group('health data consistency', () {
    test('keeps distinct same-day DailyRecord and HealthEvent emotions', () {
      final data = UnifiedHealthDataRepository.normalize(
        legacyRecords: [
          DailyRecord(
            id: '2026-08-11',
            date: DateTime(2026, 8, 11),
            emotions: const [Emotion(name: '焦慮', value: 4)],
          ),
        ],
        healthEvents: [
          HealthEvent(
            id: 'event-1',
            timestamp: DateTime(2026, 8, 11, 15),
            emotions: const [
              HealthEventEmotion(name: '興奮', intensity: 4),
            ],
          ),
        ],
      );

      expect(
        data.expand((item) => item.emotions).map((item) => item.name),
        containsAll(<String>['焦慮', '興奮']),
      );
    });

    test('removes an identical symptom across legacy and event sources', () {
      final data = UnifiedHealthDataRepository.normalize(
        legacyRecords: [
          DailyRecord(
            id: '2026-08-11',
            date: DateTime(2026, 8, 11),
            symptoms: const ['頭痛'],
          ),
        ],
        healthEvents: [
          HealthEvent(
            id: 'event-1',
            timestamp: DateTime(2026, 8, 11, 15),
            symptoms: const [HealthEventSymptom(name: '頭痛', severity: 3)],
          ),
        ],
      );

      expect(
        data.expand((item) => item.symptoms).where((item) => item.name == '頭痛'),
        hasLength(1),
      );
    });

    test('normalizes legacy state keys and leaves canonical keys unchanged',
        () {
      expect(normalizeStateChangeKey('energy'), 'energy_change');
      expect(normalizeStateChangeKey('energy_change'), 'energy_change');
      expect(
        normalizeStateChanges(const {'energy': 2, 'activity_change': 4}),
        const {'energy_change': 2, 'activity_change': 4},
      );
      expect(
        normalizeStateChanges(const {'energy_change': 5, 'energy': 2}),
        const {'energy_change': 5},
      );
      expect(
        HealthEvent(
          id: 'event-1',
          timestamp: DateTime(2026, 8, 11),
          stateChanges: const {'energy': 2},
        ).toMap()['stateChanges'],
        const {'energy_change': 2},
      );
    });

    test('uses a half-open event date range', () {
      final start = DateTime(2026, 8, 11);
      final endExclusive = DateTime(2026, 8, 12);

      expect(
        HealthEventRepository.isInHalfOpenRange(
          DateTime(2026, 8, 11, 23, 59, 59, 999),
          start: start,
          endExclusive: endExclusive,
        ),
        isTrue,
      );
      expect(
        HealthEventRepository.isInHalfOpenRange(
          DateTime(2026, 8, 12),
          start: start,
          endExclusive: endExclusive,
        ),
        isFalse,
      );
    });

    test('preserves source and precision after item-level deduplication', () {
      final data = UnifiedHealthDataRepository.normalize(
        legacyRecords: [
          DailyRecord(id: '2026-08-11', date: DateTime(2026, 8, 11)),
        ],
        healthEvents: [
          HealthEvent(
            id: 'event-1',
            timestamp: DateTime(2026, 8, 11, 15),
          ),
        ],
      );

      expect(data.first.source, UnifiedHealthDataSource.legacyDailyRecord);
      expect(data.first.precision, UnifiedHealthDataPrecision.day);
      expect(data.last.source, UnifiedHealthDataSource.healthEvent);
      expect(data.last.precision, UnifiedHealthDataPrecision.timestamp);
    });
  });
}
