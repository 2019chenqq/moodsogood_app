import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../models/unified_health_data.dart';
import '../repositories/unified_health_data_repository.dart';
import '../services/health_co_occurrence_service.dart';

class HealthEventCoOccurrencePage extends StatefulWidget {
  const HealthEventCoOccurrencePage({super.key});

  @override
  State<HealthEventCoOccurrencePage> createState() =>
      _HealthEventCoOccurrencePageState();
}

class _HealthEventCoOccurrencePageState
    extends State<HealthEventCoOccurrencePage> {
  late final Future<_CoOccurrenceViewData> _future = _load();

  Future<_CoOccurrenceViewData> _load() async {
    final now = DateTime.now();
    final data = await UnifiedHealthDataRepository().getByDateRange(
      start: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 89)),
      end: now,
      preserveSourceEvidence: true,
    );
    return _CoOccurrenceViewData.fromUnified(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('共現模式')),
      body: FutureBuilder<_CoOccurrenceViewData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('無法載入共現資料：${snapshot.error}'));
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
            children: [
              Container(
                padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
                decoration: HealingDesignSystem.adaptiveCardDecoration(context),
                child: const Text(
                  '依同一筆快速記錄中的共同出現計算，不代表因果關係。',
                ),
              ),
              const SizedBox(height: HealingDesignSystem.paddingL),
              _TopPairsCard(
                title: '精確事件症狀共現 Top 5',
                emptyText: '目前沒有同一筆快速記錄中的症狀共現資料',
                pairs: data.eventSymptomPairs,
              ),
              const SizedBox(height: HealingDesignSystem.paddingL),
              _TopPairsCard(
                title: '精確事件情緒－症狀 Top 5',
                emptyText: '目前沒有同一筆快速記錄中的情緒與症狀資料',
                pairs: data.eventEmotionSymptomPairs,
              ),
              const SizedBox(height: HealingDesignSystem.paddingL),
              _TopPairsCard(
                title: 'Legacy 同日症狀 Top 5',
                emptyText: '目前沒有舊每日紀錄的同日症狀資料',
                pairs: data.legacySymptomPairs,
              ),
              const SizedBox(height: HealingDesignSystem.paddingL),
              _TopPairsCard(
                title: 'Legacy 同日情緒－症狀 Top 5',
                emptyText: '目前沒有舊每日紀錄的同日情緒與症狀資料',
                pairs: data.legacyEmotionSymptomPairs,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopPairsCard extends StatelessWidget {
  const _TopPairsCard({
    required this.title,
    required this.emptyText,
    required this.pairs,
  });

  final String title;
  final String emptyText;
  final List<_DisplayPair> pairs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: HealingDesignSystem.titleMedium),
          const SizedBox(height: HealingDesignSystem.paddingM),
          if (pairs.isEmpty)
            Text(emptyText, style: HealingDesignSystem.bodySmall)
          else
            for (var index = 0; index < pairs.length; index++) ...[
              if (index > 0) const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${index + 1}. ${pairs[index].left} ＋ ${pairs[index].right}',
                    ),
                  ),
                  Text(
                    '${pairs[index].count} ${pairs[index].unitLabel}',
                    style: HealingDesignSystem.labelMedium.copyWith(
                      color: HealingDesignSystem.primaryBlue,
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

class _CoOccurrenceViewData {
  const _CoOccurrenceViewData({
    required this.eventSymptomPairs,
    required this.eventEmotionSymptomPairs,
    required this.legacySymptomPairs,
    required this.legacyEmotionSymptomPairs,
  });

  final List<_DisplayPair> eventSymptomPairs;
  final List<_DisplayPair> eventEmotionSymptomPairs;
  final List<_DisplayPair> legacySymptomPairs;
  final List<_DisplayPair> legacyEmotionSymptomPairs;

  factory _CoOccurrenceViewData.fromUnified(List<UnifiedHealthData> data) {
    const service = HealthCoOccurrenceService();
    final result = service.calculate(data);

    return _CoOccurrenceViewData(
      eventSymptomPairs: _topFive(result.eventSymptomCoOccurrences,
          unitLabel: CoOccurrenceEvidence.preciseEvent.countLabel),
      eventEmotionSymptomPairs: _topFive(result.eventCoOccurrences,
          unitLabel: CoOccurrenceEvidence.preciseEvent.countLabel),
      legacySymptomPairs: _topFive(result.legacySymptomSameDayRecords,
          unitLabel: CoOccurrenceEvidence.legacySameDay.countLabel),
      legacyEmotionSymptomPairs: _topFive(result.legacySameDayRecords,
          unitLabel: CoOccurrenceEvidence.legacySameDay.countLabel),
    );
  }

  static List<_DisplayPair> _topFive(
    Map<String, int> counts, {
    required String unitLabel,
  }) {
    final pairs = counts.entries.map((entry) {
      final labels = entry.key.split('\u0000');
      return _DisplayPair(
        left: labels.first,
        right: labels.length > 1 ? labels[1] : '',
        count: entry.value,
        unitLabel: unitLabel,
      );
    }).toList()
      ..sort((a, b) {
        final countOrder = b.count.compareTo(a.count);
        if (countOrder != 0) return countOrder;
        final leftOrder = a.left.compareTo(b.left);
        return leftOrder != 0 ? leftOrder : a.right.compareTo(b.right);
      });
    return pairs.take(5).toList(growable: false);
  }
}

class _DisplayPair {
  const _DisplayPair({
    required this.left,
    required this.right,
    required this.count,
    required this.unitLabel,
  });

  final String left;
  final String right;
  final int count;
  final String unitLabel;
}
