class LocalRecord {
  LocalRecord({
    this.id = '',
    required this.date,
    this.overallMood,
    this.note,
    this.updatedAt,
  });

  String id;
  DateTime date;
  double? overallMood;
  String? note;
  DateTime? updatedAt;
}
