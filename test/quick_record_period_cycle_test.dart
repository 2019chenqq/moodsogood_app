import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/period_cycle_service.dart';
import 'package:moodsogood_app/daily/quick_record_editor.dart';
import 'package:moodsogood_app/models/period_cycle.dart';
import 'package:moodsogood_app/models/health_event.dart';

void main() {
  test('period start creates one existing PeriodCycle entry', () async {
    final store = _MemoryPeriodCycleStore();
    final service = PeriodCycleService(store: store);

    expect(
      await service.apply(
        userId: 'u',
        date: DateTime(2026, 8, 11, 15),
        action: PeriodQuickAction.start,
      ),
      PeriodQuickActionResult.started,
    );
    expect(store.cycles, hasLength(1));
    expect(store.cycles.single.startDate, DateTime(2026, 8, 11));
    expect(store.collectionName, 'periodCycles');
  });

  test('ongoing action never creates a duplicate cycle', () async {
    final store = _MemoryPeriodCycleStore()
      ..cycles.add(PeriodCycle(id: 'p1', startDate: DateTime(2026, 8, 10)));
    final service = PeriodCycleService(store: store);

    final result = await service.apply(
      userId: 'u',
      date: DateTime(2026, 8, 11),
      action: PeriodQuickAction.ongoing,
    );

    expect(result, PeriodQuickActionResult.alreadyOngoing);
    expect(store.cycles, hasLength(1));
  });

  test('end action updates the active cycle end date', () async {
    final store = _MemoryPeriodCycleStore()
      ..cycles.add(PeriodCycle(id: 'p1', startDate: DateTime(2026, 8, 10)));
    final service = PeriodCycleService(store: store);

    final result = await service.apply(
      userId: 'u',
      date: DateTime(2026, 8, 13, 20),
      action: PeriodQuickAction.end,
    );

    expect(result, PeriodQuickActionResult.ended);
    expect(store.cycles.single.endDate, DateTime(2026, 8, 13));
  });

  test('end without an active cycle is safe and creates nothing', () async {
    final store = _MemoryPeriodCycleStore();
    final service = PeriodCycleService(store: store);

    final result = await service.apply(
      userId: 'u',
      date: DateTime(2026, 8, 13),
      action: PeriodQuickAction.end,
    );

    expect(result, PeriodQuickActionResult.noActiveCycle);
    expect(store.cycles, isEmpty);
  });

  test('reloading reads a cycle changed by the calendar source', () async {
    final store = _MemoryPeriodCycleStore();
    final service = PeriodCycleService(store: store);
    expect(await service.cycleForDate('u', DateTime(2026, 8, 11)), isNull);

    store.cycles.add(PeriodCycle(
      id: 'calendar-edit',
      startDate: DateTime(2026, 8, 10),
      endDate: DateTime(2026, 8, 12),
    ));

    expect(
      (await service.cycleForDate('u', DateTime(2026, 8, 11)))?.id,
      'calendar-edit',
    );
  });

  group('simplified QuickRecord period presentation', () {
    test('no active cycle shows the start action and guidance', () {
      expect(QuickRecordEditor.periodActionLabel(null), '＋ 月經開始');
      expect(
        QuickRecordEditor.periodStatusLabel(null, DateTime(2026, 8, 21)),
        '月經開始與結束各記錄一次即可，經期中系統會自動辨識。',
      );
    });

    test('starting changes presentation to Day 1', () async {
      final store = _MemoryPeriodCycleStore();
      final service = PeriodCycleService(store: store);
      await service.apply(
        userId: 'u',
        date: DateTime(2026, 8, 21, 18),
        action: PeriodQuickAction.start,
      );
      final cycle = await service.cycleForDate('u', DateTime(2026, 8, 21));
      expect(
        QuickRecordEditor.periodStatusLabel(cycle, DateTime(2026, 8, 21)),
        '經期中 · Day 1',
      );
      expect(QuickRecordEditor.periodActionLabel(cycle), '結束經期');
    });

    test('the next selected QuickRecord date automatically shows Day 2', () {
      final cycle = PeriodCycle(
        id: 'active',
        startDate: DateTime(2026, 8, 21),
      );
      expect(
        QuickRecordEditor.periodStatusLabel(cycle, DateTime(2026, 8, 22, 9)),
        '經期中 · Day 2',
      );
    });

    test('ongoing is no longer an available presentation action', () {
      final cycle = PeriodCycle(
        id: 'active',
        startDate: DateTime(2026, 8, 21),
      );
      expect(
        [
          QuickRecordEditor.periodActionLabel(null),
          QuickRecordEditor.periodActionLabel(cycle),
        ],
        isNot(contains('月經進行中')),
      );
    });

    test('Day N uses the selected date rather than today', () {
      final cycle = PeriodCycle(
        id: 'active',
        startDate: DateTime(2026, 8, 21, 23),
      );
      expect(
        QuickRecordEditor.periodDayNumber(cycle, DateTime(2026, 8, 23, 1)),
        3,
      );
    });

    test('ending sets endDate and returns to the start action', () async {
      final store = _MemoryPeriodCycleStore()
        ..cycles.add(PeriodCycle(
          id: 'active',
          startDate: DateTime(2026, 8, 21),
        ));
      final service = PeriodCycleService(store: store);
      await service.apply(
        userId: 'u',
        date: DateTime(2026, 8, 23, 20),
        action: PeriodQuickAction.end,
      );
      expect(store.cycles.single.endDate, DateTime(2026, 8, 23));
      expect(
        QuickRecordEditor.periodActionLabel(store.cycles.single),
        '＋ 月經開始',
      );
    });

    test('deleting an ordinary QuickRecord cannot mutate PeriodCycle state',
        () {
      final store = _MemoryPeriodCycleStore()
        ..cycles.add(PeriodCycle(
          id: 'active',
          startDate: DateTime(2026, 8, 21),
        ));
      final events = <HealthEvent>[
        HealthEvent(id: 'event', timestamp: DateTime(2026, 8, 22)),
      ]..removeWhere((event) => event.id == 'event');
      expect(events, isEmpty);
      expect(store.cycles, hasLength(1));
      expect(store.writeCount, 0);
    });

    test('HealthEvent schema has no period fields', () {
      final map = HealthEvent(
        id: 'event',
        timestamp: DateTime(2026, 8, 22),
      ).toMap();
      expect(map, isNot(contains('period')));
      expect(map, isNot(contains('isPeriod')));
      expect(map, isNot(contains('periodData')));
    });
  });

  group('unified period cycle reader', () {
    test('ongoing cycle contains every day from start onward', () {
      final cycle = PeriodCycle(
        id: 'ongoing',
        startDate: DateTime(2026, 8, 21),
      );
      for (var day = 21; day <= 24; day++) {
        expect(cycle.containsDate(DateTime(2026, 8, day)), isTrue);
      }
      expect(cycle.containsDate(DateTime(2026, 8, 20)), isFalse);
    });

    test('cycleForDate uses legacy fallback when canonical is empty', () async {
      final legacy = _MemoryLegacyStore()
        ..records.addAll([
          _legacy('a', 21, isPeriod: true),
          _legacy('b', 22, isPeriod: true),
          _legacy('c', 23, isPeriod: true),
          _legacy('d', 24, isPeriod: true),
        ]);
      final cycle = await PeriodCycleService(
        store: _MemoryPeriodCycleStore(),
        legacyStore: legacy,
      ).cycleForDate('u', DateTime(2026, 8, 24));
      expect(cycle, isNotNull);
      expect(cycle!.startDate, DateTime(2026, 8, 21));
      expect(cycle.endDate, DateTime(2026, 8, 24));
    });

    test('only canonical cycles are returned', () async {
      final canonical = _MemoryPeriodCycleStore()
        ..cycles.add(PeriodCycle(
          id: 'new',
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 5),
        ));
      final service = PeriodCycleService(
        store: canonical,
        legacyStore: _MemoryLegacyStore(),
      );
      expect((await service.getUnifiedCycles('u')).single.id, 'new');
    });

    test('only legacy marked days become a PeriodCycle', () async {
      final legacy = _MemoryLegacyStore()
        ..records.addAll([
          _legacy('a', 1, isPeriod: true),
          _legacy('b', 2, isPeriod: true),
          _legacy('c', 3, isPeriod: true),
        ]);
      final cycles = await PeriodCycleService(
        store: _MemoryPeriodCycleStore(),
        legacyStore: legacy,
      ).getUnifiedCycles('u');
      expect(cycles, hasLength(1));
      expect(cycles.single.startDate, DateTime(2026, 8, 1));
      expect(cycles.single.endDate, DateTime(2026, 8, 3));
    });

    test('overlapping canonical and legacy cycles prefer canonical', () async {
      final canonical = _MemoryPeriodCycleStore()
        ..cycles.add(PeriodCycle(
          id: 'new',
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 5),
        ));
      final legacy = _MemoryLegacyStore()
        ..records.addAll([
          _legacy('a', 1, isPeriod: true),
          _legacy('b', 2, isPeriod: true),
        ]);
      final cycles = await PeriodCycleService(
        store: canonical,
        legacyStore: legacy,
      ).getUnifiedCycles('u');
      expect(cycles.map((cycle) => cycle.id), ['new']);
    });

    test('different legacy history supplements canonical cycles in order',
        () async {
      final canonical = _MemoryPeriodCycleStore()
        ..cycles.add(PeriodCycle(id: 'new', startDate: DateTime(2026, 8, 10)));
      final legacy = _MemoryLegacyStore()
        ..records.addAll([
          _legacy('a', 1, isPeriod: true),
          _legacy('b', 2, isPeriod: true),
        ]);
      final cycles = await PeriodCycleService(
        store: canonical,
        legacyStore: legacy,
      ).getUnifiedCycles('u');
      expect(cycles, hasLength(2));
      expect(cycles.first.startDate, DateTime(2026, 8, 1));
      expect(cycles.last.id, 'new');
    });

    test('canonical null end date remains ongoing', () async {
      final canonical = _MemoryPeriodCycleStore()
        ..cycles
            .add(PeriodCycle(id: 'ongoing', startDate: DateTime(2026, 8, 1)));
      final cycle = (await PeriodCycleService(
        store: canonical,
        legacyStore: _MemoryLegacyStore(),
      ).getUnifiedCycles('u'))
          .single;
      expect(cycle.endDate, isNull);
    });

    test('one malformed legacy reference does not hide valid history', () {
      final cycles = PeriodCycleService.legacyRecordsToCycles([
        _legacy('bad', 1, startId: 'missing', endId: 'also-missing'),
        _legacy('valid-a', 5, isPeriod: true),
        _legacy('valid-b', 6, isPeriod: true),
      ]);
      expect(cycles, hasLength(1));
      expect(cycles.single.startDate, DateTime(2026, 8, 5));
      expect(cycles.single.endDate, DateTime(2026, 8, 6));
    });

    test('unified read performs no write or delete', () async {
      final canonical = _MemoryPeriodCycleStore();
      final legacy = _MemoryLegacyStore();
      await PeriodCycleService(
        store: canonical,
        legacyStore: legacy,
      ).getUnifiedCycles('u');
      expect(canonical.writeCount, 0);
      expect(legacy.writeCount, 0);
    });
  });

  group('legacy period cycle migration', () {
    test('8/1 through 8/5 creates one canonical cycle', () async {
      final store = _MemoryPeriodCycleStore();
      final result = await _migrationService(store, _completedLegacy())
          .migrateLegacyCycles('u');
      expect(result.created, 1);
      expect(store.cycles.single.startDate, DateTime(2026, 8, 1));
      expect(store.cycles.single.endDate, DateTime(2026, 8, 5));
      expect(
          store.statusVersion, PeriodCycleService.periodCycleMigrationVersion);
    });

    test('rerunning migration does not create a duplicate', () async {
      final store = _MemoryPeriodCycleStore();
      final service = _migrationService(store, _completedLegacy());
      await service.migrateLegacyCycles('u');
      final second = await service.migrateLegacyCycles('u');
      expect(second.created, 0);
      expect(second.skipped, 1);
      expect(store.cycles, hasLength(1));
    });

    test('an equivalent canonical cycle is skipped', () async {
      final store = _MemoryPeriodCycleStore()
        ..cycles.add(PeriodCycle(
          id: 'canonical',
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 5),
        ));
      final result = await _migrationService(store, _completedLegacy())
          .migrateLegacyCycles('u');
      expect(result.skipped, 1);
      expect(store.cycles.single.id, 'canonical');
    });

    test('a different canonical cycle is not overwritten', () async {
      final store = _MemoryPeriodCycleStore()
        ..cycles.add(PeriodCycle(
          id: 'other',
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 7, 4),
        ));
      await _migrationService(store, _completedLegacy())
          .migrateLegacyCycles('u');
      expect(store.cycles, hasLength(2));
      expect(store.cycles.first.id, 'other');
    });

    test('an explicit open legacy cycle keeps a null end date', () async {
      final store = _MemoryPeriodCycleStore();
      final legacy = [
        _legacy('open', 10, isPeriod: true, startId: 'open'),
        _legacy('open-2', 11, isPeriod: true, startId: 'open'),
      ];
      await _migrationService(store, legacy).migrateLegacyCycles('u');
      expect(store.cycles.single.endDate, isNull);
    });

    test('incomplete or contradictory legacy data is skipped', () async {
      final store = _MemoryPeriodCycleStore();
      final legacy = [
        _legacy('missing-start', 1, isPeriod: true, startId: 'absent'),
        _legacy('conflict', 10, isPeriod: true, startId: 'conflict'),
        _legacy('conflict-off', 11, startId: 'conflict'),
      ];
      final result =
          await _migrationService(store, legacy).migrateLegacyCycles('u');
      expect(result.created, 0);
      expect(store.cycles, isEmpty);
    });

    test('one failed cycle does not stop another cycle', () async {
      final store = _MemoryPeriodCycleStore()..failNextCreate = true;
      final legacy = [
        ..._completedLegacy(),
        _legacy('second', 10, isPeriod: true, startId: 'second'),
        _legacy('second-end', 12,
            isPeriod: true, startId: 'second', endId: 'second-end'),
      ];
      final result =
          await _migrationService(store, legacy).migrateLegacyCycles('u');
      expect(result.failed, 1);
      expect(result.created, 1);
      expect(store.cycles, hasLength(1));
    });

    test('migration never modifies or deletes legacy records', () async {
      final store = _MemoryPeriodCycleStore();
      final legacyStore = _MemoryLegacyStore()
        ..records.addAll(_completedLegacy());
      await PeriodCycleService(
        store: store,
        legacyStore: legacyStore,
        migrationWriter: store,
      ).migrateLegacyCycles('u');
      expect(legacyStore.writeCount, 0);
      expect(legacyStore.records, hasLength(5));
    });

    test('unified reader has one visible cycle before and after migration',
        () async {
      final store = _MemoryPeriodCycleStore();
      final legacyStore = _MemoryLegacyStore()
        ..records.addAll(_completedLegacy());
      final service = PeriodCycleService(
        store: store,
        legacyStore: legacyStore,
        migrationWriter: store,
      );
      expect(await service.getUnifiedCycles('u'), hasLength(1));
      await service.migrateLegacyCycles('u');
      expect(await service.getUnifiedCycles('u'), hasLength(1));
    });
  });

  test('QuickRecord state UI uses only canonical 1-to-5 state keys', () {
    expect(QuickRecordEditor.stateKeys, const [
      'energy_level',
      'appetite_level',
      'activity_level',
    ]);
    expect(QuickRecordEditor.stateKeys, isNot(contains('energy')));
    expect(QuickRecordEditor.stateKeys, isNot(contains('appetite')));
    expect(QuickRecordEditor.stateKeys, isNot(contains('activity')));
  });
}

class _MemoryPeriodCycleStore
    implements PeriodCycleStore, PeriodCycleMigrationWriter {
  final List<PeriodCycle> cycles = [];
  final String collectionName = 'periodCycles';
  int writeCount = 0;
  bool failNextCreate = false;
  int statusVersion = 0;

  @override
  Future<String> createCycle(String userId, DateTime startDate) async {
    writeCount++;
    final id = 'p${cycles.length + 1}';
    cycles.add(PeriodCycle(id: id, startDate: startDate));
    return id;
  }

  @override
  Future<List<PeriodCycle>> getCycles(String userId) async =>
      List<PeriodCycle>.from(cycles);

  @override
  Future<bool> createCycleIfAbsent(String userId, PeriodCycle cycle) async {
    writeCount++;
    if (failNextCreate) {
      failNextCreate = false;
      throw StateError('simulated cycle failure');
    }
    if (cycles.any((item) => item.id == cycle.id)) return false;
    cycles.add(cycle);
    cycles.sort((a, b) => a.startDate.compareTo(b.startDate));
    return true;
  }

  @override
  Future<void> recordMigrationStatus(
    String userId, {
    required int version,
    required int created,
    required int skipped,
    required int failed,
  }) async {
    statusVersion = version;
  }

  @override
  Future<void> updateCycle(
    String userId,
    PeriodCycle cycle, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    writeCount++;
    final index = cycles.indexWhere((item) => item.id == cycle.id);
    cycles[index] = PeriodCycle(
      id: cycle.id,
      startDate: startDate ?? cycle.startDate,
      endDate: endDate ?? cycle.endDate,
    );
  }
}

class _MemoryLegacyStore implements LegacyPeriodRecordStore {
  final List<LegacyPeriodRecord> records = [];
  int writeCount = 0;

  @override
  Future<List<LegacyPeriodRecord>> getRecords(String userId) async =>
      List<LegacyPeriodRecord>.from(records);
}

LegacyPeriodRecord _legacy(
  String id,
  int day, {
  bool isPeriod = false,
  String? startId,
  String? endId,
}) =>
    LegacyPeriodRecord(
      id: id,
      date: DateTime(2026, 8, day),
      isPeriod: isPeriod,
      periodStartId: startId,
      periodEndId: endId,
    );

PeriodCycleService _migrationService(
  _MemoryPeriodCycleStore store,
  List<LegacyPeriodRecord> records,
) {
  final legacyStore = _MemoryLegacyStore()..records.addAll(records);
  return PeriodCycleService(
    store: store,
    legacyStore: legacyStore,
    migrationWriter: store,
  );
}

List<LegacyPeriodRecord> _completedLegacy() => [
      _legacy('start', 1, isPeriod: true, startId: 'start'),
      _legacy('day-2', 2, isPeriod: true, startId: 'start'),
      _legacy('day-3', 3, isPeriod: true, startId: 'start'),
      _legacy('day-4', 4, isPeriod: true, startId: 'start'),
      _legacy('end', 5, isPeriod: true, startId: 'start', endId: 'end'),
    ];
