import 'package:firebase_auth/firebase_auth.dart';

import '../daily/daily_record_helpers.dart';
import '../meds/med_symptom_compare_models.dart';
import '../meds/medication_compare_repository.dart';
import '../models/daily_record.dart';
import '../models/follow_up_ai_summary.dart';
import 'follow_up_service.dart';

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
    ]);
    final medicationData = results[1] as _MedicationData;
    return buildFromData(
      records: results[0] as List<DailyRecord>,
      medications: medicationData.medications,
      adjustments: medicationData.adjustments,
      appointments: results[2] as List<FollowUpAppointment>,
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
    required List<Map<String, dynamic>> medications,
    required List<MedicationAdjustmentEvent> adjustments,
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
    final validDays = periodRecords
        .where(_hasMeaningfulData)
        .map((record) => _date(record.date))
        .toSet()
        .length;
    final limitations = <String>[];
    if (previousAppointmentDate == null) {
      limitations.add(
        eligibleRecordDates.isEmpty
            ? '尚無上次回診日期及可用紀錄，本次無法建立回診區間趨勢。'
            : '找不到上一次回診日期，本次從最早可用紀錄 ${_date(start)} 開始整理。',
      );
    }

    final symptomDates = <String, Set<String>>{};
    for (final record in periodRecords) {
      for (final symptom
          in record.symptoms.map((item) => item.trim()).toSet()) {
        if (symptom.isEmpty) continue;
        symptomDates
            .putIfAbsent(symptom, () => <String>{})
            .add(_date(record.date));
      }
    }
    final symptoms = symptomDates.entries
        .map((entry) => <String, dynamic>{
              'name': entry.key,
              'occurrenceDays': entry.value.length,
              'dates': entry.value.toList()..sort(),
              'averageSeverity': null,
            })
        .toList()
      ..sort((a, b) =>
          (b['occurrenceDays'] as int).compareTo(a['occurrenceDays'] as int));
    if (symptoms.isNotEmpty) {
      limitations.add('目前每日症狀紀錄未包含程度分數，無法計算平均程度。');
    }

    final sleepDurations =
        _points(periodRecords, (record) => record.sleep.durationHours);
    final sleepQuality = _points(
      periodRecords,
      (record) => record.sleep.quality?.toDouble(),
    );
    final sleepFlags = <String, List<String>>{
      'sleepOnsetDifficulty': [],
      'earlyAwakening': [],
      'nightInterruption': [],
    };
    var napDays = 0;
    var napCount = 0;
    var napMinutes = 0;
    for (final record in periodRecords) {
      final joined = record.sleep.flags.join('、');
      if (_containsAny(joined, const ['initInsomnia', '入睡困難', '難入睡'])) {
        sleepFlags['sleepOnsetDifficulty']!.add(_date(record.date));
      }
      if (_containsAny(joined, const ['earlyWake', '早醒', '提早醒'])) {
        sleepFlags['earlyAwakening']!.add(_date(record.date));
      }
      if (record.sleep.nightAwakenings.isNotEmpty ||
          _containsAny(joined, const ['interrupted', '中斷', '夜醒', '半夜醒'])) {
        sleepFlags['nightInterruption']!.add(_date(record.date));
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
              'name': _text(medication['name'], fallback: '未命名藥物'),
              'dose': _number(medication['dose']) ??
                  _multiply(_number(medication['dosePerUnit']),
                      _number(medication['pillCount'])),
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

    if (validDays < 7) limitations.add('本次回診區間只有 $validDays 天有效紀錄，趨勢代表性有限。');
    if (sleepDurations.isEmpty) limitations.add('統計期間內沒有可計算睡眠時數的紀錄。');
    if (body.isEmpty) limitations.add('統計期間內沒有體重、體脂率或腰圍紀錄。');
    if (medicationTimeline.isEmpty) limitations.add('統計期間內沒有調藥紀錄。');

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
              .where((emotion) =>
                  _containsAny(emotion.name, const ['焦慮', '緊張', '不安']))
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
        'durationHours': _metricSummary(sleepDurations),
        'quality': _metricSummary(sleepQuality),
        'sleepOnsetDifficulty':
            _eventSummary(sleepFlags['sleepOnsetDifficulty']!),
        'earlyAwakening': _eventSummary(sleepFlags['earlyAwakening']!),
        'nightInterruption': _eventSummary(sleepFlags['nightInterruption']!),
        'naps': {
          'days': napDays,
          'count': napCount,
          'totalMinutes': napMinutes,
        },
      },
      highFrequencySymptoms: symptoms.take(8).toList(),
      bodyMeasurements: body,
      currentMedications: currentMedications,
      medicationTimeline: medicationTimeline,
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
          dailyValues: points, direction: TrendDirection.insufficientData);
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
        : difference >= .4
            ? TrendDirection.increasing
            : difference <= -.4
                ? TrendDirection.decreasing
                : TrendDirection.stable;
    return MetricTrendInput(dailyValues: points, direction: direction);
  }

  Map<String, dynamic> _metricSummary(List<DatedMetricValue> points) => {
        'recordedDays': points.length,
        'average': points.isEmpty
            ? null
            : _round(_average(points.map((point) => point.value))),
        'minimum': points.isEmpty
            ? null
            : points
                .map((point) => point.value)
                .reduce((a, b) => a < b ? a : b),
        'maximum': points.isEmpty
            ? null
            : points
                .map((point) => point.value)
                .reduce((a, b) => a > b ? a : b),
        'dailyTrend': points.map((point) => point.toJson()).toList(),
        'direction': _trend(points).direction.name,
      };

  Map<String, dynamic> _eventSummary(List<String> dates) =>
      {'occurrenceDays': dates.length, 'dates': dates};

  double _average(Iterable<double> values) {
    final list = values.toList();
    return list.reduce((a, b) => a + b) / list.length;
  }

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  static double _round(double value) => (value * 100).round() / 100;
  static bool _containsAny(String value, List<String> terms) =>
      terms.any(value.contains);
  static double? _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  static double? _multiply(double? a, double? b) =>
      a == null || b == null ? null : _round(a * b);
  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static List<String> _strings(dynamic value) => value is List
      ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];
  static String? _dateValue(dynamic value) {
    final parsed =
        value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? null : _date(parsed);
  }
}

class _MedicationData {
  const _MedicationData({required this.medications, required this.adjustments});

  final List<Map<String, dynamic>> medications;
  final List<MedicationAdjustmentEvent> adjustments;
}
