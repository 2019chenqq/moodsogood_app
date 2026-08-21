import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/unified_health_data.dart';
import 'package:moodsogood_app/services/cooccurrence_cluster_service.dart';

void main() {
  const service = CooccurrenceClusterService();

  CooccurrenceItem item(String value) =>
      CooccurrenceItem(id: 'symptom:$value', label: value, category: 'symptom');

  CooccurrenceEvidenceRecord day(int day, List<String> values) =>
      CooccurrenceEvidenceRecord(
        date: DateTime(2026, 8, day),
        items: values.map(item).toList(),
        sourceId: 'day-$day',
        sourceType: 'legacyDailyRecord',
      );

  CooccurrenceEvidenceRecord event(
    int day,
    int hour,
    String id,
    List<String> values,
  ) =>
      CooccurrenceEvidenceRecord(
        date: DateTime(2026, 8, day),
        timestamp: DateTime(2026, 8, day, hour),
        hasReliableTimestamp: true,
        items: values.map(item).toList(),
        sourceId: id,
        sourceType: 'healthEvent',
      );

  test('companions come only from matched events and require two matches', () {
    final clusters = service.analyze([
      event(1, 8, 'e1', ['心悸', '胃食道逆流', '焦慮', '只出現一次']),
      event(2, 8, 'e2', ['心悸', '胃食道逆流', '焦慮']),
      event(3, 8, 'e3', ['心悸', '胃食道逆流']),
      event(1, 20, 'unrelated', ['頻尿', '空洞', '害怕']),
      CooccurrenceEvidenceRecord(
        date: DateTime(2026, 8, 2),
        items: [item('睡眠較差'), item('感恩'), item('自信')],
        sourceId: 'legacy-2',
        sourceType: 'legacyDailyRecord',
      ),
      CooccurrenceEvidenceRecord(
        date: DateTime(2026, 8, 3),
        items: [item('滿足')],
        sourceId: 'check-in-3',
        sourceType: 'dailyCheckIn',
      ),
    ]);

    final cluster = clusters.firstWhere(
      (value) => value.coreItems.toSet().containsAll(['心悸', '胃食道逆流']),
    );
    expect(cluster.occurrenceCount, 3);
    expect(cluster.companionItems, ['焦慮']);
    expect(cluster.companionCounts, {'焦慮': 2});
    expect(cluster.companionItems, isNot(contains('只出現一次')));
    expect(cluster.companionItems,
        isNot(containsAll(['頻尿', '空洞', '害怕', '睡眠較差', '感恩', '自信', '滿足'])));
    expect(cluster.companionItems, isNot(contains('心悸')));
    expect(cluster.companionItems, isNot(contains('胃食道逆流')));
  });

  test('legacy same-day core never gains event companions', () {
    final clusters = service.analyze([
      day(1, ['多夢', '睡眠較差', '頻尿']),
      day(2, ['多夢', '睡眠較差', '害怕']),
    ]);

    final cluster = clusters.firstWhere(
      (value) => value.coreItems.toSet().containsAll(['多夢', '睡眠較差']),
    );
    expect(cluster.companionItems, isEmpty);
    expect(cluster.companionCounts, isEmpty);
  });

  test('date-only evidence never contributes to nearby-time count', () {
    final clusters = service.analyze([
      day(1, ['焦慮', '心悸']),
      day(2, ['焦慮', '心悸']),
    ]);

    expect(clusters.single.sameDayCount, 2);
    expect(clusters.single.nearbyTimeCount, 0);
  });

  test('same event is counted once and is not also counted within two hours',
      () {
    final clusters = service.analyze([
      event(1, 8, 'e1', ['心悸', '胃食道逆流']),
      event(1, 9, 'e2', ['心悸']),
      event(2, 8, 'e3', ['心悸', '胃食道逆流']),
    ]);

    final cluster = clusters.single;
    expect(cluster.occurrenceCount, 2);
    expect(cluster.sameDayCount, 2);
    expect(cluster.nearbyTimeCount, 0);
  });

  test('unordered cross-event pair within two hours is counted once', () {
    final clusters = service.analyze([
      event(1, 8, 'a1', ['心悸']),
      event(1, 9, 'b1', ['胃食道逆流']),
      event(2, 8, 'b2', ['胃食道逆流']),
      event(2, 10, 'a2', ['心悸']),
    ]);

    final cluster = clusters.single;
    expect(cluster.occurrenceCount, 2);
    expect(cluster.sameDayCount, 0);
    expect(cluster.nearbyTimeCount, 2);
    final evidence = cluster.sourceMetadata['evidence'] as List;
    expect(evidence.map((e) => e['matchType']), everyElement('within2h'));
  });

  test('duplicate aggregate with the same source id does not double count', () {
    final raw = event(1, 8, 'same-id', ['心悸', '胃食道逆流']);
    final clusters = service.analyze([
      raw,
      CooccurrenceEvidenceRecord(
        date: raw.date,
        timestamp: raw.timestamp,
        hasReliableTimestamp: true,
        items: raw.items,
        sourceId: raw.sourceId,
        sourceType: 'aggregateObservation',
      ),
      event(2, 8, 'e2', ['心悸', '胃食道逆流']),
    ]);

    expect(clusters.single.occurrenceCount, 2);
  });

  test('state-level labels use level keys and reject old change keys', () {
    expect(CooccurrenceLabelMapper.stateLevel('energy_level', 2)?.label, '能量低');
    expect(
        CooccurrenceLabelMapper.stateLevel('activity_level', 4)?.label, '活動量高');
    expect(CooccurrenceLabelMapper.stateLevel('appetite_level', 3), isNull);
    expect(CooccurrenceLabelMapper.stateLevel('energy_change', 1), isNull);
    expect(CooccurrenceLabelMapper.stateLevel('appetite_change', 5), isNull);
    expect(CooccurrenceLabelMapper.stateLevel('activity_change', 1), isNull);
  });

  test('HealthEvent level participates in all same-event pairs', () {
    final records = CooccurrenceEvidenceAdapter.fromUnifiedHealthEvents([
      for (var day = 1; day <= 2; day++)
        UnifiedHealthData(
          source: UnifiedHealthDataSource.healthEvent,
          precision: UnifiedHealthDataPrecision.timestamp,
          date: DateTime(2026, 8, day),
          timestamp: DateTime(2026, 8, day, 8),
          sourceId: 'event-$day',
          symptoms: const [
            UnifiedScoredValue(name: '疲倦', value: 4),
            UnifiedScoredValue(name: '白天嗜睡', value: 4),
          ],
          stateChanges: const {'energy_level': 1},
        ),
    ]);

    final clusters = service.analyze(records);
    expect(clusters, hasLength(3));
    for (final expected in const [
      {'疲倦', '白天嗜睡'},
      {'疲倦', '能量低'},
      {'白天嗜睡', '能量低'},
    ]) {
      final cluster = clusters.singleWhere(
          (value) => value.coreItems.toSet().containsAll(expected));
      expect(cluster.occurrenceCount, 2);
      expect(cluster.sameDayCount, 2);
      expect(cluster.nearbyTimeCount, 0);
    }
  });

  test('HealthEvent-only adapter excludes legacy evidence from ranking', () {
    final records = CooccurrenceEvidenceAdapter.fromUnifiedHealthEvents([
      UnifiedHealthData(
        source: UnifiedHealthDataSource.legacyDailyRecord,
        precision: UnifiedHealthDataPrecision.day,
        date: DateTime(2026, 8, 1),
        sourceId: 'legacy',
        symptoms: const [
          UnifiedScoredValue(name: '多夢'),
          UnifiedScoredValue(name: '睡眠較差'),
        ],
      ),
      UnifiedHealthData(
        source: UnifiedHealthDataSource.healthEvent,
        precision: UnifiedHealthDataPrecision.timestamp,
        date: DateTime(2026, 8, 2),
        timestamp: DateTime(2026, 8, 2, 8),
        sourceId: 'event',
        symptoms: const [
          UnifiedScoredValue(name: '疲倦'),
          UnifiedScoredValue(name: '白天嗜睡'),
        ],
      ),
    ]);

    expect(records, hasLength(1));
    expect(records.single.sourceType, 'healthEvent');
  });

  test('maps known raw sleep keys and excludes unknown internal keys', () {
    expect(
        CooccurrenceLabelMapper.named('sleep', 'initInsomnia')?.label, '入睡困難');
    expect(CooccurrenceLabelMapper.named('sleep', 'fragmented')?.label, '睡眠中斷');
    expect(
        CooccurrenceLabelMapper.named('sleep', 'unknownInternalKey'), isNull);
  });
}
