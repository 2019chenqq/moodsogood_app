import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../models/health_event.dart';
import '../models/unified_health_data.dart';
import '../repositories/unified_health_data_repository.dart';
import '../services/health_co_occurrence_service.dart';
import 'health_event_repository.dart';

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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('請先登入');
    final now = DateTime.now();
    final events = await HealthEventRepository().getByDateRange(
      userId: uid,
      start: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 89)),
      end: now,
    );
    return _CoOccurrenceViewData.fromEvents(events);
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
                title: '症狀＋症狀 Top 5',
                pairs: data.symptomPairs,
              ),
              const SizedBox(height: HealingDesignSystem.paddingL),
              _TopPairsCard(
                title: '情緒＋症狀 Top 5',
                pairs: data.emotionSymptomPairs,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopPairsCard extends StatelessWidget {
  const _TopPairsCard({required this.title, required this.pairs});

  final String title;
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
            Text('目前沒有足夠的共同出現資料', style: HealingDesignSystem.bodySmall)
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
                    '共同出現 ${pairs[index].count} 次',
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
    required this.symptomPairs,
    required this.emotionSymptomPairs,
  });

  final List<_DisplayPair> symptomPairs;
  final List<_DisplayPair> emotionSymptomPairs;

  factory _CoOccurrenceViewData.fromEvents(List<HealthEvent> events) {
    const service = HealthCoOccurrenceService();
    final normalized = events
        .map(UnifiedHealthDataRepository.fromHealthEvent)
        .toList(growable: false);
    final emotionSymptom = service.calculate(normalized).eventCoOccurrences;

    // Adapt unordered symptom pairs from each individual event into the
    // existing pair counter. Events are never combined by calendar day.
    final symptomPairInputs = <UnifiedHealthData>[];
    for (final event in events) {
      final names = event.symptoms.map((item) => item.name).toSet().toList()
        ..sort();
      for (var left = 0; left < names.length; left++) {
        for (var right = left + 1; right < names.length; right++) {
          symptomPairInputs.add(UnifiedHealthData(
            source: UnifiedHealthDataSource.healthEvent,
            precision: UnifiedHealthDataPrecision.timestamp,
            date: DateTime(
              event.timestamp.year,
              event.timestamp.month,
              event.timestamp.day,
            ),
            timestamp: event.timestamp,
            emotions: [UnifiedScoredValue(name: names[left])],
            symptoms: [UnifiedScoredValue(name: names[right])],
          ));
        }
      }
    }
    final symptomPairs =
        service.calculate(symptomPairInputs).eventCoOccurrences;

    return _CoOccurrenceViewData(
      symptomPairs: _topFive(symptomPairs),
      emotionSymptomPairs: _topFive(emotionSymptom),
    );
  }

  static List<_DisplayPair> _topFive(Map<String, int> counts) {
    final pairs = counts.entries.map((entry) {
      final labels = entry.key.split('\u0000');
      return _DisplayPair(
        left: labels.first,
        right: labels.length > 1 ? labels[1] : '',
        count: entry.value,
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
  });

  final String left;
  final String right;
  final int count;
}
