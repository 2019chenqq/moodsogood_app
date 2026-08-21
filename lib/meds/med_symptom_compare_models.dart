import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_health_aggregate.dart';
import '../services/daily_health_aggregation_service.dart';
import '../daily/daily_state_dimensions.dart';
import '../daily/emotion_trend_calculator.dart';

const String medicationCompareNonCausalNotice =
    '同期紀錄與使用者主觀回報僅供整理，不代表藥物造成症狀改善或惡化。';

const meaningfulAdjustmentTypes = <String>{
  'added',
  'doseChanged',
  'scheduleChanged',
  'stopped',
  'resumed',
  'injected',
  'injection',
};

class CompareThresholds {
  const CompareThresholds._();

  static const double emotionMinor = 0.5;
  static const double emotionMeaningful = 1.0;
  static const double emotionHighAttention = 1.5;
  static const double symptomOccurrenceMinor = 15;
  static const double symptomOccurrenceMeaningful = 30;
  static const double symptomSeverityMinor = 0.5;
  static const double symptomSeverityMeaningful = 1.0;
  static const double symptomSeverityHighAttention = 1.5;
}

enum MetricDirection { higherIsWorse, higherIsBetter, neutralChange }

enum MetricDataStatus { observed, explicitlyAbsent, notRecorded }

enum ChangeDirection { increased, decreased, stable, unknown }

enum ChangeMagnitude { stable, minor, meaningful, highAttention }

enum CompareMetricKind { symptom, emotion, state }

enum SymptomChangePattern { improved, worsened, mixed, stable, insufficient }

enum DataAdequacy { unavailable, veryLimited, limited, adequate }

enum SectionRecordStatus { completed, legacyInferred, notCompleted }

class SectionRecordSummary {
  const SectionRecordSummary({
    required this.confirmedRecordedDays,
    required this.inferredRecordedDays,
    required this.notRecordedDays,
  });

  final int confirmedRecordedDays;
  final int inferredRecordedDays;
  final int notRecordedDays;

  int get usableRecordedDays => confirmedRecordedDays + inferredRecordedDays;
  bool get containsInferredData => inferredRecordedDays > 0;
}

enum AdjustmentEventOrigin { persisted, inferredFromMedicationStartDate }

class MedicationCompareOption {
  const MedicationCompareOption({
    required this.key,
    required this.medDocId,
    required this.name,
    required this.isActive,
    required this.existsInMedicationMaster,
    required this.existsOnlyInHistory,
    this.data = const {},
  });

  final String key;
  final String? medDocId;
  final String name;
  final bool isActive;
  final bool existsInMedicationMaster;
  final bool existsOnlyInHistory;
  final Map<String, dynamic> data;

  String get statusLabel => existsOnlyInHistory
      ? '歷史紀錄'
      : isActive
          ? '使用中'
          : '已停用';

  static String normalizedName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

List<MedicationCompareOption> mergeMedicationCompareOptions(
  Iterable<Map<String, dynamic>> medications,
  Iterable<MedicationAdjustmentEvent> events,
) {
  final options = <String, MedicationCompareOption>{};
  for (final medication in medications) {
    final id = (medication['id'] ?? '').toString().trim();
    final name = (medication['name'] ?? '').toString().trim();
    if (id.isEmpty && name.isEmpty) continue;
    final key = id.isNotEmpty
        ? 'id:$id'
        : 'name:${MedicationCompareOption.normalizedName(name)}';
    options[key] = MedicationCompareOption(
      key: key,
      medDocId: id.isEmpty ? null : id,
      name: name.isEmpty ? '未命名藥物' : name,
      isActive: medication['isActive'] != false,
      existsInMedicationMaster: true,
      existsOnlyInHistory: false,
      data: medication,
    );
  }
  for (final event in events) {
    final normalizedName =
        MedicationCompareOption.normalizedName(event.medName);
    if (normalizedName.isEmpty) continue;
    final key = event.medDocId.isNotEmpty
        ? 'id:${event.medDocId}'
        : 'name:$normalizedName';
    options.putIfAbsent(
      key,
      () => MedicationCompareOption(
        key: key,
        medDocId: event.medDocId.isEmpty ? null : event.medDocId,
        name: event.medName,
        isActive: false,
        existsInMedicationMaster: false,
        existsOnlyInHistory: true,
      ),
    );
  }
  final result = options.values.toList()
    ..sort((left, right) {
      int category(MedicationCompareOption option) {
        if (option.existsOnlyInHistory) return 2;
        return option.isActive ? 0 : 1;
      }

      final categoryOrder = category(left).compareTo(category(right));
      if (categoryOrder != 0) return categoryOrder;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
  return result;
}

Map<String, List<MedicationAdjustmentEvent>> groupAdjustmentEvents(
  Iterable<MedicationAdjustmentEvent> events,
) {
  final groups = <String, List<MedicationAdjustmentEvent>>{};
  for (final event in events) {
    groups.putIfAbsent(event.adjustmentId, () => []).add(event);
  }
  return groups;
}

List<MedicationAdjustmentEvent> buildSyntheticAddedEvents(
  Iterable<Map<String, dynamic>> medications,
  Iterable<MedicationAdjustmentEvent> persistedEvents,
) {
  final persistedMedIds = persistedEvents
      .map((event) => event.medDocId.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final inferred = <MedicationAdjustmentEvent>[];
  for (final medication in medications) {
    final medDocId = (medication['id'] ?? '').toString().trim();
    if (medDocId.isEmpty || persistedMedIds.contains(medDocId)) continue;
    final startDate = _modelDate(medication['startDate']);
    if (startDate == null) continue;
    inferred.add(MedicationAdjustmentEvent(
      adjustmentId: 'synthetic-added-$medDocId',
      itemIndex: 0,
      medDocId: medDocId,
      medName: (medication['name'] ?? '未命名藥物').toString().trim(),
      date: DateTime(startDate.year, startDate.month, startDate.day),
      type: 'added',
      newDose: _modelResolvedDose(medication),
      newUnit: _modelText(medication['unit']),
      newDosePerUnit: _modelNumber(medication['dosePerUnit']),
      newPillCount: _modelNumber(medication['pillCount']),
      newTimes: _modelStrings(medication['times']),
      origin: AdjustmentEventOrigin.inferredFromMedicationStartDate,
      source: 'medicationStartDateFallback',
      inferenceReason: '由既有藥物開始日期推定',
    ));
  }
  return inferred;
}

DateTime? _modelDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString().trim().replaceAll('/', '-') ?? '');
}

double? _modelNumber(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString().trim() ?? '');

double? _modelResolvedDose(Map<String, dynamic> medication) {
  final total = _modelNumber(medication['dose']);
  if (total != null) return total;
  final dosePerUnit = _modelNumber(medication['dosePerUnit']);
  final pillCount = _modelNumber(medication['pillCount']);
  if (dosePerUnit == null || pillCount == null) return null;
  return dosePerUnit * pillCount;
}

String? _modelText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

List<String> _modelStrings(dynamic value) => value is List
    ? value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList()
    : const [];

class MedicationAdjustmentEvent {
  const MedicationAdjustmentEvent({
    required this.adjustmentId,
    required this.itemIndex,
    required this.medDocId,
    required this.medName,
    required this.date,
    DateTime? effectiveDateTime,
    required this.type,
    this.oldDose,
    this.newDose,
    this.oldUnit,
    this.newUnit,
    this.oldDosePerUnit,
    this.newDosePerUnit,
    this.oldPillCount,
    this.newPillCount,
    this.oldTimes = const [],
    this.newTimes = const [],
    this.note,
    this.stopReason,
    this.origin = AdjustmentEventOrigin.persisted,
    this.source,
    this.inferenceReason,
  }) : effectiveDateTime = effectiveDateTime ?? date;

  final String adjustmentId;
  final int itemIndex;
  final String medDocId;
  final String medName;
  final DateTime date;
  final DateTime effectiveDateTime;
  final String type;
  final double? oldDose;
  final double? newDose;
  final String? oldUnit;
  final String? newUnit;
  final double? oldDosePerUnit;
  final double? newDosePerUnit;
  final double? oldPillCount;
  final double? newPillCount;
  final List<String> oldTimes;
  final List<String> newTimes;
  final String? note;
  final String? stopReason;
  final AdjustmentEventOrigin origin;
  final String? source;
  final String? inferenceReason;

  bool get isInferred =>
      origin == AdjustmentEventOrigin.inferredFromMedicationStartDate;

  String get eventKey => '$adjustmentId#$itemIndex';

  double? get resolvedOldTotalDose =>
      oldDose ?? _multiply(oldDosePerUnit, oldPillCount);

  double? get resolvedNewTotalDose =>
      newDose ?? _multiply(newDosePerUnit, newPillCount);

  String get dateLabel =>
      '${effectiveDateTime.year.toString().padLeft(4, '0')}/'
      '${effectiveDateTime.month.toString().padLeft(2, '0')}/'
      '${effectiveDateTime.day.toString().padLeft(2, '0')}';

  String get typeLabel => MedicationAdjustmentFormatter.typeLabel(this);

  String get _doseDirectionLabel {
    final oldTotal = resolvedOldTotalDose;
    final newTotal = resolvedNewTotalDose;
    if (_sameUnit(oldUnit, newUnit) && oldTotal != null && newTotal != null) {
      if (newTotal > oldTotal) return '劑量增加';
      if (newTotal < oldTotal) return '劑量降低';
    }
    return '劑量調整';
  }

  String get changeSummary => MedicationAdjustmentFormatter.shortSummary(this);

  String get _rawChangeSummary {
    if (type == 'stopped') {
      return stopReason?.trim().isNotEmpty == true
          ? '停藥（${stopReason!.trim()}）'
          : '停藥';
    }
    if (type == 'resumed') return '恢復使用';
    if (type == 'injected' || type == 'injection') return '已施打';
    if (type == 'scheduleChanged') {
      return '${_timesText(oldTimes)} → ${_timesText(newTimes)}';
    }
    final oldValue = _doseText(
      dose: oldDose,
      dosePerUnit: oldDosePerUnit,
      pillCount: oldPillCount,
      unit: oldUnit,
    );
    final newValue = _doseText(
      dose: newDose,
      dosePerUnit: newDosePerUnit,
      pillCount: newPillCount,
      unit: newUnit,
    );
    if (type == 'added') return newValue == '未提供劑量' ? '新增藥物' : newValue;
    if (oldValue != '未提供劑量' || newValue != '未提供劑量') {
      return '$oldValue → $newValue';
    }
    return typeLabel;
  }

  static List<MedicationAdjustmentEvent> fromRecord(
    Map<String, dynamic> record,
  ) {
    final adjustmentId = (record['id'] ?? '').toString();
    final date = _date(record['date']);
    final effectiveDateTime = _date(record['effectiveDateTime']) ?? date;
    final items = record['items'];
    if (adjustmentId.isEmpty || date == null || items is! List) return const [];

    final events = <MedicationAdjustmentEvent>[];
    for (var index = 0; index < items.length; index++) {
      final raw = items[index];
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final type = (item['type'] ?? '').toString().trim();
      if (!meaningfulAdjustmentTypes.contains(type)) continue;
      events.add(MedicationAdjustmentEvent(
        adjustmentId: adjustmentId,
        itemIndex: index,
        medDocId: (item['medDocId'] ?? item['medId'] ?? '').toString(),
        medName: (item['name'] ?? item['medName'] ?? '未命名藥物').toString().trim(),
        date: date,
        effectiveDateTime: effectiveDateTime,
        type: type,
        oldDose: _number(item['oldDose']),
        newDose: _number(item['newDose']),
        oldUnit: _nullableText(item['oldUnit'] ?? item['unit']),
        newUnit: _nullableText(item['newUnit'] ?? item['unit']),
        oldDosePerUnit: _number(item['oldDosePerUnit']),
        newDosePerUnit: _number(item['newDosePerUnit']),
        oldPillCount: _number(item['oldPillCount']),
        newPillCount: _number(item['newPillCount']),
        oldTimes: _strings(item['oldTimes']),
        newTimes: _strings(item['newTimes']),
        note: _nullableText(item['note'] ?? record['note']),
        stopReason: _nullableText(item['stopReason']),
        source:
            _nullableText(item['source'] ?? item['from'] ?? record['source']),
      ));
    }
    return events;
  }

  static DateTime? _date(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      return DateTime.tryParse(raw.trim().replaceAll('/', '-'));
    }
    return null;
  }

  static double? _number(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString().trim() ?? '');
  }

  static String? _nullableText(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static List<String> _strings(dynamic raw) => raw is List
      ? raw
          .map((value) => value.toString().trim())
          .where((v) => v.isNotEmpty)
          .toList()
      : const [];

  static String _timesText(List<String> values) =>
      values.isEmpty ? '未設定' : values.join('、');

  static String _doseText({
    required double? dose,
    required double? dosePerUnit,
    required double? pillCount,
    required String? unit,
  }) {
    final suffix = unit?.trim().isNotEmpty == true ? ' ${unit!.trim()}' : '';
    if (dose != null) return '${_compact(dose)}$suffix';
    if (dosePerUnit != null && pillCount != null) {
      return '${_compact(dosePerUnit)}$suffix × ${_compact(pillCount)} 顆';
    }
    return '未提供劑量';
  }

  static String _compact(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  static double? _multiply(double? left, double? right) =>
      left == null || right == null ? null : left * right;

  static bool _sameUnit(String? left, String? right) {
    final a = left?.trim().toLowerCase() ?? '';
    final b = right?.trim().toLowerCase() ?? '';
    return a.isNotEmpty && a == b;
  }
}

class MedicationAdjustmentFormatter {
  const MedicationAdjustmentFormatter._();

  static String typeLabel(MedicationAdjustmentEvent event) =>
      switch (event.type) {
        'added' => '新增藥物',
        'doseChanged' => event._doseDirectionLabel,
        'scheduleChanged' => '服用時間調整',
        'stopped' => '停藥',
        'resumed' => '恢復使用',
        'injected' || 'injection' => '施打紀錄',
        _ => '藥物調整',
      };

  static String shortSummary(MedicationAdjustmentEvent event) =>
      event._rawChangeSummary;

  static String detailSummary(MedicationAdjustmentEvent event) {
    return shortSummary(event);
  }
}

class MetricAggregate {
  const MetricAggregate({
    required this.recordedDays,
    required this.scoredDays,
    required this.presentDays,
    required this.occurrenceRate,
    required this.averageScore,
    required this.maximumScore,
    this.confirmedRecordedDays = 0,
    this.inferredRecordedDays = 0,
    this.eventCount = 0,
  });

  final int recordedDays;
  final int scoredDays;
  final int presentDays;
  final double? occurrenceRate;
  final double? averageScore;
  final double? maximumScore;
  final int confirmedRecordedDays;
  final int inferredRecordedDays;
  final int eventCount;
}

class DailyRecordAggregate {
  const DailyRecordAggregate({
    required this.totalRecordDays,
    required this.effectiveRecordDays,
    required this.symptomRecordedDays,
    required this.emotionRecordedDays,
    required this.stateRecordedDays,
    required this.legacyInferredSectionDays,
    required this.symptomRecordSummary,
    required this.emotionRecordSummary,
    required this.stateRecordSummary,
    required this.symptoms,
    required this.emotions,
    required this.states,
  });

  final int totalRecordDays;
  final int effectiveRecordDays;
  final int symptomRecordedDays;
  final int emotionRecordedDays;
  final int stateRecordedDays;
  final int legacyInferredSectionDays;
  final SectionRecordSummary symptomRecordSummary;
  final SectionRecordSummary emotionRecordSummary;
  final SectionRecordSummary stateRecordSummary;
  final Map<String, MetricAggregate> symptoms;
  final Map<String, MetricAggregate> emotions;
  final Map<String, MetricAggregate> states;
}

class DailyRecordAggregator {
  const DailyRecordAggregator._();

  static DailyRecordAggregate aggregate(
      Iterable<Map<String, dynamic>> records) {
    final symptomDays = <String, int>{};
    final symptomScores = <String, List<double>>{};
    final emotionScores = <String, List<double>>{};
    final stateScores = <String, List<double>>{};
    final emotionConfirmedDays = <String, int>{};
    final emotionInferredDays = <String, int>{};
    final stateConfirmedDays = <String, int>{};
    final stateInferredDays = <String, int>{};
    var total = 0;
    var effective = 0;
    var symptomRecorded = 0;
    var emotionRecorded = 0;
    var stateRecorded = 0;
    var legacyInferredSectionDays = 0;
    var symptomConfirmed = 0;
    var symptomInferred = 0;
    var symptomNotRecorded = 0;
    var emotionConfirmed = 0;
    var emotionInferred = 0;
    var emotionNotRecorded = 0;
    var stateConfirmed = 0;
    var stateInferred = 0;
    var stateNotRecorded = 0;

    for (final data in records) {
      total++;
      final symptomStatus = resolveSymptomStatus(data);
      final emotionStatus = resolveEmotionStatus(data);
      final stateStatus = resolveStateStatus(data);
      final hasSymptoms = symptomStatus != SectionRecordStatus.notCompleted;
      final hasEmotions = emotionStatus != SectionRecordStatus.notCompleted;
      final hasStates = stateStatus != SectionRecordStatus.notCompleted;
      void countStatus(
        SectionRecordStatus status,
        void Function() confirmed,
        void Function() inferred,
        void Function() notRecorded,
      ) {
        switch (status) {
          case SectionRecordStatus.completed:
            confirmed();
            break;
          case SectionRecordStatus.legacyInferred:
            inferred();
            break;
          case SectionRecordStatus.notCompleted:
            notRecorded();
            break;
        }
      }

      countStatus(
        symptomStatus,
        () => symptomConfirmed++,
        () => symptomInferred++,
        () => symptomNotRecorded++,
      );
      countStatus(
        emotionStatus,
        () => emotionConfirmed++,
        () => emotionInferred++,
        () => emotionNotRecorded++,
      );
      countStatus(
        stateStatus,
        () => stateConfirmed++,
        () => stateInferred++,
        () => stateNotRecorded++,
      );
      if (hasSymptoms || hasEmotions || hasStates) effective++;
      if (symptomStatus == SectionRecordStatus.legacyInferred ||
          emotionStatus == SectionRecordStatus.legacyInferred ||
          stateStatus == SectionRecordStatus.legacyInferred) {
        legacyInferredSectionDays++;
      }

      if (hasSymptoms) {
        symptomRecorded++;
        final values = _symptoms(
          data['symptoms'] ?? data['bodySymptoms'] ?? data['symptomScores'],
        );
        for (final entry in values.entries) {
          symptomDays[entry.key] = (symptomDays[entry.key] ?? 0) + 1;
          if (entry.value != null) {
            symptomScores.putIfAbsent(entry.key, () => []).add(entry.value!);
          }
        }
      }

      if (hasEmotions) {
        emotionRecorded++;
        final values = _scores(data['emotions'] ?? data['emotionScores']);
        for (final entry in values.entries) {
          emotionScores.putIfAbsent(entry.key, () => []).add(entry.value);
          final counts = emotionStatus == SectionRecordStatus.completed
              ? emotionConfirmedDays
              : emotionInferredDays;
          counts[entry.key] = (counts[entry.key] ?? 0) + 1;
        }
      }

      if (hasStates) {
        stateRecorded++;
        final values = _scores(data['stateChanges']);
        for (final entry in values.entries) {
          final definition = kDailyStateDimensionsById[entry.key];
          final name = definition?.displayName ?? entry.key;
          stateScores.putIfAbsent(name, () => []).add(entry.value);
          final counts = stateStatus == SectionRecordStatus.completed
              ? stateConfirmedDays
              : stateInferredDays;
          counts[name] = (counts[name] ?? 0) + 1;
        }
        final sleep = data['sleep'];
        if (sleep is Map) {
          final quality = _number(sleep['quality'] ?? sleep['sleepQuality']);
          if (quality != null) {
            stateScores.putIfAbsent('睡眠品質', () => []).add(quality);
            final counts = stateStatus == SectionRecordStatus.completed
                ? stateConfirmedDays
                : stateInferredDays;
            counts['睡眠品質'] = (counts['睡眠品質'] ?? 0) + 1;
          }
        }
      }
    }

    final symptoms = <String, MetricAggregate>{};
    for (final name in {...symptomDays.keys, ...symptomScores.keys}) {
      final present = symptomDays[name] ?? 0;
      final scores = symptomScores[name] ?? const [];
      symptoms[name] = MetricAggregate(
        recordedDays: symptomRecorded,
        scoredDays: scores.length,
        presentDays: present,
        occurrenceRate:
            symptomRecorded == 0 ? null : present * 100 / symptomRecorded,
        averageScore: _average(scores),
        maximumScore: _maximum(scores),
        confirmedRecordedDays: symptomConfirmed,
        inferredRecordedDays: symptomInferred,
      );
    }

    return DailyRecordAggregate(
      totalRecordDays: total,
      effectiveRecordDays: effective,
      symptomRecordedDays: symptomRecorded,
      emotionRecordedDays: emotionRecorded,
      stateRecordedDays: stateRecorded,
      legacyInferredSectionDays: legacyInferredSectionDays,
      symptomRecordSummary: SectionRecordSummary(
        confirmedRecordedDays: symptomConfirmed,
        inferredRecordedDays: symptomInferred,
        notRecordedDays: symptomNotRecorded,
      ),
      emotionRecordSummary: SectionRecordSummary(
        confirmedRecordedDays: emotionConfirmed,
        inferredRecordedDays: emotionInferred,
        notRecordedDays: emotionNotRecorded,
      ),
      stateRecordSummary: SectionRecordSummary(
        confirmedRecordedDays: stateConfirmed,
        inferredRecordedDays: stateInferred,
        notRecordedDays: stateNotRecorded,
      ),
      symptoms: symptoms,
      emotions: _scoreAggregates(
        emotionScores,
        emotionConfirmedDays,
        emotionInferredDays,
      ),
      states: _scoreAggregates(
        stateScores,
        stateConfirmedDays,
        stateInferredDays,
      ),
    );
  }

  static DailyRecordAggregate withAggregatedSymptoms(
    DailyRecordAggregate base,
    Iterable<DailyHealthAggregate> aggregates,
  ) {
    final days = aggregates.where((aggregate) => aggregate.recorded).toList();
    final statistics =
        const DailyHealthAggregationService().allSymptomStatistics(days);
    final eventDays =
        days.where((aggregate) => aggregate.eventCount > 0).length;
    final legacySymptomDays = days.where((aggregate) {
      return aggregate.eventCount == 0 &&
          aggregate.hasDailyRecord &&
          aggregate.dailyRecords.any(
            (record) => record.symptoms.any((name) => name.trim().isNotEmpty),
          );
    }).length;
    final symptoms = <String, MetricAggregate>{
      for (final item in statistics)
        item.name: MetricAggregate(
          recordedDays: item.recordedDays,
          scoredDays: item.eventCount,
          presentDays: item.occurrenceDays,
          occurrenceRate:
              item.recordedDays == 0 ? null : item.occurrenceRate * 100,
          averageScore: item.averageSeverity,
          maximumScore: item.maxSeverity?.toDouble(),
          confirmedRecordedDays: eventDays,
          inferredRecordedDays: legacySymptomDays,
          eventCount: item.eventCount,
        ),
    };
    final uniqueRecordedDays = days.map((item) => item.dateKey).toSet().length;
    return DailyRecordAggregate(
      totalRecordDays: uniqueRecordedDays,
      effectiveRecordDays: uniqueRecordedDays,
      symptomRecordedDays: uniqueRecordedDays,
      emotionRecordedDays: base.emotionRecordedDays,
      stateRecordedDays: base.stateRecordedDays,
      legacyInferredSectionDays: base.legacyInferredSectionDays,
      symptomRecordSummary: SectionRecordSummary(
        confirmedRecordedDays: eventDays,
        inferredRecordedDays: legacySymptomDays,
        notRecordedDays: (uniqueRecordedDays -
                {
                  ...days
                      .where((item) => item.symptomDailyValues.isNotEmpty)
                      .map((item) => item.dateKey)
                }.length)
            .clamp(0, uniqueRecordedDays)
            .toInt(),
      ),
      emotionRecordSummary: base.emotionRecordSummary,
      stateRecordSummary: base.stateRecordSummary,
      symptoms: symptoms,
      emotions: base.emotions,
      states: base.states,
    );
  }

  static SectionRecordStatus sectionStatus(
    Map<String, dynamic> data, {
    required List<String> completedKeys,
    required List<String> dataKeys,
  }) {
    for (final key in completedKeys) {
      if (data[key] == true) return SectionRecordStatus.completed;
      if (data[key] == false) return SectionRecordStatus.notCompleted;
    }
    for (final key in dataKeys) {
      if (_hasMeaningfulContent(data[key])) {
        return SectionRecordStatus.legacyInferred;
      }
    }
    return SectionRecordStatus.notCompleted;
  }

  static SectionRecordStatus resolveSymptomStatus(Map<String, dynamic> data) =>
      _explicitSectionStatus(
        data,
        const ['symptomSectionCompleted', 'symptomsCompleted'],
      ) ??
      (_symptoms(
        data['symptoms'] ?? data['bodySymptoms'] ?? data['symptomScores'],
      ).isNotEmpty
          ? SectionRecordStatus.legacyInferred
          : SectionRecordStatus.notCompleted);

  static SectionRecordStatus resolveEmotionStatus(Map<String, dynamic> data) =>
      _explicitSectionStatus(
        data,
        const ['emotionSectionCompleted', 'emotionsCompleted'],
      ) ??
      (_scores(data['emotions'] ?? data['emotionScores']).isNotEmpty
          ? SectionRecordStatus.legacyInferred
          : SectionRecordStatus.notCompleted);

  static SectionRecordStatus resolveStateStatus(Map<String, dynamic> data) =>
      _explicitSectionStatus(data, const ['stateSectionCompleted']) ??
      (_scores(data['stateChanges']).isNotEmpty || _sleepQuality(data) != null
          ? SectionRecordStatus.legacyInferred
          : SectionRecordStatus.notCompleted);

  static SectionRecordStatus? _explicitSectionStatus(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (data[key] == true) return SectionRecordStatus.completed;
      if (data[key] == false) return SectionRecordStatus.notCompleted;
    }
    return null;
  }

  static double? _sleepQuality(Map<String, dynamic> data) {
    final sleep = data['sleep'];
    if (sleep is! Map) return null;
    return _number(sleep['quality'] ?? sleep['sleepQuality']);
  }

  static bool _hasMeaningfulContent(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Iterable) return value.any(_hasMeaningfulContent);
    if (value is Map) {
      return value.entries.any((entry) {
        final item = entry.value;
        if (item is bool) return item;
        if (item is num) return item > 0;
        return _hasMeaningfulContent(item);
      });
    }
    return true;
  }

  static Map<String, double?> _symptoms(dynamic raw) {
    final result = <String, double?>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is String) {
          final name = item.trim();
          if (name.isNotEmpty) result[name] = null;
        } else if (item is Map) {
          final name = (item['name'] ?? item['title'] ?? item['symptom'] ?? '')
              .toString()
              .trim();
          final value = item['score'] ?? item['value'] ?? item['intensity'];
          if (name.isNotEmpty && _isPresent(value, missingMeansPresent: true)) {
            result[name] = _positiveNumber(value);
          }
        }
      }
    } else if (raw is Map) {
      raw.forEach((key, value) {
        final name = key.toString().trim();
        if (name.isNotEmpty && _isPresent(value)) {
          result[name] = _positiveNumber(value);
        }
      });
    }
    return result;
  }

  static bool _isPresent(dynamic raw, {bool missingMeansPresent = false}) {
    if (raw == null) return missingMeansPresent;
    if (raw is bool) return raw;
    if (raw is num) return raw > 0;
    final text = raw.toString().trim().toLowerCase();
    if (text == 'true' || text == 'yes' || text == '有') return true;
    final number = double.tryParse(text);
    return number != null && number > 0;
  }

  static double? _positiveNumber(dynamic raw) {
    final value =
        raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
    return value != null && value > 0 ? value : null;
  }

  static Map<String, double> _scores(dynamic raw) {
    final result = <String, double>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final name = key.toString().trim();
        final score = _number(value);
        if (name.isNotEmpty && score != null) result[name] = score;
      });
    } else if (raw is List) {
      for (final item in raw.whereType<Map>()) {
        final name = (item['name'] ?? item['title'] ?? '').toString().trim();
        final score = _number(item['value'] ?? item['score']);
        if (name.isNotEmpty && score != null) result[name] = score;
      }
    }
    return result;
  }

  static double? _number(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString().trim() ?? '');
  }

  static Map<String, MetricAggregate> _scoreAggregates(
    Map<String, List<double>> values,
    Map<String, int> confirmedDays,
    Map<String, int> inferredDays,
  ) =>
      values.map((name, scores) => MapEntry(
            name,
            MetricAggregate(
              recordedDays: scores.length,
              scoredDays: scores.length,
              presentDays: scores.length,
              occurrenceRate: null,
              averageScore: _average(scores),
              maximumScore: _maximum(scores),
              confirmedRecordedDays: confirmedDays[name] ?? 0,
              inferredRecordedDays: inferredDays[name] ?? 0,
            ),
          ));

  static double? _average(List<double> values) => values.isEmpty
      ? null
      : values.reduce((left, right) => left + right) / values.length;

  static double? _maximum(List<double> values) => values.isEmpty
      ? null
      : values.reduce((left, right) => left > right ? left : right);
}

class CompareMetricResult {
  const CompareMetricResult({
    required this.name,
    required this.kind,
    required this.metricDirection,
    required this.newlyAppeared,
    required this.disappeared,
    required this.direction,
    required this.magnitude,
    required this.occurrenceDirection,
    required this.occurrenceMagnitude,
    required this.severityDirection,
    required this.severityMagnitude,
    required this.symptomPattern,
    required this.beforeOccurrenceRate,
    required this.afterOccurrenceRate,
    required this.beforeAverageScore,
    required this.afterAverageScore,
    required this.beforeMaximumScore,
    required this.afterMaximumScore,
    required this.beforePresentDays,
    required this.afterPresentDays,
    required this.beforeRecordedDays,
    required this.afterRecordedDays,
    required this.confidence,
    required this.dataAdequacy,
    this.beforeEventCount = 0,
    this.afterEventCount = 0,
  });

  final String name;
  final CompareMetricKind kind;
  final MetricDirection metricDirection;
  final bool newlyAppeared;
  final bool disappeared;
  final ChangeDirection direction;
  final ChangeMagnitude magnitude;
  final ChangeDirection occurrenceDirection;
  final ChangeMagnitude occurrenceMagnitude;
  final ChangeDirection severityDirection;
  final ChangeMagnitude severityMagnitude;
  final SymptomChangePattern symptomPattern;
  final double? beforeOccurrenceRate;
  final double? afterOccurrenceRate;
  final double? beforeAverageScore;
  final double? afterAverageScore;
  final double? beforeMaximumScore;
  final double? afterMaximumScore;
  final int beforePresentDays;
  final int afterPresentDays;
  final int beforeRecordedDays;
  final int afterRecordedDays;
  final CompareConfidence confidence;
  final DataAdequacy dataAdequacy;
  final int beforeEventCount;
  final int afterEventCount;

  bool get canCalculate => dataAdequacy != DataAdequacy.unavailable;
  bool get canInterpret =>
      dataAdequacy == DataAdequacy.limited ||
      dataAdequacy == DataAdequacy.adequate;
  bool get sufficientData => canInterpret;
  bool get isPreliminary => dataAdequacy == DataAdequacy.veryLimited;

  bool get needsAttention {
    if (!canInterpret) return false;
    if (kind == CompareMetricKind.symptom) {
      if (newlyAppeared) return afterPresentDays >= 2;
      return symptomPattern == SymptomChangePattern.worsened;
    }
    return metricDirection == MetricDirection.higherIsWorse
        ? direction == ChangeDirection.increased
        : metricDirection == MetricDirection.higherIsBetter &&
            direction == ChangeDirection.decreased;
  }

  bool get possiblyImproved {
    if (!canInterpret || kind == CompareMetricKind.state) return false;
    if (kind == CompareMetricKind.symptom) {
      return symptomPattern == SymptomChangePattern.improved;
    }
    return metricDirection == MetricDirection.higherIsWorse
        ? direction == ChangeDirection.decreased
        : metricDirection == MetricDirection.higherIsBetter &&
            direction == ChangeDirection.increased;
  }
}

class CompareEngine {
  const CompareEngine._();

  static List<CompareMetricResult> compare(
    DailyRecordAggregate before,
    DailyRecordAggregate after, {
    int? beforeAvailableDays,
    int? afterAvailableDays,
    bool hasConcurrentAdjustments = false,
  }) {
    final beforeAvailable = beforeAvailableDays ?? before.effectiveRecordDays;
    final afterAvailable = afterAvailableDays ?? after.effectiveRecordDays;
    final results = <CompareMetricResult>[];
    final symptomKeys = {...before.symptoms.keys, ...after.symptoms.keys};
    for (final name in symptomKeys) {
      final b = before.symptoms[name] ?? _absent(before.symptomRecordedDays);
      final a = after.symptoms[name] ?? _absent(after.symptomRecordedDays);
      final adequacy = dataAdequacyFor(
        before.symptomRecordedDays,
        after.symptomRecordedDays,
      );
      final canCalculate = adequacy != DataAdequacy.unavailable;
      final occurrenceDiff =
          canCalculate && b.occurrenceRate != null && a.occurrenceRate != null
              ? a.occurrenceRate! - b.occurrenceRate!
              : null;
      final occurrenceDirection = _direction(occurrenceDiff);
      final newlyAppeared =
          canCalculate && b.presentDays == 0 && a.presentDays > 0;
      final dayDifference = a.presentDays - b.presentDays;
      final occurrenceMagnitude = _occurrenceMagnitude(
        rateDifference: occurrenceDiff,
        dayDifference: dayDifference,
        newlyAppeared: newlyAppeared,
        afterPresentDays: a.presentDays,
      );
      final severityDiff = b.averageScore != null && a.averageScore != null
          ? a.averageScore! - b.averageScore!
          : null;
      final severityDirection = _direction(severityDiff);
      final severityMagnitude = _scoreMagnitude(
        severityDiff?.abs(),
        minor: CompareThresholds.symptomSeverityMinor,
        meaningful: CompareThresholds.symptomSeverityMeaningful,
        high: CompareThresholds.symptomSeverityHighAttention,
      );
      final pattern = _symptomPattern(
        adequacy: adequacy,
        occurrenceDirection: occurrenceDirection,
        occurrenceMagnitude: occurrenceMagnitude,
        severityDirection: severityDirection,
        severityMagnitude: severityMagnitude,
      );
      final overallMagnitude =
          occurrenceMagnitude.index > severityMagnitude.index
              ? occurrenceMagnitude
              : severityMagnitude;
      results.add(CompareMetricResult(
        name: name,
        kind: CompareMetricKind.symptom,
        metricDirection: MetricDirection.higherIsWorse,
        newlyAppeared: newlyAppeared,
        disappeared: canInterpretAdequacy(adequacy) &&
            b.presentDays > 0 &&
            a.presentDays == 0,
        direction: switch (pattern) {
          SymptomChangePattern.worsened => ChangeDirection.increased,
          SymptomChangePattern.improved => ChangeDirection.decreased,
          SymptomChangePattern.mixed => ChangeDirection.unknown,
          _ => ChangeDirection.stable,
        },
        magnitude: overallMagnitude,
        occurrenceDirection: occurrenceDirection,
        occurrenceMagnitude: occurrenceMagnitude,
        severityDirection: severityDirection,
        severityMagnitude: severityMagnitude,
        symptomPattern: pattern,
        beforeOccurrenceRate: b.occurrenceRate,
        afterOccurrenceRate: a.occurrenceRate,
        beforeAverageScore: b.averageScore,
        afterAverageScore: a.averageScore,
        beforeMaximumScore: b.maximumScore,
        afterMaximumScore: a.maximumScore,
        beforePresentDays: b.presentDays,
        afterPresentDays: a.presentDays,
        beforeRecordedDays: before.symptomRecordedDays,
        afterRecordedDays: after.symptomRecordedDays,
        beforeEventCount: b.eventCount,
        afterEventCount: a.eventCount,
        confidence: calculateCompareConfidence(
          beforeEffectiveDays: before.symptomRecordedDays,
          afterEffectiveDays: after.symptomRecordedDays,
          beforeAvailableDays: beforeAvailable,
          afterAvailableDays: afterAvailable,
          hasConcurrentAdjustments: hasConcurrentAdjustments,
          beforeConfirmedDays:
              before.symptomRecordSummary.confirmedRecordedDays,
          beforeInferredDays: before.symptomRecordSummary.inferredRecordedDays,
          afterConfirmedDays: after.symptomRecordSummary.confirmedRecordedDays,
          afterInferredDays: after.symptomRecordSummary.inferredRecordedDays,
        ),
        dataAdequacy: adequacy,
      ));
    }
    _addScoreResults(
      results,
      before.emotions,
      after.emotions,
      CompareMetricKind.emotion,
      beforeAvailable,
      afterAvailable,
      hasConcurrentAdjustments,
    );
    _addScoreResults(
      results,
      before.states,
      after.states,
      CompareMetricKind.state,
      beforeAvailable,
      afterAvailable,
      hasConcurrentAdjustments,
    );
    results.sort((a, b) => b.magnitude.index.compareTo(a.magnitude.index));
    return results;
  }

  static void _addScoreResults(
    List<CompareMetricResult> output,
    Map<String, MetricAggregate> before,
    Map<String, MetricAggregate> after,
    CompareMetricKind kind,
    int beforeAvailableDays,
    int afterAvailableDays,
    bool hasConcurrentAdjustments,
  ) {
    for (final name in {...before.keys, ...after.keys}) {
      final b = before[name];
      final a = after[name];
      final adequacy = dataAdequacyFor(
        b?.recordedDays ?? 0,
        a?.recordedDays ?? 0,
      );
      final diff = b?.averageScore != null && a?.averageScore != null
          ? a!.averageScore! - b!.averageScore!
          : null;
      final direction = _direction(diff);
      final magnitude = _scoreMagnitude(
        diff?.abs(),
        minor: CompareThresholds.emotionMinor,
        meaningful: CompareThresholds.emotionMeaningful,
        high: CompareThresholds.emotionHighAttention,
      );
      output.add(CompareMetricResult(
        name: name,
        kind: kind,
        metricDirection: kind == CompareMetricKind.state
            ? metricDirectionForState(name)
            : metricDirectionForEmotion(name),
        newlyAppeared: false,
        disappeared: false,
        direction: direction,
        magnitude: magnitude,
        occurrenceDirection: ChangeDirection.unknown,
        occurrenceMagnitude: ChangeMagnitude.stable,
        severityDirection: direction,
        severityMagnitude: magnitude,
        symptomPattern: SymptomChangePattern.stable,
        beforeOccurrenceRate: null,
        afterOccurrenceRate: null,
        beforeAverageScore: b?.averageScore,
        afterAverageScore: a?.averageScore,
        beforeMaximumScore: b?.maximumScore,
        afterMaximumScore: a?.maximumScore,
        beforePresentDays: b?.presentDays ?? 0,
        afterPresentDays: a?.presentDays ?? 0,
        beforeRecordedDays: b?.recordedDays ?? 0,
        afterRecordedDays: a?.recordedDays ?? 0,
        confidence: calculateCompareConfidence(
          beforeEffectiveDays: b?.recordedDays ?? 0,
          afterEffectiveDays: a?.recordedDays ?? 0,
          beforeAvailableDays: beforeAvailableDays,
          afterAvailableDays: afterAvailableDays,
          hasConcurrentAdjustments: hasConcurrentAdjustments,
          beforeConfirmedDays: b?.confirmedRecordedDays ?? 0,
          beforeInferredDays: b?.inferredRecordedDays ?? 0,
          afterConfirmedDays: a?.confirmedRecordedDays ?? 0,
          afterInferredDays: a?.inferredRecordedDays ?? 0,
        ),
        dataAdequacy: adequacy,
      ));
    }
  }

  static MetricDirection metricDirectionForEmotion(String name) {
    final classification = EmotionClassificationSystem.classify(name);
    return switch (classification.valence) {
      AffectValence.positive => MetricDirection.higherIsBetter,
      AffectValence.negative => MetricDirection.higherIsWorse,
      _ => MetricDirection.neutralChange,
    };
  }

  static MetricDirection metricDirectionForState(String name) => name == '睡眠品質'
      ? MetricDirection.higherIsBetter
      : MetricDirection.neutralChange;

  static MetricAggregate _absent(int recordedDays) => MetricAggregate(
        recordedDays: recordedDays,
        scoredDays: 0,
        presentDays: 0,
        occurrenceRate: recordedDays == 0 ? null : 0,
        averageScore: null,
        maximumScore: null,
      );

  static ChangeDirection _direction(double? diff) {
    if (diff == null) return ChangeDirection.unknown;
    if (diff > 0) return ChangeDirection.increased;
    if (diff < 0) return ChangeDirection.decreased;
    return ChangeDirection.stable;
  }

  static ChangeMagnitude _occurrenceMagnitude({
    required double? rateDifference,
    required int dayDifference,
    required bool newlyAppeared,
    required int afterPresentDays,
  }) {
    if (rateDifference == null) return ChangeMagnitude.stable;
    if (newlyAppeared) {
      if (afterPresentDays == 1) return ChangeMagnitude.minor;
      if (afterPresentDays >= 3 && rateDifference.abs() >= 60) {
        return ChangeMagnitude.highAttention;
      }
      return ChangeMagnitude.meaningful;
    }
    if (rateDifference.abs() >= 60 && dayDifference.abs() >= 3) {
      return ChangeMagnitude.highAttention;
    }
    if (rateDifference.abs() >= CompareThresholds.symptomOccurrenceMeaningful &&
        dayDifference.abs() >= 2) {
      return ChangeMagnitude.meaningful;
    }
    if (rateDifference.abs() >= CompareThresholds.symptomOccurrenceMinor ||
        dayDifference != 0) {
      return ChangeMagnitude.minor;
    }
    return ChangeMagnitude.stable;
  }

  static ChangeMagnitude _scoreMagnitude(
    double? value, {
    required double minor,
    required double meaningful,
    required double high,
  }) {
    if (value == null || value < minor) return ChangeMagnitude.stable;
    if (value >= high) return ChangeMagnitude.highAttention;
    if (value >= meaningful) return ChangeMagnitude.meaningful;
    return ChangeMagnitude.minor;
  }

  static SymptomChangePattern _symptomPattern({
    required DataAdequacy adequacy,
    required ChangeDirection occurrenceDirection,
    required ChangeMagnitude occurrenceMagnitude,
    required ChangeDirection severityDirection,
    required ChangeMagnitude severityMagnitude,
  }) {
    if (adequacy == DataAdequacy.unavailable) {
      return SymptomChangePattern.insufficient;
    }
    final occurrenceMeaningful =
        occurrenceMagnitude.index >= ChangeMagnitude.meaningful.index;
    final severityMeaningful =
        severityMagnitude.index >= ChangeMagnitude.meaningful.index;
    final opposite = (occurrenceDirection == ChangeDirection.increased &&
            severityDirection == ChangeDirection.decreased) ||
        (occurrenceDirection == ChangeDirection.decreased &&
            severityDirection == ChangeDirection.increased);
    if (opposite && occurrenceMeaningful && severityMeaningful) {
      return SymptomChangePattern.mixed;
    }
    if ((occurrenceMeaningful &&
            occurrenceDirection == ChangeDirection.increased) ||
        (severityMeaningful &&
            severityDirection == ChangeDirection.increased)) {
      return SymptomChangePattern.worsened;
    }
    if ((occurrenceMeaningful &&
            occurrenceDirection == ChangeDirection.decreased) ||
        (severityMeaningful &&
            severityDirection == ChangeDirection.decreased)) {
      return SymptomChangePattern.improved;
    }
    return SymptomChangePattern.stable;
  }
}

enum CompareConfidence { high, medium, low }

DataAdequacy dataAdequacyFor(int beforeDays, int afterDays) {
  final minimum = beforeDays < afterDays ? beforeDays : afterDays;
  if (minimum <= 0) return DataAdequacy.unavailable;
  if (minimum <= 2) return DataAdequacy.veryLimited;
  if (minimum <= 4) return DataAdequacy.limited;
  return DataAdequacy.adequate;
}

bool canInterpretAdequacy(DataAdequacy value) =>
    value == DataAdequacy.limited || value == DataAdequacy.adequate;

CompareConfidence calculateCompareConfidence({
  required int beforeEffectiveDays,
  required int afterEffectiveDays,
  int? windowDays,
  int? beforeAvailableDays,
  int? afterAvailableDays,
  required bool hasConcurrentAdjustments,
  int beforeConfirmedDays = 0,
  int beforeInferredDays = 0,
  int afterConfirmedDays = 0,
  int afterInferredDays = 0,
}) {
  final beforeAvailable = beforeAvailableDays ?? windowDays ?? 0;
  final afterAvailable = afterAvailableDays ?? windowDays ?? 0;
  final beforeCoverage =
      beforeAvailable == 0 ? 0 : beforeEffectiveDays / beforeAvailable;
  final afterCoverage =
      afterAvailable == 0 ? 0 : afterEffectiveDays / afterAvailable;
  final maximum = beforeEffectiveDays > afterEffectiveDays
      ? beforeEffectiveDays
      : afterEffectiveDays;
  final balanced = maximum > 0 &&
      (beforeEffectiveDays - afterEffectiveDays).abs() <= maximum * 0.5;
  if (!hasConcurrentAdjustments &&
      balanced &&
      beforeEffectiveDays >= 7 &&
      afterEffectiveDays >= 7 &&
      beforeCoverage >= 0.7 &&
      afterCoverage >= 0.7) {
    return adjustConfidenceForLegacyData(
      original: CompareConfidence.high,
      confirmedDays: beforeConfirmedDays + afterConfirmedDays,
      inferredDays: beforeInferredDays + afterInferredDays,
    );
  }
  if (balanced &&
      beforeEffectiveDays >= 4 &&
      afterEffectiveDays >= 4 &&
      beforeCoverage >= 0.5 &&
      afterCoverage >= 0.5) {
    return adjustConfidenceForLegacyData(
      original: CompareConfidence.medium,
      confirmedDays: beforeConfirmedDays + afterConfirmedDays,
      inferredDays: beforeInferredDays + afterInferredDays,
    );
  }
  return CompareConfidence.low;
}

CompareConfidence adjustConfidenceForLegacyData({
  required CompareConfidence original,
  required int confirmedDays,
  required int inferredDays,
}) {
  if (inferredDays <= 0) return original;
  if (inferredDays > confirmedDays) return CompareConfidence.low;
  return switch (original) {
    CompareConfidence.high => CompareConfidence.medium,
    CompareConfidence.medium || CompareConfidence.low => CompareConfidence.low,
  };
}

class CompareConfidenceSummary {
  const CompareConfidenceSummary({
    required this.overall,
    required this.symptom,
    required this.emotion,
    required this.state,
  });

  final CompareConfidence overall;
  final CompareConfidence symptom;
  final CompareConfidence emotion;
  final CompareConfidence state;

  factory CompareConfidenceSummary.calculate({
    required DailyRecordAggregate before,
    required DailyRecordAggregate after,
    required int beforeAvailableDays,
    required int afterAvailableDays,
    required bool hasConcurrentAdjustments,
  }) {
    CompareConfidence value(
      int beforeDays,
      int afterDays, {
      required int beforeConfirmedDays,
      required int beforeInferredDays,
      required int afterConfirmedDays,
      required int afterInferredDays,
    }) =>
        calculateCompareConfidence(
          beforeEffectiveDays: beforeDays,
          afterEffectiveDays: afterDays,
          beforeAvailableDays: beforeAvailableDays,
          afterAvailableDays: afterAvailableDays,
          hasConcurrentAdjustments: hasConcurrentAdjustments,
          beforeConfirmedDays: beforeConfirmedDays,
          beforeInferredDays: beforeInferredDays,
          afterConfirmedDays: afterConfirmedDays,
          afterInferredDays: afterInferredDays,
        );
    final beforeConfirmedTotal =
        before.symptomRecordSummary.confirmedRecordedDays +
            before.emotionRecordSummary.confirmedRecordedDays +
            before.stateRecordSummary.confirmedRecordedDays;
    final beforeInferredTotal =
        before.symptomRecordSummary.inferredRecordedDays +
            before.emotionRecordSummary.inferredRecordedDays +
            before.stateRecordSummary.inferredRecordedDays;
    final afterConfirmedTotal =
        after.symptomRecordSummary.confirmedRecordedDays +
            after.emotionRecordSummary.confirmedRecordedDays +
            after.stateRecordSummary.confirmedRecordedDays;
    final afterInferredTotal = after.symptomRecordSummary.inferredRecordedDays +
        after.emotionRecordSummary.inferredRecordedDays +
        after.stateRecordSummary.inferredRecordedDays;
    return CompareConfidenceSummary(
      overall: value(
        before.effectiveRecordDays,
        after.effectiveRecordDays,
        beforeConfirmedDays: beforeConfirmedTotal,
        beforeInferredDays: beforeInferredTotal,
        afterConfirmedDays: afterConfirmedTotal,
        afterInferredDays: afterInferredTotal,
      ),
      symptom: value(
        before.symptomRecordedDays,
        after.symptomRecordedDays,
        beforeConfirmedDays: before.symptomRecordSummary.confirmedRecordedDays,
        beforeInferredDays: before.symptomRecordSummary.inferredRecordedDays,
        afterConfirmedDays: after.symptomRecordSummary.confirmedRecordedDays,
        afterInferredDays: after.symptomRecordSummary.inferredRecordedDays,
      ),
      emotion: value(
        before.emotionRecordedDays,
        after.emotionRecordedDays,
        beforeConfirmedDays: before.emotionRecordSummary.confirmedRecordedDays,
        beforeInferredDays: before.emotionRecordSummary.inferredRecordedDays,
        afterConfirmedDays: after.emotionRecordSummary.confirmedRecordedDays,
        afterInferredDays: after.emotionRecordSummary.inferredRecordedDays,
      ),
      state: value(
        before.stateRecordedDays,
        after.stateRecordedDays,
        beforeConfirmedDays: before.stateRecordSummary.confirmedRecordedDays,
        beforeInferredDays: before.stateRecordSummary.inferredRecordedDays,
        afterConfirmedDays: after.stateRecordSummary.confirmedRecordedDays,
        afterInferredDays: after.stateRecordSummary.inferredRecordedDays,
      ),
    );
  }
}

class ObservationWindowStatus {
  const ObservationWindowStatus({
    required this.requestedDays,
    required this.elapsedAfterDays,
    required this.remainingDays,
    required this.completed,
    required this.expectedCompletionDate,
  });

  final int requestedDays;
  final int elapsedAfterDays;
  final int remainingDays;
  final bool completed;
  final DateTime expectedCompletionDate;

  factory ObservationWindowStatus.calculate({
    required DateTime eventDate,
    required int requestedDays,
    DateTime? now,
  }) {
    final todayValue = now ?? DateTime.now();
    final today = DateTime(todayValue.year, todayValue.month, todayValue.day);
    final anchor = DateTime(eventDate.year, eventDate.month, eventDate.day);
    final afterStart = anchor.add(const Duration(days: 1));
    final elapsed = today.isBefore(afterStart)
        ? 0
        : today.difference(afterStart).inDays + 1;
    final observed = elapsed.clamp(0, requestedDays);
    return ObservationWindowStatus(
      requestedDays: requestedDays,
      elapsedAfterDays: observed,
      remainingDays: requestedDays - observed,
      completed: observed >= requestedDays,
      expectedCompletionDate: anchor.add(Duration(days: requestedDays)),
    );
  }
}

class MedicationComparisonWindow {
  const MedicationComparisonWindow({
    required this.beforeStart,
    required this.beforeEndExclusive,
    required this.adjustmentDay,
    required this.afterStart,
    required this.afterEndExclusive,
  });

  final DateTime beforeStart;
  final DateTime beforeEndExclusive;
  final DateTime adjustmentDay;
  final DateTime afterStart;
  final DateTime afterEndExclusive;

  factory MedicationComparisonWindow.dateLevel({
    required DateTime adjustmentDate,
    required int days,
  }) {
    final adjustmentDay = DateTime(
      adjustmentDate.year,
      adjustmentDate.month,
      adjustmentDate.day,
    );
    final afterStart = adjustmentDay.add(const Duration(days: 1));
    return MedicationComparisonWindow(
      beforeStart: adjustmentDay.subtract(Duration(days: days)),
      beforeEndExclusive: adjustmentDay,
      adjustmentDay: adjustmentDay,
      afterStart: afterStart,
      afterEndExclusive: afterStart.add(Duration(days: days)),
    );
  }

  factory MedicationComparisonWindow.timestampLevel({
    required DateTime effectiveDateTime,
    required int days,
  }) =>
      MedicationComparisonWindow(
        beforeStart: effectiveDateTime.subtract(Duration(days: days)),
        beforeEndExclusive: effectiveDateTime,
        adjustmentDay: effectiveDateTime,
        afterStart: effectiveDateTime,
        afterEndExclusive: effectiveDateTime.add(Duration(days: days)),
      );
}

class LogicalDailyRecord {
  const LogicalDailyRecord({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
}

List<LogicalDailyRecord> deduplicateDailyRecords(
  Iterable<LogicalDailyRecord> records, {
  void Function(String message)? onSkipped,
}) {
  final groups = <String, List<LogicalDailyRecord>>{};
  for (final record in records) {
    final date = logicalDailyRecordDate(record);
    if (date == null) {
      onSkipped?.call('略過無法解析日期的 dailyRecord：${record.id}');
      continue;
    }
    final key = _ymd(date);
    groups.putIfAbsent(key, () => []).add(record);
  }
  final result = <LogicalDailyRecord>[];
  for (final entry in groups.entries) {
    final values = entry.value..sort(_compareDailyRecordPreference);
    final merged = Map<String, dynamic>.from(values.first.data);
    for (final secondary in values.skip(1)) {
      for (final field in secondary.data.entries) {
        if (!merged.containsKey(field.key) ||
            (_isEmptyValue(merged[field.key]) && !_isEmptyValue(field.value))) {
          merged[field.key] = field.value;
        }
      }
    }
    result.add(LogicalDailyRecord(id: entry.key, data: merged));
  }
  result.sort((a, b) => a.id.compareTo(b.id));
  return result;
}

DateTime? logicalDailyRecordDate(LogicalDailyRecord record) {
  for (final raw in [
    record.data['date'],
    record.id,
    record.data['recordDate'],
    record.data['day'],
    record.data['createdDate'],
  ]) {
    final parsed = _safeDate(raw);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
  }
  return null;
}

int _compareDailyRecordPreference(
  LogicalDailyRecord left,
  LogicalDailyRecord right,
) {
  final updated = _dateRank(right.data['updatedAt'])
      .compareTo(_dateRank(left.data['updatedAt']));
  if (updated != 0) return updated;
  final created = _dateRank(right.data['createdAt'])
      .compareTo(_dateRank(left.data['createdAt']));
  if (created != 0) return created;
  return _completeness(right.data).compareTo(_completeness(left.data));
}

int _dateRank(dynamic value) => _safeDate(value)?.millisecondsSinceEpoch ?? -1;

int _completeness(Map<String, dynamic> data) =>
    data.values.where((value) => !_isEmptyValue(value)).length;

bool _isEmptyValue(dynamic value) =>
    value == null ||
    (value is String && value.trim().isEmpty) ||
    (value is Iterable && value.isEmpty) ||
    (value is Map && value.isEmpty);

DateTime? _safeDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) {
    final text = value.trim().replaceAll('/', '-');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)) return null;
    return DateTime.tryParse(text);
  }
  return null;
}

String _ymd(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
