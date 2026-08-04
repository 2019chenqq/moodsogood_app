import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_record_draft.dart';
import 'package:moodsogood_app/daily/emotion_dimensions.dart';
import 'package:moodsogood_app/daily/symptom_definitions.dart';
import 'package:moodsogood_app/models/daily_record.dart';

void main() {
  group('DailyRecord new optional fields', () {
    test('old records safely default missing fields', () {
      final record = DailyRecord.fromData('2026-08-03', {
        'date': '2026-08-03',
        'emotions': const [],
        'symptoms': const [],
      });

      expect(record.stateChanges, isEmpty);
      expect(record.bodyMeasurement, isNull);
      expect(record.symptomSectionCompleted, isFalse);
      expect(record.emotionSectionCompleted, isFalse);
      expect(record.stateSectionCompleted, isFalse);
    });

    test('explicit completed flags override empty or non-empty content', () {
      final record = DailyRecord.fromData('2026-08-03', {
        'symptomSectionCompleted': true,
        'symptoms': const [],
        'emotionSectionCompleted': false,
        'emotions': [
          {'name': '平靜', 'value': 4},
        ],
        'stateSectionCompleted': true,
        'stateChanges': const {},
      });

      expect(record.symptomSectionCompleted, isTrue);
      expect(record.emotionSectionCompleted, isFalse);
      expect(record.stateSectionCompleted, isTrue);
    });

    test(
        'legacy non-empty content is backfilled only when record is saved again',
        () {
      final record = DailyRecord.fromData('2026-08-03', {
        'symptoms': ['頭痛'],
        'emotions': [
          {'name': '焦慮', 'value': 3},
        ],
        'stateChanges': {'energy_change': 2},
      });

      expect(record.symptomSectionCompleted, isTrue);
      expect(record.emotionSectionCompleted, isTrue);
      expect(record.stateSectionCompleted, isTrue);
    });

    test('state changes serialize only explicit 1 to 5 values', () {
      final record = DailyRecord.fromData('2026-08-03', {
        'date': '2026-08-03',
        'stateChanges': {
          'energy_change': 1,
          'appetite_change': 3,
          'activity_change': 5,
          'invalid': 8,
        },
      });

      expect(record.stateChanges, {
        'energy_change': 1,
        'appetite_change': 3,
        'activity_change': 5,
      });
      expect(
        const DailyStateItem(id: 'energy_change', name: '能量變化')
            .toJson()['value'],
        isNull,
      );
    });

    test('body weight and fat round trip', () {
      const measurement = BodyMeasurement(
        weightKg: 75.5,
        bodyFatPercent: 40,
        waistCm: 88.2,
        measurementTiming: MeasurementTiming.beforeSleep,
      );

      final parsed = BodyMeasurement.fromJson(measurement.toJson());
      expect(parsed.weightKg, 75.5);
      expect(parsed.bodyFatPercent, 40);
      expect(parsed.waistCm, 88.2);
      expect(parsed.measurementTiming, MeasurementTiming.beforeSleep);
      expect(parsed.isValid, isTrue);
    });
  });

  test('energy appetite and activity are not emotion dimensions', () {
    for (final name in ['能量', '能量變化', '食慾', '食慾變化', '活動量', '活動量變化']) {
      expect(resolveEmotionDimension(name), isNull, reason: name);
    }
  });

  test('formal symptoms and aliases resolve to preset names', () {
    expect(normalizeSymptomName('呼吸不順'), '呼吸困難');
    expect(normalizeSymptomName('食慾不振'), '食慾降低');
    expect(normalizeSymptomName('肌肉抽蓄'), '肌肉抽搐');
    expect(normalizeSymptomName('嗜睡'), '白天嗜睡');
    for (final alias in kLegacySymptomAliases.values) {
      expect(kPresetSymptoms, contains(alias));
    }
  });

  test('AI explicit facts remain separate from emotions', () {
    final draft = InneraAiRecordDraft.empty(DateTime(2026, 8, 3))
        .mergeExplicitRecordFacts('今天完全沒精神，一直想吃東西，睡前量體重 75.5 公斤，體脂 40%');

    expect(draft.emotions, isEmpty);
    expect(draft.stateChanges['energy_change'], 1);
    expect(draft.stateChanges['appetite_change'], 4);
    expect(draft.symptoms, contains('一直想吃東西'));
    expect(draft.bodyMeasurement?.weightKg, 75.5);
    expect(draft.bodyMeasurement?.bodyFatPercent, 40);
    expect(draft.bodyMeasurement?.measurementTiming,
        MeasurementTiming.beforeSleep);
  });

  test('AI draft merges body measurements across separate messages', () {
    final draft = InneraAiRecordDraft.empty(DateTime(2026, 8, 4))
        .mergeExplicitRecordFacts('起床後量體重 75.5 公斤')
        .mergeExplicitRecordFacts('體脂率 39.2%，腰圍 88 公分');

    expect(draft.bodyMeasurement?.weightKg, 75.5);
    expect(draft.bodyMeasurement?.bodyFatPercent, 39.2);
    expect(draft.bodyMeasurement?.waistCm, 88);
    expect(
      draft.bodyMeasurement?.measurementTiming,
      MeasurementTiming.afterWaking,
    );
  });

  test('AI patch preserves existing body fields when adding one value', () {
    final draft = InneraAiRecordDraft.fromMap({
      'dateKey': '2026-08-04',
      'bodyMeasurement': {
        'weightKg': 75.5,
        'measurementTiming': 'beforeBreakfast',
      },
    }).mergePatch({
      'bodyMeasurement': {
        'weightKg': null,
        'bodyFatPercent': 39.2,
        'waistCm': null,
        'measurementTiming': null,
      },
    });

    expect(draft.bodyMeasurement?.weightKg, 75.5);
    expect(draft.bodyMeasurement?.bodyFatPercent, 39.2);
    expect(
      draft.bodyMeasurement?.measurementTiming,
      MeasurementTiming.beforeBreakfast,
    );
  });

  test('draft state changes can be corrected or removed before saving', () {
    final draft = InneraAiRecordDraft.empty(DateTime(2026, 8, 4))
        .withStateChange('energy_change', 2)
        .withStateChange('appetite_change', 4)
        .withStateChange('energy_change', 3)
        .withStateChange('appetite_change', null);

    expect(draft.stateChanges, {'energy_change': 3});
  });
}
