import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:moodsogood_app/ai/innera_ai_record_draft.dart';
import 'package:moodsogood_app/daily/emotion_dimensions.dart';
import 'package:moodsogood_app/daily/body_measurement_input.dart';
import 'package:moodsogood_app/daily/widgets/body_measurement_page.dart';
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
        .mergeExplicitRecordFacts('今天能量 1 分、食慾 4 分，睡前量體重 75.5 公斤，體脂 40%');

    expect(draft.emotions, isEmpty);
    expect(draft.stateChanges['energy_change'], 1);
    expect(draft.stateChanges['appetite_change'], 4);
    expect(draft.symptoms, isEmpty);
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
        'measurementTiming': 'afterBreakfast',
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
      MeasurementTiming.afterBreakfast,
    );
  });

  test('body measurement supports one decimal without truncating integers', () {
    expect(parseBodyMeasurementNumber('75.5'), 75.5);
    expect(parseBodyMeasurementNumber('120.8'), 120.8);
    expect(parseBodyMeasurementNumber('7.55'), isNull);
    expect(parseBodyMeasurementNumber('40..2'), isNull);
    expect(parseBodyMeasurementNumber('-7'), isNull);
    expect(parseBodyMeasurementNumber('abc'), isNull);
    expect(parseBodyMeasurementNumber('75,5'), 75.5);
    expect(formatBodyMeasurementNumber(75.5), '75.5');
    expect(formatBodyMeasurementNumber(86), '86');
  });

  testWidgets('decimal point survives parent value echo while typing',
      (tester) async {
    BodyMeasurement? value;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: BodyMeasurementPage(
              date: DateTime(2026, 8, 9),
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    final weightField = find.byType(TextFormField).first;
    await tester.enterText(weightField, '75.');
    await tester.pump();

    expect(tester.widget<TextFormField>(weightField).controller?.text, '75.');
    await tester.enterText(weightField, '75.5');
    await tester.pump();
    expect(tester.widget<TextFormField>(weightField).controller?.text, '75.5');
    expect(value?.weightKg, 75.5);
  });

  test('body measurement timing and custom time round trip', () {
    const measurement = BodyMeasurement(
      weightKg: 75.5,
      bodyFatPercent: 40.2,
      waistCm: 86,
      measurementTiming: MeasurementTiming.other,
      customMeasurementTime: '運動後',
    );

    final json = measurement.toJson();
    final parsed = BodyMeasurement.fromJson(json);
    expect(json['measurementTiming'], 'other');
    expect(json['customMeasurementTime'], '運動後');
    expect(parsed.measurementTimeDisplay, '運動後');
    expect(parsed.isValid, isTrue);
    expect(
      const BodyMeasurement(measurementTiming: MeasurementTiming.other).isValid,
      isFalse,
    );
  });

  test('legacy timing keys load safely', () {
    final parsed = BodyMeasurement.fromJson({
      'weightKg': 75.5,
      'measurementTiming': 'afterMeal',
    });

    expect(parsed.measurementTiming, MeasurementTiming.other);
    expect(parsed.customMeasurementTime, '飯後（舊版）');
  });

  test('AI maps fixed and custom measurement times without guessing', () {
    final dinner = InneraAiRecordDraft.empty(DateTime(2026, 8, 4))
        .mergeExplicitRecordFacts('晚餐後量的，體重 75.5 公斤');
    final waking = InneraAiRecordDraft.empty(DateTime(2026, 8, 4))
        .mergeExplicitRecordFacts('起床量 75.5 公斤');
    final custom = InneraAiRecordDraft.empty(DateTime(2026, 8, 4))
        .mergeExplicitRecordFacts('運動後量體重 75.5 公斤');
    final noTiming = InneraAiRecordDraft.empty(DateTime(2026, 8, 4))
        .mergeExplicitRecordFacts('體重 75.5 公斤');

    expect(dinner.bodyMeasurement?.measurementTiming,
        MeasurementTiming.afterDinner);
    expect(waking.bodyMeasurement?.measurementTiming,
        MeasurementTiming.afterWaking);
    expect(custom.bodyMeasurement?.measurementTiming, MeasurementTiming.other);
    expect(custom.bodyMeasurement?.customMeasurementTime, '運動後');
    expect(noTiming.bodyMeasurement?.measurementTiming, isNull);
  });

  test('AI rejects over-precision and out-of-range values', () {
    const original = '體重 75.55 公斤，腰圍 999 公分';
    final draft = InneraAiRecordDraft.empty(DateTime(2026, 8, 4)).mergePatch(
      {
        'bodyMeasurement': {
          'weightKg': 75.55,
          'waistCm': 999,
        },
      },
      rawUserEntry: original,
    ).mergeExplicitRecordFacts('體重 75.55 公斤，腰圍 999 公分');

    expect(draft.bodyMeasurement, isNull);
    expect(draft.rawUserEntries, contains(original));
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
