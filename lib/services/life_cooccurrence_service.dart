import '../models/life_timeline_item.dart';
import 'cooccurrence_cluster_service.dart';

/// Compatibility adapter for the life timeline data layer. All clustering is
/// delegated to [CooccurrenceClusterService].
class LifeCooccurrenceService {
  const LifeCooccurrenceService({this.nearTimeWindowMinutes = 120});

  final int nearTimeWindowMinutes;

  List<CooccurrenceCluster> analyze(
    Map<DateTime, List<LifeTimelineItem>> itemsByDate,
  ) =>
      CooccurrenceClusterService(windowMinutes: nearTimeWindowMinutes).analyze(
        CooccurrenceEvidenceAdapter.fromTimeline(itemsByDate),
      );
}
