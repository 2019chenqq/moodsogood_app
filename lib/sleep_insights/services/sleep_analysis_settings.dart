class SleepAnalysisSettings {
  const SleepAnalysisSettings._();

  static const int maximumValidNightMinutes = 20 * 60;
  static const int maximumValidNightAwakeningMinutes = 12 * 60;
  static const int maximumValidNapMinutes = 8 * 60;
  static const int minimumComparisonRecords = 2;
  static const int minimumRegularityRecords = 2;
  static const int consecutiveDays = 3;
  static const int belowBaselineMinutes = 60;
  static const int largeChangeMinutes = 120;
  static const int stableDurationVariationMinutes = 45;
  static const int stableClockVariationMinutes = 40;
  static const int largeDurationVariationMinutes = 90;
  static const int largeClockVariationMinutes = 75;
}
