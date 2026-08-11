import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/period_cycle.dart';
import '../utils/health_data_encryption_service.dart';

abstract class PeriodCycleStore {
  Future<List<PeriodCycle>> getCycles(String userId);
  Future<String> createCycle(String userId, DateTime startDate);
  Future<void> updateCycle(
    String userId,
    PeriodCycle cycle, {
    DateTime? startDate,
    DateTime? endDate,
  });
}

class FirestorePeriodCycleStore implements PeriodCycleStore {
  FirestorePeriodCycleStore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _cycles(String userId) =>
      _firestore.collection('users').doc(userId).collection('periodCycles');

  @override
  Future<List<PeriodCycle>> getCycles(String userId) async {
    final documents = await HealthDataEncryptionService.getEncrypted(
      _cycles(userId).orderBy('startDate'),
    );
    return documents
        .map((document) => PeriodCycle.fromData(document.id, document.data))
        .toList(growable: false);
  }

  @override
  Future<String> createCycle(String userId, DateTime startDate) async {
    final reference = _cycles(userId).doc();
    await HealthDataEncryptionService.setEncrypted(
      reference,
      PeriodCycle(id: reference.id, startDate: _day(startDate)).toFirestore(),
      merge: false,
    );
    return reference.id;
  }

  @override
  Future<void> updateCycle(
    String userId,
    PeriodCycle cycle, {
    DateTime? startDate,
    DateTime? endDate,
  }) =>
      HealthDataEncryptionService.setEncrypted(
        _cycles(userId).doc(cycle.id),
        PeriodCycle(
          id: cycle.id,
          startDate: _day(startDate ?? cycle.startDate),
          endDate: endDate == null ? cycle.endDate : _day(endDate),
        ).toFirestore(),
      );

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

enum PeriodQuickAction { start, ongoing, end }

enum PeriodQuickActionResult {
  started,
  alreadyOngoing,
  ended,
  noActiveCycle,
}

class PeriodCycleService {
  PeriodCycleService({PeriodCycleStore? store})
      : _store = store ?? FirestorePeriodCycleStore();

  final PeriodCycleStore _store;

  Future<List<PeriodCycle>> getCycles(String userId) =>
      _store.getCycles(userId);

  Future<PeriodCycle?> cycleForDate(String userId, DateTime date) async {
    final day = _day(date);
    final cycles = await _store.getCycles(userId);
    for (final cycle in cycles.reversed) {
      if (_contains(cycle, day)) return cycle;
    }
    return null;
  }

  Future<PeriodQuickActionResult> apply({
    required String userId,
    required DateTime date,
    required PeriodQuickAction action,
  }) async {
    final day = _day(date);
    final cycles = await _store.getCycles(userId);
    final active = _activeCycle(cycles, day);
    final covering = _coveringCycle(cycles, day);

    switch (action) {
      case PeriodQuickAction.start:
        if (covering != null && _day(covering.startDate) == day) {
          return PeriodQuickActionResult.started;
        }
        if (active != null && active.startDate.isBefore(day)) {
          await _store.updateCycle(
            userId,
            active,
            endDate: day.subtract(const Duration(days: 1)),
          );
        }
        await _store.createCycle(userId, day);
        return PeriodQuickActionResult.started;
      case PeriodQuickAction.ongoing:
        return covering != null || active != null
            ? PeriodQuickActionResult.alreadyOngoing
            : PeriodQuickActionResult.noActiveCycle;
      case PeriodQuickAction.end:
        final target = active ?? covering;
        if (target == null || day.isBefore(_day(target.startDate))) {
          return PeriodQuickActionResult.noActiveCycle;
        }
        await _store.updateCycle(userId, target, endDate: day);
        return PeriodQuickActionResult.ended;
    }
  }

  static PeriodCycle? _activeCycle(
    Iterable<PeriodCycle> cycles,
    DateTime day,
  ) {
    final values = cycles
        .where((cycle) =>
            cycle.endDate == null && !_day(cycle.startDate).isAfter(day))
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    return values.isEmpty ? null : values.first;
  }

  static PeriodCycle? _coveringCycle(
    Iterable<PeriodCycle> cycles,
    DateTime day,
  ) {
    final values = cycles.where((cycle) => _contains(cycle, day)).toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    return values.isEmpty ? null : values.first;
  }

  static bool _contains(PeriodCycle cycle, DateTime day) {
    final start = _day(cycle.startDate);
    final end = cycle.endDate == null ? null : _day(cycle.endDate!);
    return !day.isBefore(start) && (end == null || !day.isAfter(end));
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
