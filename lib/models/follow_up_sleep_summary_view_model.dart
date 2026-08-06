class FollowUpSleepMetric {
  const FollowUpSleepMetric({required this.label, required this.value});

  final String label;
  final String value;

  String get displayText => '$label：$value';
}

/// Presentation data shared by the in-App card, QR snapshot and PDF.
class FollowUpSleepSummaryViewModel {
  const FollowUpSleepSummaryViewModel({
    required this.trend,
    required this.recordedDays,
    required this.averageHours,
    required this.minimumHours,
    required this.maximumHours,
    required this.qualityDays,
    required this.averageQuality,
    required this.metrics,
  });

  final List<Map<String, dynamic>> trend;
  final int recordedDays;
  final double? averageHours;
  final double? minimumHours;
  final double? maximumHours;
  final int qualityDays;
  final double? averageQuality;
  final List<FollowUpSleepMetric> metrics;

  List<String> get displayItems =>
      metrics.map((metric) => metric.displayText).toList(growable: false);

  factory FollowUpSleepSummaryViewModel.fromData(
    Map<String, dynamic> sleep, {
    List<Map<String, dynamic>>? sleepTrend,
  }) {
    final duration = _map(sleep['durationHours']);
    final quality = _map(sleep['quality']);
    final naps = _map(sleep['naps']);
    final conditions = _list(sleep['conditions']);
    final trend = sleepTrend ?? _list(duration['dailyTrend']);
    final recordedDays = _integer(duration['recordedDays']);
    final average = _number(duration['average']);
    final minimum = _number(duration['minimum']);
    final maximum = _number(duration['maximum']);
    final qualityDays = _integer(quality['recordedDays']);
    final averageQuality = _number(quality['average']);

    final conditionMetrics = <FollowUpSleepMetric>[];
    final seenConditions = <String>{};
    for (final condition in conditions) {
      final code = condition['code']?.toString().trim() ?? '';
      final label = condition['label']?.toString().trim() ?? '';
      final days = _integer(condition['occurrenceDays']);
      final key = code.isNotEmpty ? code : label;
      if (label.isEmpty || days <= 0 || !seenConditions.add(key)) continue;
      conditionMetrics.add(
        FollowUpSleepMetric(label: label, value: '$days 天'),
      );
    }

    // Old summaries predate the dynamic `conditions` array. These aliases are
    // read only as a compatibility fallback and never restrict new records.
    if (conditionMetrics.isEmpty) {
      const legacyConditions = <String, String>{
        'sleepOnsetDifficulty': '入睡困難',
        'earlyAwakening': '早醒',
        'nightInterruption': '睡眠中斷',
        'dreams': '多夢',
      };
      for (final entry in legacyConditions.entries) {
        final days = _integer(_map(sleep[entry.key])['occurrenceDays']);
        if (days > 0) {
          conditionMetrics.add(
            FollowUpSleepMetric(label: entry.value, value: '$days 天'),
          );
        }
      }
    }
    final napDays = _integer(naps['days']);

    String hours(double? value) =>
        value == null ? '無資料' : '${_compact(value)} 小時';
    final qualityValue = averageQuality == null
        ? '未填寫'
        : '${_compact(averageQuality)}/5（$qualityDays 天）';
    return FollowUpSleepSummaryViewModel(
      trend: trend,
      recordedDays: recordedDays,
      averageHours: average,
      minimumHours: minimum,
      maximumHours: maximum,
      qualityDays: qualityDays,
      averageQuality: averageQuality,
      metrics: [
        FollowUpSleepMetric(label: '有效紀錄', value: '$recordedDays 天'),
        FollowUpSleepMetric(label: '平均', value: hours(average)),
        FollowUpSleepMetric(label: '最短', value: hours(minimum)),
        FollowUpSleepMetric(label: '最長', value: hours(maximum)),
        FollowUpSleepMetric(label: '睡眠品質', value: qualityValue),
        ...conditionMetrics,
        if (napDays > 0) FollowUpSleepMetric(label: '小睡', value: '$napDays 天'),
      ],
    );
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
  static List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : const [];
  static double? _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  static int _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
  static String _compact(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
