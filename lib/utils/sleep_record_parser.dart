/// Compatibility parser for sleep values shared by daily records, sleep
/// insights, medication comparison and follow-up summaries.
class SleepRecordParser {
  const SleepRecordParser._();

  /// Returns sleep quality on the App's current 1–5 scale.
  ///
  /// Current records store `sleep.quality`. Older builds also used
  /// `sleep.sleepQuality`, `sleep.qualityScore`, or a top-level
  /// `sleepQuality`. Explicit 10-point values are converted to 1–5.
  static int? quality(
    Map<String, dynamic>? sleep, {
    Map<String, dynamic>? record,
  }) {
    final source = sleep ?? const <String, dynamic>{};
    final raw = source['quality'] ??
        source['sleepQuality'] ??
        source['qualityScore'] ??
        record?['sleepQuality'];
    final parsed = _number(raw);
    if (parsed == null || parsed <= 0) return null;

    final rawScale = source['qualityScale'] ??
        source['sleepQualityScale'] ??
        record?['sleepQualityScale'];
    final scale = _number(rawScale);
    final normalized = scale != null && scale > 5
        ? parsed * 5 / scale
        : parsed > 5 && parsed <= 10
            ? parsed / 2
            : parsed;
    if (normalized < 1 || normalized > 5) return null;
    return normalized.round().clamp(1, 5);
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }
}
