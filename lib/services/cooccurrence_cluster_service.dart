import 'package:flutter/foundation.dart';

import '../models/life_timeline_item.dart';
import '../models/unified_health_data.dart';

class CooccurrenceItem {
  const CooccurrenceItem({
    required this.id,
    required this.label,
    required this.category,
  });

  final String id;
  final String label;
  final String category;
}

class CooccurrenceEvidenceRecord {
  const CooccurrenceEvidenceRecord({
    required this.date,
    required this.items,
    required this.sourceId,
    required this.sourceType,
    this.timestamp,
    this.hasReliableTimestamp = false,
    this.metadata = const {},
  });

  final DateTime date;
  final DateTime? timestamp;
  final bool hasReliableTimestamp;
  final List<CooccurrenceItem> items;
  final String sourceId;
  final String sourceType;
  final Map<String, dynamic> metadata;
}

class CooccurrenceCluster {
  const CooccurrenceCluster({
    required this.coreItems,
    required this.companionItems,
    this.companionCounts = const {},
    required this.occurrenceCount,
    required this.sameDayCount,
    required this.nearbyTimeCount,
    required this.windowMinutes,
    required this.dateRangeStart,
    required this.dateRangeEnd,
    required this.sourceMetadata,
  });

  final List<String> coreItems;
  final List<String> companionItems;
  final Map<String, int> companionCounts;
  final int occurrenceCount;
  final int sameDayCount;
  final int nearbyTimeCount;
  final int windowMinutes;
  final DateTime dateRangeStart;
  final DateTime dateRangeEnd;
  final Map<String, dynamic> sourceMetadata;

  Map<String, dynamic> toMap() => {
        'coreItems': coreItems,
        'companionItems': companionItems,
        'occurrenceCount': occurrenceCount,
        'sameDayCount': sameDayCount,
        'nearbyTimeCount': nearbyTimeCount,
        'windowMinutes': windowMinutes,
        'dateRange': {
          'start': _dateText(dateRangeStart),
          'end': _dateText(dateRangeEnd),
        },
        'sourceMetadata': sourceMetadata,
      };
}

/// The single clustering implementation used by life overview, quick record,
/// and follow-up summaries. It is intentionally descriptive, not causal.
class CooccurrenceClusterService {
  const CooccurrenceClusterService({
    this.windowMinutes = 120,
    this.minimumOccurrences = 2,
  });

  final int windowMinutes;
  final int minimumOccurrences;

  List<CooccurrenceCluster> analyze(
    Iterable<CooccurrenceEvidenceRecord> source, {
    Set<String> focusItemIds = const {},
    DateTime? startInclusive,
    DateTime? endInclusive,
  }) {
    final records = _deduplicateEvidence(
      source.map(_cleanRecord).where((record) {
        final value = record.timestamp ?? record.date;
        return record.items.isNotEmpty &&
            (startInclusive == null || !value.isBefore(startInclusive)) &&
            (endInclusive == null || !value.isAfter(endInclusive));
      }),
    );
    if (records.isEmpty) return const [];
    final start = records.map((r) => r.date).reduce(_earlier);
    final end = records.map((r) => r.date).reduce(_later);
    final evidenceByPair = _pairEvidence(records);
    final labels = <String, String>{
      for (final record in records)
        for (final item in record.items) item.id: item.label,
    };
    final drafts = <_ClusterDraft>[];
    for (final pairEvidence in evidenceByPair.values) {
      final core = pairEvidence.first.itemIds;
      final occurrenceCount = pairEvidence.length;
      if (occurrenceCount < minimumOccurrences) continue;
      final matchingEvents = records
          .where((record) =>
              record.sourceType == UnifiedHealthDataSource.healthEvent.name &&
              record.items.map((item) => item.id).toSet().containsAll(core))
          .map((record) => _observation([record]))
          .toList(growable: false);
      final companionEvidence = matchingEvents;
      final companionCounts = <String, int>{};
      for (final observation in companionEvidence) {
        for (final id in observation.itemIds.difference(core)) {
          companionCounts.update(id, (value) => value + 1, ifAbsent: () => 1);
        }
      }
      final companions =
          companionCounts.entries.where((entry) => entry.value >= 2).toList()
            ..sort((a, b) {
              final countOrder = b.value.compareTo(a.value);
              return countOrder != 0 ? countOrder : a.key.compareTo(b.key);
            });
      final limitedCompanions = companions.take(5).toList(growable: false);
      drafts.add(_ClusterDraft(
        core: core,
        companions: limitedCompanions.map((e) => e.key).toList(),
        companionCounts: {
          for (final entry in limitedCompanions) entry.key: entry.value,
        },
        occurrenceCount: occurrenceCount,
        sameDayCount:
            pairEvidence.where((e) => e.matchType != 'within2h').length,
        nearbyTimeCount:
            pairEvidence.where((e) => e.matchType == 'within2h').length,
        sourceIds: pairEvidence.expand((o) => o.sourceIds).toSet(),
        sourceTypes: pairEvidence.expand((o) => o.sourceTypes).toSet(),
        evidence: pairEvidence,
      ));
    }

    drafts.sort((a, b) => _compareDrafts(a, b, focusItemIds));
    final kept = <_ClusterDraft>[];
    for (final candidate in drafts) {
      final isNearDuplicateSubset = kept.any((larger) =>
          larger.core.length > candidate.core.length &&
          larger.core.containsAll(candidate.core) &&
          (larger.occurrenceCount - candidate.occurrenceCount).abs() <= 1);
      final isCompanionVariant = kept.any((stable) =>
          candidate.core.length > stable.core.length &&
          candidate.core.containsAll(stable.core) &&
          (stable.occurrenceCount - candidate.occurrenceCount).abs() <= 1);
      if (!isNearDuplicateSubset && !isCompanionVariant) kept.add(candidate);
    }

    final List<CooccurrenceCluster> result =
        List.unmodifiable(kept.map((draft) => CooccurrenceCluster(
              coreItems: (draft.core.map((id) => labels[id]!).toList()..sort()),
              companionItems: draft.companions
                  .map((id) => labels[id])
                  .whereType<String>()
                  .toList(),
              companionCounts: {
                for (final id in draft.companions)
                  if (labels[id] != null)
                    labels[id]!: draft.companionCounts[id] ?? 0,
              },
              occurrenceCount: draft.occurrenceCount,
              sameDayCount: draft.sameDayCount,
              nearbyTimeCount: draft.nearbyTimeCount,
              windowMinutes: windowMinutes,
              dateRangeStart: start,
              dateRangeEnd: end,
              sourceMetadata: {
                'sourceIds': draft.sourceIds.toList()..sort(),
                'sourceTypes': draft.sourceTypes.toList()..sort(),
                'evidence': draft.evidence.map((e) => e.toMap()).toList(),
              },
            )));
    for (final cluster in result.take(3)) {
      final pair = cluster.coreItems.join('+');
      final evidence = cluster.sourceMetadata['evidence'] as List? ?? const [];
      for (final raw in evidence) {
        final item = raw as Map;
        debugPrint('[CoOccurrence] pair=$pair / eventId=${item['eventId']} '
            '/ timestamp=${item['timestamp']} '
            '/ matchedEventId=${item['matchedEventId']} '
            '/ matchType=${item['matchType']}');
      }
    }
    return result;
  }

  List<CooccurrenceEvidenceRecord> _deduplicateEvidence(
    Iterable<CooccurrenceEvidenceRecord> source,
  ) {
    final byIdentity = <String, CooccurrenceEvidenceRecord>{};
    for (final record in source) {
      final timestamp =
          record.timestamp?.toIso8601String() ?? record.date.toIso8601String();
      final identity = record.sourceId.isNotEmpty
          ? record.sourceId
          : '${record.sourceType}:$timestamp';
      final current = byIdentity[identity];
      if (current == null ||
          (record.sourceType == UnifiedHealthDataSource.healthEvent.name &&
              current.sourceType != UnifiedHealthDataSource.healthEvent.name)) {
        byIdentity[identity] = record;
      }
    }
    return byIdentity.values.toList()
      ..sort(
          (a, b) => (a.timestamp ?? a.date).compareTo(b.timestamp ?? b.date));
  }

  Map<String, List<_PairEvidence>> _pairEvidence(
    List<CooccurrenceEvidenceRecord> records,
  ) {
    final result = <String, List<_PairEvidence>>{};
    void add(Set<String> pair, CooccurrenceEvidenceRecord left,
        CooccurrenceEvidenceRecord? right, String matchType) {
      result.putIfAbsent(_setKey(pair), () => []).add(_PairEvidence(
            itemIds: pair,
            sourceIds: {left.sourceId, if (right != null) right.sourceId},
            sourceTypes: {left.sourceType, if (right != null) right.sourceType},
            eventId: left.sourceId,
            timestamp: left.timestamp ?? left.date,
            matchedEventId: right?.sourceId,
            matchType: matchType,
          ));
    }

    final precise = <CooccurrenceEvidenceRecord>[];
    final legacyByDay = <String, List<CooccurrenceEvidenceRecord>>{};
    for (final record in records) {
      final ids = record.items.map((i) => i.id).toSet().toList()..sort();
      if (record.sourceType == UnifiedHealthDataSource.healthEvent.name &&
          record.hasReliableTimestamp &&
          record.timestamp != null) {
        precise.add(record);
        for (var i = 0; i < ids.length; i++) {
          for (var j = i + 1; j < ids.length; j++) {
            add({ids[i], ids[j]}, record, null, 'sameEvent');
          }
        }
      } else if (record.sourceType ==
          UnifiedHealthDataSource.legacyDailyRecord.name) {
        legacyByDay.putIfAbsent(_dateText(record.date), () => []).add(record);
      }
    }
    for (final dayRecords in legacyByDay.values) {
      final ids = dayRecords
          .expand((r) => r.items.map((i) => i.id))
          .toSet()
          .toList()
        ..sort();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          add({ids[i], ids[j]}, dayRecords.first, null, 'legacySameDay');
        }
      }
    }
    for (var i = 0; i < precise.length; i++) {
      for (var j = i + 1; j < precise.length; j++) {
        final left = precise[i];
        final right = precise[j];
        if (right.timestamp!.difference(left.timestamp!).abs() >
            Duration(minutes: windowMinutes)) {
          continue;
        }
        final leftIds = left.items.map((e) => e.id).toSet();
        final rightIds = right.items.map((e) => e.id).toSet();
        final pairs = <String, Set<String>>{};
        for (final a in leftIds) {
          for (final b in rightIds) {
            if (a == b) continue;
            final pair = {a, b};
            if (leftIds.containsAll(pair) || rightIds.containsAll(pair)) {
              continue;
            }
            pairs[_setKey(pair)] = pair;
          }
        }
        for (final pair in pairs.values) {
          add(pair, left, right, 'within2h');
        }
      }
    }
    return result;
  }

  CooccurrenceEvidenceRecord _cleanRecord(CooccurrenceEvidenceRecord record) {
    final unique = <String, CooccurrenceItem>{};
    for (final item in record.items) {
      if (item.id.trim().isNotEmpty && item.label.trim().isNotEmpty) {
        unique[item.id] = item;
      }
    }
    return CooccurrenceEvidenceRecord(
      date: _day(record.date),
      timestamp: record.timestamp,
      hasReliableTimestamp: record.hasReliableTimestamp,
      items: unique.values.toList(),
      sourceId: record.sourceId,
      sourceType: record.sourceType,
      metadata: record.metadata,
    );
  }

  _Observation _observation(List<CooccurrenceEvidenceRecord> records) =>
      _Observation(
        itemIds: records.expand((r) => r.items.map((i) => i.id)).toSet(),
        sourceIds:
            records.map((r) => r.sourceId).where((id) => id.isNotEmpty).toSet(),
        sourceTypes: records
            .map((r) => r.sourceType)
            .where((type) => type.isNotEmpty)
            .toSet(),
      );

  int _compareDrafts(_ClusterDraft a, _ClusterDraft b, Set<String> focus) {
    final focusOrder = b.core
        .intersection(focus)
        .length
        .compareTo(a.core.intersection(focus).length);
    if (focusOrder != 0) return focusOrder;
    final countOrder = b.occurrenceCount.compareTo(a.occurrenceCount);
    if (countOrder != 0) return countOrder;
    final sizeOrder = b.core.length.compareTo(a.core.length);
    if (sizeOrder != 0) return sizeOrder;
    return b.nearbyTimeCount.compareTo(a.nearbyTimeCount);
  }

  static String _setKey(Set<String> values) =>
      (values.toList()..sort()).join('|');
  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
}

/// Converts existing data-layer objects into shared, low-information-filtered
/// evidence. It never creates an event for mere record existence.
class CooccurrenceEvidenceAdapter {
  const CooccurrenceEvidenceAdapter._();

  static List<CooccurrenceEvidenceRecord> fromUnified(
          List<UnifiedHealthData> data) =>
      [
        for (var index = 0; index < data.length; index++)
          _fromUnified(data[index], index),
      ];

  static List<CooccurrenceEvidenceRecord> fromUnifiedHealthEvents(
          Iterable<UnifiedHealthData> data) =>
      fromUnified(
        data
            .where((item) => item.source == UnifiedHealthDataSource.healthEvent)
            .toList(growable: false),
      );

  static CooccurrenceEvidenceRecord _fromUnified(
      UnifiedHealthData value, int index) {
    final items = <CooccurrenceItem>[
      ...value.symptoms
          .map((v) => CooccurrenceLabelMapper.named('symptom', v.name))
          .whereType<CooccurrenceItem>(),
      ...value.emotions
          .map((v) => CooccurrenceLabelMapper.named('emotion', v.name))
          .whereType<CooccurrenceItem>(),
      ...value.stateChanges.entries
          .map((e) => CooccurrenceLabelMapper.stateLevel(e.key, e.value))
          .whereType<CooccurrenceItem>(),
      ...value.sleepFlags
          .map((flag) => CooccurrenceLabelMapper.named('sleep', flag))
          .whereType<CooccurrenceItem>(),
      if (value.sleepQuality != null && value.sleepQuality! <= 2)
        const CooccurrenceItem(
          id: 'sleep:poorQuality',
          label: '睡眠較差',
          category: 'sleep',
        ),
    ];
    final sourceType = value.source.name;
    return CooccurrenceEvidenceRecord(
      date: value.date,
      timestamp: value.timestamp,
      hasReliableTimestamp:
          value.precision == UnifiedHealthDataPrecision.timestamp &&
              value.timestamp != null,
      items: items,
      sourceId: value.sourceId?.trim().isNotEmpty == true
          ? value.sourceId!
          : '$sourceType:${value.timestamp?.toIso8601String() ?? value.dateKey}:$index',
      sourceType: sourceType,
      metadata: {'timestampPrecision': value.precision.name},
    );
  }

  static List<CooccurrenceEvidenceRecord> fromTimeline(
    Map<DateTime, List<LifeTimelineItem>> itemsByDate,
  ) =>
      [
        for (final entry in itemsByDate.entries)
          for (var index = 0; index < entry.value.length; index++)
            _fromTimelineItem(entry.key, entry.value[index], index),
      ];

  static CooccurrenceEvidenceRecord _fromTimelineItem(
      DateTime date, LifeTimelineItem item, int index) {
    final metadata = item.metadata ?? const <String, dynamic>{};
    final signals = <CooccurrenceItem>[];
    void addNamed(String category, dynamic values) {
      if (values is! Iterable) return;
      for (final raw in values) {
        final name =
            raw is Map ? raw['name']?.toString() ?? '' : raw.toString();
        final signal = CooccurrenceLabelMapper.named(category, name);
        if (signal != null) signals.add(signal);
      }
    }

    addNamed('symptom', metadata['symptoms']);
    addNamed('emotion', metadata['emotions']);
    if (item.type == LifeTimelineType.sleep) {
      final quality = metadata['quality'];
      if (quality is num && quality <= 2) {
        signals.add(const CooccurrenceItem(
            id: 'sleep:poorQuality', label: '睡眠較差', category: 'sleep'));
      }
      final flags = metadata['flags'];
      if (flags is Iterable) {
        for (final raw in flags) {
          final signal = CooccurrenceLabelMapper.named('sleep', raw.toString());
          if (signal != null) signals.add(signal);
        }
      }
    }
    final changes = metadata['stateChanges'];
    if (changes is Map) {
      for (final entry in changes.entries) {
        final value = entry.value is num ? (entry.value as num).toInt() : null;
        if (value == null) continue;
        final signal =
            CooccurrenceLabelMapper.stateLevel(entry.key.toString(), value);
        if (signal != null) signals.add(signal);
      }
    }
    final rawSourceType = metadata['sourceType']?.toString();
    final sourceType = item.type == LifeTimelineType.quickRecord ||
            rawSourceType == 'healthEvent'
        ? UnifiedHealthDataSource.healthEvent.name
        : rawSourceType == 'dailyRecord'
            ? UnifiedHealthDataSource.legacyDailyRecord.name
            : rawSourceType ?? item.type;
    return CooccurrenceEvidenceRecord(
      date: date,
      timestamp: item.hasExplicitTime ? item.time : null,
      hasReliableTimestamp:
          item.hasExplicitTime && metadata['timestampPrecision'] != 'day',
      items: signals,
      sourceId:
          item.sourceId ?? '$sourceType:${item.time.toIso8601String()}:$index',
      sourceType: sourceType,
      metadata: {'timelineType': item.type, ...metadata},
    );
  }
}

class CooccurrenceLabelMapper {
  const CooccurrenceLabelMapper._();

  static const sleepLabels = <String, String>{
    'initInsomnia': '入睡困難',
    'fragmented': '睡眠中斷',
    'interrupted': '睡眠中斷',
    'earlyWake': '早醒',
    'dreams': '多夢',
    'lightSleep': '淺眠',
    'nocturia': '夜尿',
    'insufficient': '睡眠不足',
  };

  static CooccurrenceItem? named(String category, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final label = sleepLabels[value] ?? value;
    if (label.contains('_') || RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(label)) {
      return null;
    }
    return CooccurrenceItem(
        id: '$category:$value', label: label, category: category);
  }

  static CooccurrenceItem? stateLevel(String key, int score) {
    if (score == 3 || score < 1 || score > 5) {
      return null;
    }
    final dimension = switch (key) {
      'energy_level' => '能量',
      'appetite_level' => '食慾',
      'activity_level' => '活動量',
      _ => '',
    };
    if (dimension.isEmpty) return null;
    return CooccurrenceItem(
      id: 'state:$key:${score < 3 ? 'low' : 'high'}',
      label: '$dimension${score < 3 ? '低' : '高'}',
      category: 'stateLevel',
    );
  }
}

String _dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class _Observation {
  const _Observation(
      {required this.itemIds,
      required this.sourceIds,
      required this.sourceTypes});
  final Set<String> itemIds;
  final Set<String> sourceIds;
  final Set<String> sourceTypes;
}

class _PairEvidence extends _Observation {
  const _PairEvidence({
    required super.itemIds,
    required super.sourceIds,
    required super.sourceTypes,
    required this.eventId,
    required this.timestamp,
    required this.matchedEventId,
    required this.matchType,
  });

  final String eventId;
  final DateTime timestamp;
  final String? matchedEventId;
  final String matchType;

  Map<String, dynamic> toMap() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'matchedEventId': matchedEventId,
        'matchType': matchType,
      };
}

class _ClusterDraft {
  const _ClusterDraft({
    required this.core,
    required this.companions,
    required this.companionCounts,
    required this.occurrenceCount,
    required this.sameDayCount,
    required this.nearbyTimeCount,
    required this.sourceIds,
    required this.sourceTypes,
    required this.evidence,
  });
  final Set<String> core;
  final List<String> companions;
  final Map<String, int> companionCounts;
  final int occurrenceCount;
  final int sameDayCount;
  final int nearbyTimeCount;
  final Set<String> sourceIds;
  final Set<String> sourceTypes;
  final List<_PairEvidence> evidence;
}
