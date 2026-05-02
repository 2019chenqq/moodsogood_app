class CalendarDaySummary {
  final DateTime date;
  final bool hasDailyRecord;
  final bool hasDiary;
  final bool hasEmotionData;
  final bool hasSymptomData;
  final bool hasSleepData;
  final bool isPeriodDay;
  final bool isPredictedPeriodDay;
  final double? averageMood;

  // Daily record details
  final List<String> emotionNames;
  final List<String> symptomNames;
  final double? sleepHours;
  final String? sleepQuality;
  final String? dailyRecordDocId;

  // Diary details
  final String? diaryDocId;
  final String? diaryTitle;
  final String? diaryContent;
  final String? diarySummary;

  // Period details
  final String? periodNote;

  // Insight / AI
  final List<String> ruleInsights;
  final String? aiFeedback;

  const CalendarDaySummary({
    required this.date,
    this.hasDailyRecord = false,
    this.hasDiary = false,
    this.hasEmotionData = false,
    this.hasSymptomData = false,
    this.hasSleepData = false,
    this.isPeriodDay = false,
    this.isPredictedPeriodDay = false,
    this.averageMood,
    this.emotionNames = const <String>[],
    this.symptomNames = const <String>[],
    this.sleepHours,
    this.sleepQuality,
    this.dailyRecordDocId,
    this.diaryDocId,
    this.diaryTitle,
    this.diaryContent,
    this.diarySummary,
    this.periodNote,
    this.ruleInsights = const <String>[],
    this.aiFeedback,
  });

  factory CalendarDaySummary.empty(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return CalendarDaySummary(date: normalized);
  }

  CalendarDaySummary copyWith({
    DateTime? date,
    bool? hasDailyRecord,
    bool? hasDiary,
    bool? hasEmotionData,
    bool? hasSymptomData,
    bool? hasSleepData,
    bool? isPeriodDay,
    bool? isPredictedPeriodDay,
    double? averageMood,
    List<String>? emotionNames,
    List<String>? symptomNames,
    double? sleepHours,
    String? sleepQuality,
    String? dailyRecordDocId,
    String? diaryDocId,
    String? diaryTitle,
    String? diaryContent,
    String? diarySummary,
    String? periodNote,
    List<String>? ruleInsights,
    String? aiFeedback,
    bool clearAverageMood = false,
    bool clearSleepHours = false,
    bool clearSleepQuality = false,
    bool clearDailyRecordDocId = false,
    bool clearDiaryDocId = false,
    bool clearDiaryTitle = false,
    bool clearDiaryContent = false,
    bool clearDiarySummary = false,
    bool clearPeriodNote = false,
    bool clearAiFeedback = false,
  }) {
    return CalendarDaySummary(
      date: date ?? this.date,
      hasDailyRecord: hasDailyRecord ?? this.hasDailyRecord,
      hasDiary: hasDiary ?? this.hasDiary,
      hasEmotionData: hasEmotionData ?? this.hasEmotionData,
      hasSymptomData: hasSymptomData ?? this.hasSymptomData,
      hasSleepData: hasSleepData ?? this.hasSleepData,
      isPeriodDay: isPeriodDay ?? this.isPeriodDay,
      isPredictedPeriodDay: isPredictedPeriodDay ?? this.isPredictedPeriodDay,
      averageMood: clearAverageMood ? null : (averageMood ?? this.averageMood),
      emotionNames: emotionNames ?? this.emotionNames,
      symptomNames: symptomNames ?? this.symptomNames,
      sleepHours: clearSleepHours ? null : (sleepHours ?? this.sleepHours),
      sleepQuality: clearSleepQuality ? null : (sleepQuality ?? this.sleepQuality),
      dailyRecordDocId:
          clearDailyRecordDocId ? null : (dailyRecordDocId ?? this.dailyRecordDocId),
      diaryDocId: clearDiaryDocId ? null : (diaryDocId ?? this.diaryDocId),
      diaryTitle: clearDiaryTitle ? null : (diaryTitle ?? this.diaryTitle),
      diaryContent: clearDiaryContent ? null : (diaryContent ?? this.diaryContent),
      diarySummary: clearDiarySummary ? null : (diarySummary ?? this.diarySummary),
      periodNote: clearPeriodNote ? null : (periodNote ?? this.periodNote),
      ruleInsights: ruleInsights ?? this.ruleInsights,
      aiFeedback: clearAiFeedback ? null : (aiFeedback ?? this.aiFeedback),
    );
  }

  String get dateKey {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
