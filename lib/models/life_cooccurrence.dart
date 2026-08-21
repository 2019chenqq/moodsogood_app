class LifeCooccurrencePattern {
  const LifeCooccurrencePattern({
    required this.leftLabel,
    required this.rightLabel,
    required this.sameDayCount,
    required this.nearTimeCount,
  });

  final String leftLabel;
  final String rightLabel;
  final int sameDayCount;
  final int nearTimeCount;

  String get pairLabel => '$leftLabel + $rightLabel';
}
