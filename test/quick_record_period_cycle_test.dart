import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/period_cycle_service.dart';
import 'package:moodsogood_app/daily/quick_record_editor.dart';
import 'package:moodsogood_app/models/period_cycle.dart';

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

  test('QuickRecord state UI uses only canonical 1-to-5 state keys', () {
    expect(QuickRecordEditor.stateKeys, const [
      'energy_change',
      'appetite_change',
      'activity_change',
    ]);
    expect(QuickRecordEditor.stateKeys, isNot(contains('energy')));
    expect(QuickRecordEditor.stateKeys, isNot(contains('appetite')));
    expect(QuickRecordEditor.stateKeys, isNot(contains('activity')));
  });
}

class _MemoryPeriodCycleStore implements PeriodCycleStore {
  final List<PeriodCycle> cycles = [];
  final String collectionName = 'periodCycles';

  @override
  Future<String> createCycle(String userId, DateTime startDate) async {
    final id = 'p${cycles.length + 1}';
    cycles.add(PeriodCycle(id: id, startDate: startDate));
    return id;
  }

  @override
  Future<List<PeriodCycle>> getCycles(String userId) async =>
      List<PeriodCycle>.from(cycles);

  @override
  Future<void> updateCycle(
    String userId,
    PeriodCycle cycle, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final index = cycles.indexWhere((item) => item.id == cycle.id);
    cycles[index] = PeriodCycle(
      id: cycle.id,
      startDate: startDate ?? cycle.startDate,
      endDate: endDate ?? cycle.endDate,
    );
  }
}
