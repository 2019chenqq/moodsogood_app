import 'package:flutter/foundation.dart';

import 'medication_local_db.dart';
import 'medication_adjustment_service.dart';
import 'medication_subjective_response.dart';
import 'medication_subjective_tracking_cycle.dart';

class MedicationSubjectivePendingResponse {
  const MedicationSubjectivePendingResponse({
    required this.cycle,
    required this.cycles,
    required this.followUpDay,
    required this.calculatedDay,
  });

  final MedicationSubjectiveTrackingCycle cycle;
  final List<MedicationSubjectiveTrackingCycle> cycles;
  final int followUpDay;
  final int calculatedDay;

  String get adjustmentSummary => cycles.length == 1
      ? cycle.adjustmentSummary
      : cycles
          .map((item) => '${item.medicationName}：${item.adjustmentSummary}')
          .join('；');
}

class MedicationSubjectivePendingDetector {
  const MedicationSubjectivePendingDetector._();

  static List<MedicationSubjectivePendingResponse> detect({
    required Iterable<MedicationSubjectiveTrackingCycle> cycles,
    required Iterable<MedicationSubjectiveResponse> responses,
    required DateTime today,
  }) {
    final day = _dateOnly(today);
    final activeByChangeRecord =
        <String, List<MedicationSubjectiveTrackingCycle>>{};
    for (final cycle in cycles.where((item) => item.active)) {
      activeByChangeRecord.putIfAbsent(cycle.episodeId, () => []).add(cycle);
    }
    if (activeByChangeRecord.isEmpty) return const [];

    final latest = activeByChangeRecord.values.reduce((left, right) =>
        _groupChangeDate(left).isAfter(_groupChangeDate(right)) ? left : right)
      ..sort((left, right) => left.medicationId.compareTo(right.medicationId));
    final cycle = latest.first;
    final changeDate = _groupChangeDate(latest);
    final calculatedDay = day.difference(_dateOnly(changeDate)).inDays;
    if (calculatedDay < 0) return const [];
    final dueDays = MedicationSubjectiveTrackingCycle.followUpDays
        .where((followUpDay) => followUpDay <= calculatedDay);
    if (dueDays.isEmpty) return const [];
    final followUpDay = dueDays.last;
    final episodeChangeRecordIds =
        latest.expand((item) => item.changeRecordIds).toSet();
    final isCompleted = responses.any((response) =>
        episodeChangeRecordIds.contains(response.changeRecordId) &&
        response.followUpDay == followUpDay);

    debugPrint(
      '[MedicationSubjective] episodeId=${cycle.episodeId} '
      'latestChangeRecordId=${cycle.changeRecordId} '
      'adjustmentDate=${changeDate.toIso8601String()} '
      'adjustmentTypes=${latest.map((item) => item.changeType.name).join(',')} '
      'trackingFound=true trackingActive=true calculatedDay=$calculatedDay '
      'targetFollowUpDay=$followUpDay responseExists=$isCompleted '
      'pendingShown=${!isCompleted}',
    );

    for (final item in latest) {
      debugPrint(
        '[MedicationSubjective] medicationId=${item.medicationId} '
        'changeRecordId=${item.changeRecordId} '
        'changeDate=${changeDate.toIso8601String()} '
        'today=${day.toIso8601String()} calculatedDay=$calculatedDay '
        'followUpDay=$followUpDay cycleActive=${item.active} '
        'responseCompleted=$isCompleted',
      );
    }
    if (isCompleted) return const [];
    debugPrint(
      '[MedicationSubjective] pendingResponseDetected=true '
      'changeRecordId=${cycle.changeRecordId} followUpDay=$followUpDay',
    );
    return [
      MedicationSubjectivePendingResponse(
        cycle: cycle,
        cycles: List.unmodifiable(latest),
        followUpDay: followUpDay,
        calculatedDay: calculatedDay,
      ),
    ];
  }

  static DateTime _groupChangeDate(
    List<MedicationSubjectiveTrackingCycle> cycles,
  ) =>
      cycles.map((item) => item.changeDate).reduce(
            (left, right) => left.isAfter(right) ? left : right,
          );

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class MedicationSubjectivePendingService {
  MedicationSubjectivePendingService({MedicationLocalDB? localDb})
      : _localDb = localDb ?? MedicationLocalDB();

  final MedicationLocalDB _localDb;

  Future<List<MedicationSubjectivePendingResponse>> load({
    required String uid,
    DateTime? now,
  }) async {
    await MedicationAdjustmentService(localDb: _localDb)
        .repairMissingLatestTrackingCycles(uid: uid);
    final results = await Future.wait([
      _localDb.getSubjectiveTrackingCycles(uid: uid, active: true),
      _localDb.getAllSubjectiveResponses(uid),
    ]);
    return MedicationSubjectivePendingDetector.detect(
      cycles: results[0] as List<MedicationSubjectiveTrackingCycle>,
      responses: results[1] as List<MedicationSubjectiveResponse>,
      today: now ?? DateTime.now(),
    );
  }
}
