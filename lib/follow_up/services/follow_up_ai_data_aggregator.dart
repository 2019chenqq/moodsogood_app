import 'package:firebase_auth/firebase_auth.dart';

import '../../daily/daily_record_helpers.dart';
import '../../daily/daily_check_in_service.dart';
import '../../daily/health_event_repository.dart';
import '../../daily/services/health_event_cooccurrence_service.dart';
import '../../daily/unified_body_measurement_repository.dart';
import '../../daily/unified_sleep_repository.dart';
import '../../meds/medication_compare_repository.dart';
import '../../meds/medication_local_db.dart';
import '../../meds/med_symptom_compare_models.dart';
import '../../meds/medication_subjective_response.dart';
import '../../meds/medication_subjective_summary_builder.dart';
import '../../models/daily_record.dart';
import '../../models/daily_check_in.dart';
import '../../models/health_event.dart';
import '../../models/sleep_record.dart';
import '../../sleep_insights/models/sleep_insight_models.dart';
import '../../sleep_insights/services/sleep_analysis_service.dart';
import '../models/follow_up_ai_summary.dart';
import 'follow_up_service.dart';
import 'follow_up_health_summary_builder.dart';

const _sleepConditionLabels = <String, String>{
  'good': '良好',
  'ok': '尚可',
  'earlyWake': '早醒',
  'dreams': '多夢',
  'lightSleep': '淺眠',
  'fragmented': '睡眠片段',
  'insufficient': '睡眠不足',
  'initInsomnia': '入睡困難',
  'interrupted': '夜間醒來',
  'nocturia': '夜尿',
};

class FollowUpAiDataAggregator {
  FollowUpAiDataAggregator({
    MedicationCompareRepository? medicationRepository,
    UnifiedSleepRepository? sleepRepository,
    UnifiedBodyMeasurementRepository? bodyMeasurementRepository,
  })  : _medicationRepository =
            medicationRepository ?? MedicationCompareRepository(),
        _sleepRepository = sleepRepository,
        _bodyMeasurementRepository = bodyMeasurementRepository;

  final MedicationCompareRepository _medicationRepository;
  final UnifiedSleepRepository? _sleepRepository;
  final UnifiedBodyMeasurementRepository? _bodyMeasurementRepository;

  Future<FollowUpAiV1Input> build({
    required List<FollowUpDiscussionTopicInput> discussionTopics,
    required String discussionDetails,
    required String additionalNotes,
    DateTime? currentAppointmentDate,
    DateTime? now,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('請先登入後再使用 AI 回診整理。');

    final results = await Future.wait<dynamic>([
      loadAllRecords(uid),
      _loadMedicationData(uid),
      FollowUpService.getAppointments(),
      MedicationLocalDB().getAllSubjectiveResponses(uid),
      HealthEventRepository().getAll(userId: uid),
      DailyCheckInService().getAll(),
    ]);

    final records = results[0] as List<DailyRecord>;
    final medicationData = results[1] as _MedicationData;
    final appointments = results[2] as List<FollowUpAppointment>;
    final subjectiveResponses =
        results[3] as List<MedicationSubjectiveResponse>;
    final healthEvents = results[4] as List<HealthEvent>;
    final dailyCheckIns = results[5] as List<DailyCheckIn>;
    final todaySource = now ?? DateTime.now();
    final today = _day(todaySource);
    final previousAppointment = _previousAppointmentDate(
      appointments,
      currentAppointmentDate ?? today,
    );
    // With no previous appointment, query the compatible repositories far
    // enough back to discover the actual earliest standalone record.
    final repositoryStart = previousAppointment ?? DateTime(2000);
    final unifiedResults = await Future.wait<dynamic>([
      (_sleepRepository ?? UnifiedSleepRepository()).getByDateRange(
        userId: uid,
        start: repositoryStart,
        end: today,
      ),
      (_bodyMeasurementRepository ?? UnifiedBodyMeasurementRepository())
          .getByDateRange(
        userId: uid,
        start: repositoryStart,
        end: today,
      ),
    ]);

    return buildFromData(
      records: records,
      medications: medicationData.medications,
      adjustments: medicationData.adjustments,
      subjectiveResponses: subjectiveResponses,
      healthEvents: healthEvents,
      dailyCheckIns: dailyCheckIns,
      sleepRecords: unifiedResults[0] as List<UnifiedSleepRecord>,
      bodyMeasurementRecords: unifiedResults[1] as List<UnifiedBodyMeasurement>,
      appointments: appointments,
      discussionTopics: discussionTopics,
      discussionDetails: discussionDetails,
      additionalNotes: additionalNotes,
      currentAppointmentDate: currentAppointmentDate,
      now: now,
    );
  }

  Future<_MedicationData> _loadMedicationData(String uid) async {
    await _medicationRepository.syncAll(uid);
    return _MedicationData(
      medications: await _medicationRepository.getMedications(uid),
      adjustments: await _medicationRepository.getAdjustmentEvents(uid),
    );
  }

  FollowUpAiV1Input buildFromData({
    required List<DailyRecord> records,
    List<Map<String, dynamic>>? rawRecords,
    required List<Map<String, dynamic>> medications,
    required List<MedicationAdjustmentEvent> adjustments,
    Iterable<MedicationSubjectiveResponse> subjectiveResponses = const [],
    Iterable<HealthEvent> healthEvents = const [],
    Iterable<DailyCheckIn> dailyCheckIns = const [],
    Iterable<UnifiedSleepRecord>? sleepRecords,
    Iterable<UnifiedBodyMeasurement>? bodyMeasurementRecords,
    required List<FollowUpDiscussionTopicInput> discussionTopics,
    required String discussionDetails,
    required String additionalNotes,
    List<FollowUpAppointment> appointments = const [],
    DateTime? currentAppointmentDate,
    DateTime? now,
  }) {
    final todaySource = now ?? DateTime.now();
    final today =
        DateTime(todaySource.year, todaySource.month, todaySource.day);

    final appointmentDates =
        appointments.map((item) => _day(item.date)).toList()..sort();
    final upcomingDates =
        appointmentDates.where((date) => !date.isBefore(today)).toList();
    final currentVisitDate = currentAppointmentDate == null
        ? (upcomingDates.isEmpty ? today : upcomingDates.first)
        : _day(currentAppointmentDate);
    final previousDates = appointmentDates
        .where((date) => date.isBefore(currentVisitDate))
        .toList();
    final previousAppointmentDate =
        previousDates.isEmpty ? null : previousDates.last;

    final eligibleRecordDates = <DateTime>[
      ...records.map((record) => _day(record.date)),
      ...healthEvents.map((event) => _day(event.timestamp)),
      ...dailyCheckIns.map((checkIn) => _day(checkIn.date)),
      ...subjectiveResponses.map((response) => _day(response.recordedAt)),
      ...?sleepRecords?.map((item) => _day(item.record.date)),
      ...?bodyMeasurementRecords?.map((item) => _day(item.date)),
    ].where((date) => !date.isAfter(today)).toList()
      ..sort();
    final start = previousAppointmentDate ??
        (eligibleRecordDates.isEmpty ? today : eligibleRecordDates.first);

    final periodRecords = records.where((record) {
      final date = _day(record.date);
      return !date.isBefore(start) && !date.isAfter(today);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final endExclusive = today.add(const Duration(days: 1));
    final healthSummary = const FollowUpHealthSummaryBuilder().build(
      dailyRecords: periodRecords,
      healthEvents: healthEvents,
      dailyCheckIns: dailyCheckIns,
      start: start,
      endExclusive: endExclusive,
    );
    final validDays = healthSummary.recordedDays;

    final limitations = <String>[];
    if (previousAppointmentDate == null) {
      limitations.add(
        eligibleRecordDates.isEmpty
            ? '目前沒有可用的歷史紀錄。'
            : '這次摘要從 ${_date(start)} 開始整理，因為沒有更早的回診日期。',
      );
    }

    final symptoms = healthSummary.symptoms;

    if (symptoms.isEmpty) {
      limitations.add('這段期間沒有可整理的症狀資料。');
    } else {
      limitations.add('症狀紀錄僅代表有紀錄的日期與事件，不代表診斷或因果。');
    }

    final resolvedSleepRecords = sleepRecords ??
        UnifiedSleepRepository.resolve(
          legacy: periodRecords.map(
            (record) => SleepRecord.fromSleepData(record.date, record.sleep),
          ),
        );
    final periodSleepRecords = resolvedSleepRecords
        .where((item) =>
            !_day(item.record.date).isBefore(start) &&
            !_day(item.record.date).isAfter(today))
        .toList(growable: false);
    final sleepInsight = const SleepAnalysisService().analyze(
      records: UnifiedSleepRepository.overlayForInsights(
        dailyRecords: periodRecords,
        sleepRecords: periodSleepRecords,
      ),
      startDate: start,
      endDate: today,
      period: SleepInsightPeriod.all,
    );
    final sleepDurations = sleepInsight.points
        .where((point) => point.nightMinutes != null)
        .map((point) => DatedMetricValue(
              date: point.date,
              value: _round(point.nightMinutes! / 60),
            ))
        .toList(growable: false);
    final sleepQuality = sleepInsight.points
        .where((point) => point.quality != null)
        .map((point) => DatedMetricValue(
              date: point.date,
              value: point.quality!.toDouble(),
            ))
        .toList(growable: false);
    final sleepConditionDates = <String, Set<String>>{};
    var napDays = 0;
    var napCount = 0;
    var napMinutes = 0;
    for (final point
        in sleepInsight.points.where((item) => item.hasSleepRecord)) {
      final date = _date(point.date);
      for (final rawFlag in point.flags) {
        final code = _canonicalSleepFlag(rawFlag);
        if (code != null) {
          sleepConditionDates.putIfAbsent(code, () => <String>{}).add(date);
        }
      }
      if (point.hasNightWakeRecord) {
        sleepConditionDates
            .putIfAbsent('interrupted', () => <String>{})
            .add(date);
      }
      if (point.napCount > 0) {
        napDays++;
        napCount += point.napCount;
        napMinutes += point.napMinutes;
      }
    }

    final body = <Map<String, dynamic>>[];
    final resolvedBodyMeasurements =
        UnifiedBodyMeasurementRepository.selectDailyTrend(
      bodyMeasurementRecords ??
          periodRecords
              .where((record) => record.bodyMeasurement?.hasData == true)
              .map(UnifiedBodyMeasurementRepository.fromLegacy),
    ).where((item) => !item.date.isBefore(start) && !item.date.isAfter(today));
    void addBody(
      String name,
      String unit,
      double? Function(UnifiedBodyMeasurement) read,
    ) {
      final values = resolvedBodyMeasurements
          .map((record) => MapEntry(record.date, read(record)))
          .where((entry) => entry.value != null)
          .toList();
      if (values.isEmpty) return;
      body.add({
        'name': name,
        'unit': unit,
        'startDate': _date(values.first.key),
        'startValue': values.first.value,
        'latestDate': _date(values.last.key),
        'latestValue': values.last.value,
        'change': _round(values.last.value! - values.first.value!),
      });
    }

    addBody('體重', 'kg', (record) => record.measurement.weightKg);
    addBody('體脂率', '%', (record) => record.measurement.bodyFatPercent);
    addBody('腰圍', 'cm', (record) => record.measurement.waistCm);

    final currentMedications = medications
        .where((medication) => medication['isActive'] != false)
        .map((medication) => <String, dynamic>{
              'name': _text(medication['name'], fallback: '未知藥物'),
              'dose': _number(medication['dose']) ??
                  _multiply(
                    _number(medication['dosePerUnit']),
                    _number(medication['pillCount']),
                  ),
              'unit': _text(medication['unit']),
              'times': _strings(medication['times']),
              'startDate': _dateString(medication['startDate']),
            })
        .toList();

    final medicationTimeline = adjustments
        .where((event) {
          final date = _day(event.effectiveDateTime);
          return !date.isBefore(start) && !date.isAfter(today);
        })
        .map((event) => <String, dynamic>{
              'changeRecordId': event.adjustmentId,
              'medicationId': event.medDocId,
              'date': _date(event.effectiveDateTime),
              'medicationName': event.medName,
              'type': event.type,
              'beforeDose': event.resolvedOldTotalDose,
              'beforeUnit': event.oldUnit,
              'afterDose': event.resolvedNewTotalDose,
              'afterUnit': event.newUnit,
              'beforeTimes': event.oldTimes,
              'afterTimes': event.newTimes,
              'recordOrigin': event.origin.name,
            })
        .toList()
      ..sort((a, b) =>
          (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));

    final periodSubjectiveResponses = subjectiveResponses.where((response) =>
        !response.recordedAt.isBefore(start) &&
        response.recordedAt.isBefore(endExclusive));
    final medicationSubjectiveReports =
        MedicationSubjectiveSummaryBuilder.toAiInput(periodSubjectiveResponses)
            .map((group) {
      final changeRecordId = group['changeRecordId']?.toString() ?? '';
      final medicationId = group['medicationId']?.toString() ?? '';
      final sameChange = adjustments
          .where((event) => event.adjustmentId == changeRecordId)
          .toList();
      final concurrentNames = sameChange
          .where((event) => event.medDocId != medicationId)
          .map((event) => event.medName.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      return <String, dynamic>{
        ...group,
        if (concurrentNames.isNotEmpty)
          'concurrentMedicationAdjustments': concurrentNames,
        if (group['pairingStatus'] == 'legacy_unassigned' &&
            sameChange.length > 1)
          'pairingStatus': 'unsafe_to_assign_to_one_medication',
      };
    }).toList(growable: false);
    if (medicationSubjectiveReports.isNotEmpty) {
      limitations.add(
        '已整理 ${medicationSubjectiveReports.length} 組用藥後主觀回報。',
      );
    }

    return FollowUpAiV1Input(
      statistics: FollowUpStatistics(
        periodStart: start,
        periodEnd: today,
        validRecordDays: validDays,
        previousAppointmentDate: previousAppointmentDate,
        currentAppointmentDate: currentVisitDate,
        periodBasis: previousAppointmentDate == null
            ? 'earliestRecordToCurrentVisit'
            : 'previousAppointmentToCurrentVisit',
      ),
      discussionTopics: discussionTopics,
      discussionDetails: discussionDetails.trim(),
      additionalNotes: additionalNotes.trim(),
      wellbeingTrends: WellbeingTrendsInput(
        mood: _trend(_dailySummaryPoints(
          healthSummary.dailySummary['mood5Point'],
        )),
        anxiety: _trend(_points(periodRecords, (record) {
          final values = record.emotions
              .where((emotion) => _containsAny(emotion.name, const [
                    '焦慮',
                    '緊張',
                    '不安',
                  ]))
              .map((emotion) => emotion.value)
              .whereType<int>()
              .toList();
          if (values.isEmpty) return null;
          return values.reduce((a, b) => a + b) / values.length;
        })),
        energy: _trend(_stateSummaryPoints(
          healthSummary.dailySummary,
          'energy_change',
        )),
        appetite: _trend(_stateSummaryPoints(
          healthSummary.dailySummary,
          'appetite_change',
        )),
        activity: _trend(_stateSummaryPoints(
          healthSummary.dailySummary,
          'activity_change',
        )),
      ),
      sleep: {
        'durationHours': _metricSummary(
          sleepDurations,
          trend: sleepDurations,
        ),
        'quality': _metricSummary(sleepQuality),
        'conditions': _sleepConditionLabels.entries
            .where(
                (entry) => sleepConditionDates[entry.key]?.isNotEmpty == true)
            .map((entry) => {
                  'code': entry.key,
                  'label': entry.value,
                  'occurrenceDays': sleepConditionDates[entry.key]!.length,
                  'dates': sleepConditionDates[entry.key]!.toList()..sort(),
                })
            .toList(),
        'sleepOnsetDifficulty':
            _eventSummary(sleepConditionDates['initInsomnia'] ?? const {}),
        'earlyAwakening':
            _eventSummary(sleepConditionDates['earlyWake'] ?? const {}),
        'nightInterruption':
            _eventSummary(sleepConditionDates['interrupted'] ?? const {}),
        'naps': {
          'days': napDays,
          'count': napCount,
          'totalMinutes': napMinutes,
        },
      },
      highFrequencySymptoms: _cooccurrenceItems(
        healthEvents
            .where((event) =>
                !event.timestamp.isBefore(start) &&
                event.timestamp.isBefore(endExclusive))
            .toList(growable: false),
      ),
      bodyMeasurements: body,
      currentMedications: currentMedications,
      medicationTimeline: medicationTimeline,
      medicationSubjectiveReports: medicationSubjectiveReports,
      dailyHealthSummary: healthSummary.dailySummary,
      coOccurrenceSummary: healthSummary.coOccurrences,
      representativeHealthEvents: healthSummary.representativeEvents,
      dataLimitations: limitations,
    );
  }

  List<DatedMetricValue> _dailySummaryPoints(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) {
          final date = DateTime.tryParse(item['date']?.toString() ?? '');
          final value = _number(item['mainValue']);
          return date == null || value == null
              ? null
              : DatedMetricValue(date: date, value: value);
        })
        .whereType<DatedMetricValue>()
        .toList();
  }

  List<DatedMetricValue> _stateSummaryPoints(
    Map<String, dynamic> summary,
    String key,
  ) {
    final states = summary['stateDailyValues'];
    return states is Map
        ? _dailySummaryPoints((states[key] as List?)
            ?.map(
              (item) =>
                  item is Map ? {...item, 'mainValue': item['value']} : item,
            )
            .toList())
        : const [];
  }

  List<DatedMetricValue> _points(
    List<DailyRecord> records,
    double? Function(DailyRecord record) read,
  ) =>
      records
          .map((record) {
            final value = read(record);
            return value == null
                ? null
                : DatedMetricValue(date: record.date, value: _round(value));
          })
          .whereType<DatedMetricValue>()
          .toList();

  MetricTrendInput _trend(List<DatedMetricValue> points) {
    if (points.length < 3) {
      return MetricTrendInput(
        dailyValues: points,
        direction: TrendDirection.insufficientData,
      );
    }
    final half = points.length ~/ 2;
    final first = _average(points.take(half).map((point) => point.value));
    final last = _average(points.skip(half).map((point) => point.value));
    final difference = last - first;
    final range =
        points.map((point) => point.value).reduce((a, b) => a > b ? a : b) -
            points.map((point) => point.value).reduce((a, b) => a < b ? a : b);
    final direction = range >= 2.5 && difference.abs() < .5
        ? TrendDirection.fluctuating
        : difference >= .5
            ? TrendDirection.increasing
            : difference <= -.5
                ? TrendDirection.decreasing
                : TrendDirection.stable;
    return MetricTrendInput(dailyValues: points, direction: direction);
  }

  Map<String, dynamic> _metricSummary(
    List<DatedMetricValue> points, {
    List<DatedMetricValue>? trend,
  }) {
    final values = points.map((point) => point.value).toList();
    final summary = <String, dynamic>{
      'recordedDays': points.length,
      'average': values.isEmpty ? null : _round(_average(values)),
      'minimum': values.isEmpty
          ? null
          : _round(values.reduce((a, b) => a < b ? a : b)),
      'maximum': values.isEmpty
          ? null
          : _round(values.reduce((a, b) => a > b ? a : b)),
      'dailyTrend': (trend ?? points)
          .map((point) => {'date': _date(point.date), 'value': point.value})
          .toList(),
    };
    final change = _sleepTrendChange(summary['dailyTrend'] as List);
    if (change != null) {
      summary['comparison'] = {'change': change};
    }
    return summary;
  }

  Map<String, dynamic> _eventSummary(Set<String> dates) => {
        'occurrenceDays': dates.length,
        'dates': dates.toList()..sort(),
      };

  static bool _containsAny(String value, List<String> needles) =>
      needles.any((needle) => value.contains(needle));

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime? _previousAppointmentDate(
    Iterable<FollowUpAppointment> appointments,
    DateTime currentVisitDate,
  ) {
    final current = _day(currentVisitDate);
    final previous = appointments
        .map((item) => _day(item.date))
        .where((date) => date.isBefore(current))
        .toList()
      ..sort();
    return previous.isEmpty ? null : previous.last;
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static double? _multiply(double? a, double? b) {
    if (a == null || b == null) return null;
    return a * b;
  }

  static List<String> _strings(dynamic value) => value is Iterable
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];

  static String? _dateString(dynamic value) {
    final date = value is DateTime
        ? value
        : value is String
            ? DateTime.tryParse(value)
            : null;
    return date == null ? null : _date(date);
  }

  static double _round(double value) => (value * 100).round() / 100;

  static double _average(Iterable<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  static num? _sleepTrendChange(List<dynamic> trend) {
    final values = trend
        .map((point) => point is Map ? point['value'] : null)
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
    if (values.length < 3) return null;
    final half = values.length ~/ 2;
    if (half == 0) return null;
    double average(Iterable<double> items) =>
        items.reduce((a, b) => a + b) / items.length;
    final earlier = average(values.take(half));
    final recent = average(values.skip(half));
    return _round(recent - earlier);
  }

  static String? _canonicalSleepFlag(String rawFlag) {
    final flag = rawFlag.trim();
    return _sleepConditionLabels.containsKey(flag) ? flag : null;
  }

  static List<Map<String, dynamic>> _cooccurrenceItems(
    List<HealthEvent> events,
  ) {
    final result = HealthEventCooccurrenceService.instance.analyze(events);
    final pairs = <Map<String, dynamic>>[
      ...result.symptomPairs.map((pair) => <String, dynamic>{
            'items': [pair.itemA, pair.itemB],
            'itemTypes': const ['symptom', 'symptom'],
            'coOccurrenceCount': pair.coOccurrenceCount,
            'averageValues': {
              pair.itemA: result.symptomAvgSeverity[pair.itemA],
              pair.itemB: result.symptomAvgSeverity[pair.itemB],
            },
          }),
      ...result.emotionSymptomPairs.map((pair) => <String, dynamic>{
            'items': [pair.itemA, pair.itemB],
            'itemTypes': const ['emotion', 'symptom'],
            'coOccurrenceCount': pair.coOccurrenceCount,
            'averageValues': {
              pair.itemA: result.emotionAvgIntensity[pair.itemA],
              pair.itemB: result.symptomAvgSeverity[pair.itemB],
            },
          }),
    ]..sort((a, b) => (b['coOccurrenceCount'] as int)
        .compareTo(a['coOccurrenceCount'] as int));
    final repeated = pairs
        .where((item) => (item['coOccurrenceCount'] as int) >= 2)
        .toList(growable: false);
    return (repeated.isNotEmpty ? repeated : pairs.take(3))
        .take(5)
        .toList(growable: false);
  }
}

class _MedicationData {
  const _MedicationData({
    required this.medications,
    required this.adjustments,
  });

  final List<Map<String, dynamic>> medications;
  final List<MedicationAdjustmentEvent> adjustments;
}
