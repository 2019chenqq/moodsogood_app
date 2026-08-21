class LifeTimelineType {
  static const dailyCheckIn = 'dailyCheckIn';
  static const quickRecord = 'quickRecord';
  static const emotion = 'emotion';
  static const symptom = 'symptom';
  static const sleep = 'sleep';
  static const diary = 'diary';
  static const period = 'period';
  static const activity = 'activity';
  static const medication = 'medication';
  static const subjectiveMedicationResponse = 'subjectiveMedicationResponse';

  static const values = <String>{
    dailyCheckIn,
    quickRecord,
    emotion,
    symptom,
    sleep,
    diary,
    period,
    activity,
    medication,
    subjectiveMedicationResponse,
  };

  const LifeTimelineType._();
}

/// A source-backed event on a single-day life timeline.
///
/// [time] is always present so consumers can sort items. When
/// [hasExplicitTime] is false it is only the normalized calendar date; UI must
/// not render it as an exact event time.
class LifeTimelineItem {
  const LifeTimelineItem({
    required this.time,
    required this.type,
    required this.title,
    required this.summary,
    this.sourceId,
    this.metadata,
    this.hasExplicitTime = true,
  }) : assert(type != '');

  final DateTime time;
  final String type;
  final String title;
  final String summary;
  final String? sourceId;
  final Map<String, dynamic>? metadata;
  final bool hasExplicitTime;
}
