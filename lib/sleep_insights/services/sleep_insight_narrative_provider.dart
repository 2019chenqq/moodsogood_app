import '../models/sleep_insight_models.dart';

abstract class SleepInsightNarrativeProvider {
  Future<String> generateNarrative(SleepInsightResult result);
}

class RuleBasedSleepInsightNarrativeProvider
    implements SleepInsightNarrativeProvider {
  const RuleBasedSleepInsightNarrativeProvider();

  @override
  Future<String> generateNarrative(SleepInsightResult result) async =>
      result.narrative.join('');
}
