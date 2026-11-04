/// Compatibility parser for sleep values shared by daily records, sleep
/// insights, medication comparison and follow-up summaries.
class SleepRecordParser {
  const SleepRecordParser._();

  /// Returns sleep quality on the App's current 1–5 scale.
  ///
  /// A value alone never identifies its scale. Supply [knownScale] only when
  /// the caller knows the source schema; otherwise explicit scale metadata is
  /// required. Invalid explicit metadata is not overridden by [knownScale].
  /// Only 1–5 and 1–10 scales are supported. Missing/invalid values stay null.
  static int? quality(
    Map<String, dynamic>? sleep, {
    Map<String, dynamic>? record,
    int? knownScale,
  }) {
    final source = sleep ?? const <String, dynamic>{};
    final raw = source['quality'] ??
        source['sleepQuality'] ??
        source['qualityScore'] ??
        record?['sleepQuality'];
    final parsed = _number(raw);
    if (parsed == null || !parsed.isFinite) return null;

    final rawScale = source['qualityScale'] ??
        source['sleepQualityScale'] ??
        record?['sleepQualityScale'];
    final scale = rawScale == null ? knownScale?.toDouble() : _number(rawScale);
    if (scale != 5 && scale != 10) return null;
    if (parsed < 1 || parsed > scale!) return null;
    final normalized = parsed * 5 / scale;
    return normalized.round().clamp(1, 5);
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }
}
