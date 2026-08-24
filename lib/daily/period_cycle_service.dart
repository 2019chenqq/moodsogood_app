import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/period_cycle.dart';
import '../utils/health_data_encryption_service.dart';

abstract class PeriodCycleStore {
  Future<List<PeriodCycle>> getCycles(String userId);
  Future<String> createCycle(String userId, DateTime startDate);
  Future<void> deleteCycle(String userId, String cycleId);
  Future<void> updateCycle(
    String userId,
    PeriodCycle cycle, {
    DateTime? startDate,
    DateTime? endDate,
  });
}

/// Read-only source for legacy menstrual data stored on DailyRecord documents.
abstract class LegacyPeriodRecordStore {
  Future<List<LegacyPeriodRecord>> getRecords(String userId);
}

abstract class PeriodCycleMigrationWriter {
  Future<bool> createCycleIfAbsent(String userId, PeriodCycle cycle);
  Future<bool> closeMigratedCycleIfOpen(
    String userId,
    PeriodCycle cycle,
  );
  Future<void> recordMigrationStatus(
    String userId, {
    required int version,
    required int created,
    required int updated,
    required int skipped,
    required int failed,
  });
}

class LegacyPeriodRecord {
  const LegacyPeriodRecord({
    required this.id,
    required this.date,
    required this.isPeriod,
    this.periodStartId,
    this.periodEndId,
  });

  final String id;
  final DateTime date;
  final bool isPeriod;
  final String? periodStartId;
  final String? periodEndId;
}

class FirestoreLegacyPeriodRecordStore implements LegacyPeriodRecordStore {
  FirestoreLegacyPeriodRecordStore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<List<LegacyPeriodRecord>> getRecords(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('dailyRecords')
        .get();
    final records = <LegacyPeriodRecord>[];
    for (final document in snapshot.docs) {
      try {
        final data = await HealthDataEncryptionService.decryptData(
          document.data(),
        );
        final periodData = data['periodData'] is Map
            ? (data['periodData'] as Map).cast<String, dynamic>()
            : const <String, dynamic>{};
        final date = _legacyDate(data['date']);
        if (date == null) continue;
        records.add(LegacyPeriodRecord(
          id: document.id,
          date: date,
          isPeriod: data['isPeriod'] == true || periodData['isPeriod'] == true,
          periodStartId:
              _legacyId(data['periodStartId'] ?? periodData['periodStartId']),
          periodEndId:
              _legacyId(data['periodEndId'] ?? periodData['periodEndId']),
        ));
      } catch (_) {
        // A malformed legacy document must not hide other usable history.
      }
    }
    return records;
  }

  static DateTime? _legacyDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _legacyId(dynamic value) {
    final id = value?.toString().trim();
    return id == null || id.isEmpty ? null : id;
  }
}

class FirestorePeriodCycleStore
    implements PeriodCycleStore, PeriodCycleMigrationWriter {
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
  Future<void> deleteCycle(String userId, String cycleId) =>
      _cycles(userId).doc(cycleId).delete();

  @override
  Future<bool> createCycleIfAbsent(
    String userId,
    PeriodCycle cycle,
  ) =>
      HealthDataEncryptionService.createEncryptedIfAbsent(
        _cycles(userId).doc(cycle.id),
        cycle.toFirestore(),
      );

  @override
  Future<bool> closeMigratedCycleIfOpen(
    String userId,
    PeriodCycle cycle,
  ) async {
    if (!cycle.id.startsWith('legacy-v1-') || cycle.endDate == null) {
      return false;
    }
    final reference = _cycles(userId).doc(cycle.id);
    final snapshot = await reference.get();
    if (!snapshot.exists || snapshot.data() == null) return false;
    final currentData = await HealthDataEncryptionService.decryptData(
      snapshot.data()!,
    );
    final current = PeriodCycle.fromData(cycle.id, currentData);
    if (current.endDate != null ||
        _day(current.startDate) != _day(cycle.startDate)) {
      return false;
    }
    await updateCycle(userId, current, endDate: cycle.endDate);
    return true;
  }

  @override
  Future<void> recordMigrationStatus(
    String userId, {
    required int version,
    required int created,
    required int updated,
    required int skipped,
    required int failed,
  }) =>
      _firestore.collection('users').doc(userId).set({
        'periodCycleMigrationVersion': version,
        'periodCycleMigrationUpdatedAt': FieldValue.serverTimestamp(),
        'periodCycleMigrationCreated': created,
        'periodCycleMigrationUpdated': updated,
        'periodCycleMigrationSkipped': skipped,
        'periodCycleMigrationFailed': failed,
      }, SetOptions(merge: true));

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

class PeriodCycleMigrationResult {
  const PeriodCycleMigrationResult({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.failed,
  });

  final int created;
  final int updated;
  final int skipped;
  final int failed;
}

class PeriodCycleService {
  PeriodCycleService({
    PeriodCycleStore? store,
    LegacyPeriodRecordStore? legacyStore,
    PeriodCycleMigrationWriter? migrationWriter,
  })  : _store = store ?? FirestorePeriodCycleStore(),
        _legacyStore = legacyStore,
        _migrationWriter = migrationWriter;

  final PeriodCycleStore _store;
  final LegacyPeriodRecordStore? _legacyStore;
  final PeriodCycleMigrationWriter? _migrationWriter;

  static const periodCycleMigrationVersion = 1;

  Future<List<PeriodCycle>> getCycles(String userId) =>
      _store.getCycles(userId);

  /// Combines canonical PeriodCycle documents with read-only legacy history.
  /// Canonical cycles win whenever their date ranges overlap legacy output.
  Future<List<PeriodCycle>> getUnifiedCycles(String userId) async {
    List<PeriodCycle> canonical = const [];
    List<LegacyPeriodRecord> legacyRecords = const [];

    try {
      canonical = await _store.getCycles(userId);
    } catch (_) {
      // Legacy remains a valid fallback when the canonical source is unavailable.
    }
    try {
      final legacyStore = _legacyStore ?? FirestoreLegacyPeriodRecordStore();
      legacyRecords = await legacyStore.getRecords(userId);
    } catch (_) {
      // Canonical data remains usable when the legacy source is unavailable.
    }

    final result = <PeriodCycle>[...canonical];
    for (final legacy in legacyRecordsToCycles(legacyRecords)) {
      if (!canonical.any((cycle) => _overlaps(cycle, legacy))) {
        result.add(legacy);
      }
    }
    result.sort((a, b) => a.startDate.compareTo(b.startDate));
    return result;
  }

  /// Restores legacy start/end spans and contiguous explicitly-marked days.
  /// Missing referenced dates are skipped rather than inferred.
  static List<PeriodCycle> legacyRecordsToCycles(
    Iterable<LegacyPeriodRecord> records,
  ) {
    final sorted = records.toList()..sort((a, b) => a.date.compareTo(b.date));
    final byId = <String, LegacyPeriodRecord>{
      for (final record in sorted) record.id: record,
    };
    final cycles = <PeriodCycle>[];
    final consumedDays = <DateTime>{};

    for (final record in sorted) {
      final startId = record.periodStartId;
      final endId = record.periodEndId;
      if (startId == null || endId == null) continue;
      final start = byId[startId];
      final end = byId[endId];
      if (start == null || end == null) continue;
      final startDay = _day(start.date);
      final endDay = _day(end.date);
      if (endDay.isBefore(startDay)) continue;
      cycles.add(PeriodCycle(
        id: 'legacy:$startId:$endId',
        startDate: startDay,
        endDate: endDay,
      ));
      for (var day = startDay;
          !day.isAfter(endDay);
          day = day.add(const Duration(days: 1))) {
        consumedDays.add(day);
      }
    }

    final markedDays = sorted
        .where((record) => record.isPeriod)
        .map((record) => _day(record.date))
        .where((day) => !consumedDays.contains(day))
        .toSet()
        .toList()
      ..sort();
    for (var index = 0; index < markedDays.length;) {
      final start = markedDays[index];
      var end = start;
      index++;
      while (index < markedDays.length &&
          markedDays[index].difference(end).inDays == 1) {
        end = markedDays[index++];
      }
      cycles.add(PeriodCycle(
        id: 'legacy:${_dateKey(start)}:${_dateKey(end)}',
        startDate: start,
        endDate: end,
      ));
    }
    cycles.sort((a, b) => a.startDate.compareTo(b.startDate));
    return cycles;
  }

  /// Explicit phase-2 entry point. It never changes legacy DailyRecord data.
  Future<PeriodCycleMigrationResult> migrateLegacyCycles(String userId) async {
    final legacyStore = _legacyStore ?? FirestoreLegacyPeriodRecordStore();
    final writer = _migrationWriter ??
        (_store is PeriodCycleMigrationWriter
            ? _store as PeriodCycleMigrationWriter
            : null);
    if (writer == null) {
      throw StateError('PeriodCycle migration requires a migration writer.');
    }

    final existing = await _store.getCycles(userId);
    final legacyRecords = await legacyStore.getRecords(userId);
    final candidates = legacyRecordsToMigrationCycles(legacyRecords);
    var created = 0;
    var updated = 0;
    final referencedStarts = legacyRecords
        .map((record) => record.periodStartId)
        .whereType<String>()
        .toSet();
    var skipped = referencedStarts.length - candidates.length;
    var failed = 0;
    final known = <PeriodCycle>[...existing];

    for (final candidate in candidates) {
      final sameDocument =
          known.where((cycle) => cycle.id == candidate.id).firstOrNull;
      if (sameDocument != null &&
          sameDocument.endDate == null &&
          candidate.endDate != null) {
        try {
          if (await writer.closeMigratedCycleIfOpen(userId, candidate)) {
            updated++;
            known
              ..remove(sameDocument)
              ..add(candidate);
          } else {
            skipped++;
          }
        } catch (error) {
          failed++;
          debugPrint(
            '[PeriodCycleMigration] Failed to close ${candidate.id}: $error',
          );
        }
        continue;
      }
      if (known.any((cycle) => _overlaps(cycle, candidate))) {
        skipped++;
        continue;
      }
      try {
        final didCreate = await writer.createCycleIfAbsent(userId, candidate);
        if (didCreate) {
          created++;
          known.add(candidate);
        } else {
          skipped++;
        }
      } catch (error) {
        failed++;
        debugPrint(
          '[PeriodCycleMigration] Failed ${candidate.id}: $error',
        );
      }
    }

    try {
      await writer.recordMigrationStatus(
        userId,
        version: periodCycleMigrationVersion,
        created: created,
        updated: updated,
        skipped: skipped,
        failed: failed,
      );
    } catch (error) {
      debugPrint('[PeriodCycleMigration] Status write failed: $error');
    }
    return PeriodCycleMigrationResult(
      created: created,
      updated: updated,
      skipped: skipped,
      failed: failed,
    );
  }

  /// Strict migration parser: unlike the unified reader, unlinked marked days
  /// are not enough to prove a complete cycle and are intentionally skipped.
  static List<PeriodCycle> legacyRecordsToMigrationCycles(
    Iterable<LegacyPeriodRecord> records,
  ) {
    final sorted = records.toList()..sort((a, b) => a.date.compareTo(b.date));
    final byId = <String, LegacyPeriodRecord>{
      for (final record in sorted) record.id: record,
    };
    final startIds = sorted
        .map((record) => record.periodStartId)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final cycles = <PeriodCycle>[];

    for (final startId in startIds) {
      final start = byId[startId];
      if (start == null || !start.isPeriod) {
        debugPrint('[PeriodCycleMigration] Skip invalid start $startId');
        continue;
      }
      final linked =
          sorted.where((record) => record.periodStartId == startId).toList();
      final endIds = linked
          .map((record) => record.periodEndId)
          .whereType<String>()
          .toSet();
      if (endIds.length > 1) {
        debugPrint('[PeriodCycleMigration] Skip conflicting ends $startId');
        continue;
      }

      DateTime? endDate;
      if (endIds.isNotEmpty) {
        final end = byId[endIds.single];
        if (end == null || _day(end.date).isBefore(_day(start.date))) {
          debugPrint('[PeriodCycleMigration] Skip invalid end $startId');
          continue;
        }
        endDate = _day(end.date);
      } else {
        final hasContradiction = linked.any((record) => !record.isPeriod);
        if (hasContradiction) {
          debugPrint('[PeriodCycleMigration] Skip ambiguous open $startId');
          continue;
        }
        final markedDays = sorted
            .where((record) => record.isPeriod)
            .map((record) => _day(record.date))
            .toSet();
        var lastMarkedDay = _day(start.date);
        while (markedDays.contains(
          lastMarkedDay.add(const Duration(days: 1)),
        )) {
          lastMarkedDay = lastMarkedDay.add(const Duration(days: 1));
        }
        final hasLaterLegacyRecord = sorted.any(
          (record) => _day(record.date).isAfter(lastMarkedDay),
        );
        if (hasLaterLegacyRecord) {
          endDate = lastMarkedDay;
        }
      }

      cycles.add(PeriodCycle(
        id: _migrationCycleId(startId, start.date),
        startDate: _day(start.date),
        endDate: endDate,
      ));
    }
    cycles.sort((a, b) => a.startDate.compareTo(b.startDate));
    return cycles;
  }

  Future<PeriodCycle?> cycleForDate(String userId, DateTime date) async {
    final day = _day(date);
    final cycles = await getUnifiedCycles(userId);
    for (final cycle in cycles.reversed) {
      if (_contains(cycle, day)) return cycle;
    }
    return null;
  }

  /// Cancels the canonical open cycle that is active on [date].
  /// Legacy fallback records are intentionally never deleted here.
  Future<bool> cancelActiveCycle(String userId, DateTime date) async {
    final day = _day(date);
    final cycles = await _store.getCycles(userId);
    final active = _activeCycle(cycles, day);
    if (active == null) return false;
    await _store.deleteCycle(userId, active.id);
    return true;
  }

  /// Deletes the canonical cycle covering [date], whether completed or open.
  /// In-memory legacy fallback cycles are never mutated or deleted.
  Future<bool> cancelCycleForDate(String userId, DateTime date) async {
    final day = _day(date);
    final cycles = await _store.getCycles(userId);
    final covering = _coveringCycle(cycles, day);
    if (covering == null) return false;
    await _store.deleteCycle(userId, covering.id);
    return true;
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

  static bool _overlaps(PeriodCycle a, PeriodCycle b) {
    final aStart = _day(a.startDate);
    final bStart = _day(b.startDate);
    final aEnd = a.endDate == null ? null : _day(a.endDate!);
    final bEnd = b.endDate == null ? null : _day(b.endDate!);
    return (bEnd == null || !aStart.isAfter(bEnd)) &&
        (aEnd == null || !bStart.isAfter(aEnd));
  }

  static String _migrationCycleId(String startId, DateTime startDate) {
    var checksum = 2166136261;
    for (final unit in startId.codeUnits) {
      checksum = ((checksum ^ unit) * 16777619) & 0xFFFFFFFF;
    }
    return 'legacy-v1-${_dateKey(_day(startDate))}-'
        '${checksum.toRadixString(16).padLeft(8, '0')}';
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
