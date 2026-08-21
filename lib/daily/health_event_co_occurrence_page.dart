import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../repositories/unified_health_data_repository.dart';
import '../services/cooccurrence_cluster_service.dart';

class HealthEventCoOccurrencePage extends StatefulWidget {
  const HealthEventCoOccurrencePage({super.key});

  @override
  State<HealthEventCoOccurrencePage> createState() =>
      _HealthEventCoOccurrencePageState();
}

class _HealthEventCoOccurrencePageState
    extends State<HealthEventCoOccurrencePage> {
  late final Future<List<CooccurrenceCluster>> _future = _load();

  Future<List<CooccurrenceCluster>> _load() async {
    final now = DateTime.now();
    final data = await UnifiedHealthDataRepository().getByDateRange(
      start: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 89)),
      end: now,
      preserveSourceEvidence: false,
    );
    return const CooccurrenceClusterService().analyze(
      CooccurrenceEvidenceAdapter.fromUnifiedHealthEvents(data),
      startInclusive: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 89)),
      endInclusive: now,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('近期共現模式')),
        body: FutureBuilder<List<CooccurrenceCluster>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('共現紀錄載入失敗，請稍後再試。'));
            }
            final clusters = (snapshot.data ?? const []).take(3).toList();
            return ListView(
              padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
              children: [
                Container(
                  padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
                  decoration:
                      HealingDesignSystem.adaptiveCardDecoration(context),
                  child: const Text(
                    '以下整理近期重複共同出現的紀錄，可作為後續觀察線索，不代表因果關係。',
                  ),
                ),
                const SizedBox(height: HealingDesignSystem.paddingL),
                Container(
                  padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
                  decoration:
                      HealingDesignSystem.adaptiveCardDecoration(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('近期重複出現', style: HealingDesignSystem.titleMedium),
                      const SizedBox(height: HealingDesignSystem.paddingM),
                      if (clusters.isEmpty)
                        Text(
                          '目前還沒有足夠的重複紀錄形成可觀察的共現模式。',
                          style: HealingDesignSystem.bodySmall,
                        )
                      else
                        for (var index = 0;
                            index < clusters.length;
                            index++) ...[
                          if (index > 0) const Divider(height: 24),
                          _ClusterSummary(cluster: clusters[index]),
                        ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _ClusterSummary extends StatelessWidget {
  const _ClusterSummary({required this.cluster});

  final CooccurrenceCluster cluster;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cluster.coreItems.join('＋'),
            style: HealingDesignSystem.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            cluster.nearbyTimeCount > 0
                ? '重複出現 ${cluster.occurrenceCount} 次，其中 ${cluster.nearbyTimeCount} 次在 ${cluster.windowMinutes ~/ 60} 小時內出現'
                : '同日重複出現 ${cluster.sameDayCount} 次',
            style: HealingDesignSystem.bodySmall,
          ),
          if (cluster.companionItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '常伴隨：${cluster.companionItems.map((item) => '$item（${cluster.companionCounts[item]}次）').join('、')}',
              style: HealingDesignSystem.bodySmall,
            ),
          ],
        ],
      );
}
