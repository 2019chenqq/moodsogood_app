import 'package:firebase_auth/firebase_auth.dart';

import '../../daily/daily_record_helpers.dart';
import '../../meds/medication_compare_repository.dart';
import '../../meds/medication_local_db.dart';
import '../../meds/med_symptom_compare_models.dart';
import '../../meds/medication_subjective_response.dart';
import '../../meds/medication_subjective_summary_builder.dart';
import '../../models/daily_record.dart';
import '../models/follow_up_ai_summary.dart';
import 'follow_up_service.dart';

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
  FollowUpAiDataAggregator({MedicationCompareRepository? medicationRepository})
      : _medicationRepository =
            medicationRepository ?? MedicationCompareRepository();

  final MedicationCompareRepository _medicationRepository;

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
    ]);

    final records = results[0] as List<DailyRecord>;
    final medicationData = results[1] as _MedicationData;
    final appointments = results[2] as List<FollowUpAppointment>;
    final subjectiveResponses = results[3] as List<MedicationSubjectiveResponse>;

    return buildFromData(
      records: records,
      medications: medicationData.medications,
      adjustments: medicationData.adjustments,
      subjectiveResponses: subjectiveResponses,
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
    required List<FollowUpDiscussionTopicInput> discussionTopics,
    required String discussionDetails,
    required String additionalNotes,
    List<FollowUpAppointment> appointments = const [],
    DateTime? currentAppointmentDate,
    DateTime? now,
  }) {
    final todaySource = now ?? DateTime.now();
    final today = DateTime(todaySource.year, todaySource.month, todaySource.day);

    final appointmentDates = appointments.map((item) => _day(item.date)).toList()
      ..sort();
    final upcomingDates =
        appointmentDates.where((date) => !date.isBefore(today)).toList();
    final currentVisitDate = currentAppointmentDate == null
        ? (upcomingDates.isEmpty ? today : upcomingDates.first)
        : _day(currentAppointmentDate);
    final previousDates =
        appointmentDates.where((date) => date.isBefore(currentVisitDate)).toList();
    final previousAppointmentDate =
        previousDates.isEmpty ? null : previousDates.last;

    final eligibleRecordDates = records
        .map((record) => _day(record.date))
        .where((date) => !date.isAfter(today))
        .toList()
      ..sort();
    final start = previousAppointmentDate ??
        (eligibleRecordDates.isEmpty ? today : eligibleRecordDates.first);

    final periodRecords = records.where((record) {
      final date = _day(record.date);
      return !date.isBefore(start) && !date.isAfter(today);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final validDays = periodRecords.where(_hasMeaningfulData).length;

    final limitations = <String>[];
    if (previousAppointmentDate == null) {
      limitations.add(
        eligibleRecordDates.isEmpty
            ? '目前沒有可用的歷史紀錄。'
            : '這次摘要從 ${_date(start)} 開始整理，因為沒有更早的回診日期。',
      );
    }

    final symptomDateSet = <String, Set<String>>{};
    final symptomCount = <String, int>{};
    for (final record in periodRecords) {
      final date = _date(record.date);
      for (final symptom in record.symptoms) {
        final name = symptom.trim();
        if (name.isEmpty) continue;
        symptomCount[name] = (symptomCount[name] ?? 0) + 1;
        symptomDateSet.putIfAbsent(name, () => <String>{}).add(date);
      }
    }
    final symptoms = symptomCount.entries
        .map((entry) => <String, dynamic>{
              'name': entry.key,
              'occurrenceDays': entry.value,
              'dates': (symptomDateSet[entry.key] ?? const <String>{}).toList()
                ..sort(),
              'averageSeverity': null,
            })
        .toList()
      ..sort((a, b) {
        final byDays =
            (b['occurrenceDays'] as int).compareTo(a['occurrenceDays'] as int);
        return byDays != 0
            ? byDays
            : a['name'].toString().compareTo(b['name'].toString());
      });

    if (symptoms.isEmpty) {
      limitations.add('這段期間沒有可整理的症狀資料。');
    }

    final sleepDurations =
        _points(periodRecords, (record) => record.sleep.durationHours);
    final sleepQuality =
        _points(periodRecords, (record) => record.sleep.quality?.toDouble());
    final sleepConditionDates = <String, Set<String>>{};
    var napDays = 0;
    var napCount = 0;
    var napMinutes = 0;
    for (final record in periodRecords) {
      final date = _date(record.date);
      for (final rawFlag in record.sleep.flags) {
        final code = _canonicalSleepFlag(rawFlag);
        if (code != null) {
          sleepConditionDates.putIfAbsent(code, () => <String>{}).add(date);
        }
      }
      if (record.sleep.nightAwakenings.isNotEmpty) {
        sleepConditionDates
            .putIfAbsent('interrupted', () => <String>{})
            .add(date);
      }
      if (record.sleep.naps.isNotEmpty) {
        napDays++;
        napCount += record.sleep.naps.length;
        napMinutes += record.sleep.naps
            .fold<int>(0, (sum, nap) => sum + nap.durationMinutes);
      }
    }

    final body = <Map<String, dynamic>>[];
    void addBody(String name, String unit, double? Function(DailyRecord) read) {
      final values = periodRecords
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

    addBody('體重', 'kg', (record) => record.bodyMeasurement?.weightKg);
    addBody('體脂率', '%', (record) => record.bodyMeasurement?.bodyFatPercent);
    addBody('腰圍', 'cm', (record) => record.bodyMeasurement?.waistCm);

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
              'startDate': _dateValue(medication['startDate']),
            })
        .toList();

    final medicationTimeline = adjustments
        .where((event) {
          final date = _day(event.date);
          return !date.isBefore(start) && !date.isAfter(today);
        })
        .map((event) => <String, dynamic>{
              'date': _date(event.date),
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
        .toList();

    final medicationSubjectiveReports =
        MedicationSubjectiveSummaryBuilder.toAiInput(subjectiveResponses);
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
        mood: _trend(_points(periodRecords, (record) {
          final value = record.overallMood;
          if (value == null) return null;
          return record.moodScale == 10 ? value / 2 : value;
        })),
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
        energy: _stateTrend(periodRecords, 'energy_change'),
        appetite: _stateTrend(periodRecords, 'appetite_change'),
        activity: _stateTrend(periodRecords, 'activity_change'),
      ),
      sleep: {
        'durationHours': _metricSummary(
          sleepDurations,
          trend: sleepDurations,
        ),
        'quality': _metricSummary(sleepQuality),
        'conditions': _sleepConditionLabels.entries
            .where((entry) => sleepConditionDates[entry.key]?.isNotEmpty == true)
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
      highFrequencySymptoms: symptoms.take(5).toList(),
      bodyMeasurements: body,
      currentMedications: currentMedications,
      medicationTimeline: medicationTimeline,
      medicationSubjectiveReports: medicationSubjectiveReports,
      dataLimitations: limitations,
    );
  }

  bool _hasMeaningfulData(DailyRecord record) =>
      record.overallMood != null ||
      record.emotions.any((emotion) => emotion.value != null) ||
      record.stateChanges.isNotEmpty ||
      record.symptoms.isNotEmpty ||
      record.sleep.durationHours != null ||
      record.sleep.quality != null ||
      record.sleep.flags.isNotEmpty ||
      record.sleep.naps.isNotEmpty ||
      record.bodyMeasurement?.hasData == true;

  MetricTrendInput _stateTrend(List<DailyRecord> records, String id) =>
      _trend(_points(records, (record) => record.stateChanges[id]?.toDouble()));

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
      'minimum': values.isEmpty ? null : _round(values.reduce((a, b) => a < b ? a : b)),
      'maximum': values.isEmpty ? null : _round(values.reduce((a, b) => a > b ? a : b)),
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

  static String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

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

  static DateTime? _dateValue(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
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
}

class _MedicationData {
  const _MedicationData({
    required this.medications,
    required this.adjustments,
  });

  final List<Map<String, dynamic>> medications;
  final List<MedicationAdjustmentEvent> adjustments;
}
