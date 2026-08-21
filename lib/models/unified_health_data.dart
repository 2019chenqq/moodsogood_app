enum UnifiedHealthDataSource {
  legacyDailyRecord,
  healthEvent,
  dailyCheckIn,
}

enum UnifiedHealthDataPrecision { day, timestamp }

class UnifiedScoredValue {
  const UnifiedScoredValue({required this.name, this.value});

  final String name;
  final int? value;

  @override
  bool operator ==(Object other) =>
      other is UnifiedScoredValue && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

class UnifiedHealthData {
  const UnifiedHealthData({
    required this.source,
    required this.precision,
    required this.date,
    this.timestamp,
    this.emotions = const [],
    this.symptoms = const [],
    this.stateChanges = const {},
    this.overallMood,
    this.healthStatus,
    this.sourceId,
    this.sleepFlags = const [],
    this.sleepQuality,
  }) : assert(
          precision != UnifiedHealthDataPrecision.day || timestamp == null,
          'Day-precision data must not contain a synthetic timestamp.',
        );

  final UnifiedHealthDataSource source;
  final UnifiedHealthDataPrecision precision;
  final DateTime date;
  final DateTime? timestamp;
  final List<UnifiedScoredValue> emotions;
  final List<UnifiedScoredValue> symptoms;
  final Map<String, int> stateChanges;
  final double? overallMood;
  final int? healthStatus;
  final String? sourceId;
  final List<String> sleepFlags;
  final int? sleepQuality;

  String get dateKey => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  UnifiedHealthData copyWith({
    List<UnifiedScoredValue>? emotions,
    List<UnifiedScoredValue>? symptoms,
    Map<String, int>? stateChanges,
    double? overallMood,
    bool clearOverallMood = false,
    int? healthStatus,
    bool clearHealthStatus = false,
    String? sourceId,
    List<String>? sleepFlags,
    int? sleepQuality,
  }) {
    return UnifiedHealthData(
      source: source,
      precision: precision,
      date: date,
      timestamp: timestamp,
      emotions: emotions ?? this.emotions,
      symptoms: symptoms ?? this.symptoms,
      stateChanges: stateChanges ?? this.stateChanges,
      overallMood: clearOverallMood ? null : overallMood ?? this.overallMood,
      healthStatus:
          clearHealthStatus ? null : healthStatus ?? this.healthStatus,
      sourceId: sourceId ?? this.sourceId,
      sleepFlags: sleepFlags ?? this.sleepFlags,
      sleepQuality: sleepQuality ?? this.sleepQuality,
    );
  }
}
