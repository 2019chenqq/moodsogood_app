import 'package:cloud_firestore/cloud_firestore.dart';

import 'follow_up_sleep_summary_view_model.dart';

/// V0 contract between the follow-up summary UI/data layer and a future AI
/// summarization service.
///
/// The contract intentionally contains observations only. Diagnostic labels,
/// mood-episode classifications, and medication causality are outside its
/// scope.
class FollowUpAiInput {
  const FollowUpAiInput({
    required this.statistics,
    required this.sleep,
    required this.wellbeingTrends,
    required this.commonSymptoms,
    required this.bodyMeasurements,
    required this.medicationAdjustments,
    required this.discussionSelection,
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final FollowUpStatistics statistics;
  final SleepSummaryInput sleep;
  final WellbeingTrendsInput wellbeingTrends;
  final List<SymptomSummaryInput> commonSymptoms;
  final List<BodyMeasurementChangeInput> bodyMeasurements;
  final List<MedicationDoseChangeInput> medicationAdjustments;
  final DiscussionSelectionInput discussionSelection;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'statistics': statistics.toJson(),
        'sleep': sleep.toJson(),
        'wellbeingTrends': wellbeingTrends.toJson(),
        'commonSymptoms': commonSymptoms.map((item) => item.toJson()).toList(),
        'bodyMeasurements':
            bodyMeasurements.map((item) => item.toJson()).toList(),
        'medicationAdjustments':
            medicationAdjustments.map((item) => item.toJson()).toList(),
        'discussionSelection': discussionSelection.toJson(),
      };
}

class FollowUpStatistics {
  const FollowUpStatistics({
    required this.periodStart,
    required this.periodEnd,
    required this.validRecordDays,
    this.previousAppointmentDate,
    this.currentAppointmentDate,
    this.periodBasis = 'recordRange',
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final int validRecordDays;
  final DateTime? previousAppointmentDate;
  final DateTime? currentAppointmentDate;
  final String periodBasis;

  Map<String, dynamic> toJson() => {
        'periodStart': _date(periodStart),
        'periodEnd': _date(periodEnd),
        'validRecordDays': validRecordDays,
        'periodBasis': periodBasis,
        'previousAppointmentDate': previousAppointmentDate == null
            ? null
            : _date(previousAppointmentDate!),
        'currentAppointmentDate': currentAppointmentDate == null
            ? null
            : _date(currentAppointmentDate!),
      };
}

class SleepSummaryInput {
  const SleepSummaryInput({
    required this.averageHours,
    required this.minimumHours,
    required this.maximumHours,
    required this.abnormalFlags,
    required this.dailyTrend,
  });

  final double? averageHours;
  final double? minimumHours;
  final double? maximumHours;
  final List<SleepAbnormalFlagInput> abnormalFlags;
  final List<DatedMetricValue> dailyTrend;

  Map<String, dynamic> toJson() => {
        'averageHours': averageHours,
        'range': {'minimumHours': minimumHours, 'maximumHours': maximumHours},
        'abnormalFlags': abnormalFlags.map((item) => item.toJson()).toList(),
        'dailyTrend': dailyTrend.map((item) => item.toJson()).toList(),
      };
}

class SleepAbnormalFlagInput {
  const SleepAbnormalFlagInput({
    required this.code,
    required this.label,
    this.dates = const [],
  });

  final String code;
  final String label;
  final List<DateTime> dates;

  Map<String, dynamic> toJson() => {
        'code': code,
        'label': label,
        'dates': dates.map(_date).toList(),
      };
}

class DatedMetricValue {
  const DatedMetricValue({required this.date, required this.value});

  final DateTime date;
  final double value;

  Map<String, dynamic> toJson() => {'date': _date(date), 'value': value};
}

class WellbeingTrendsInput {
  const WellbeingTrendsInput({
    required this.mood,
    required this.anxiety,
    required this.energy,
    required this.appetite,
    required this.activity,
  });

  final MetricTrendInput mood;
  final MetricTrendInput anxiety;
  final MetricTrendInput energy;
  final MetricTrendInput appetite;
  final MetricTrendInput activity;

  Map<String, dynamic> toJson() => {
        'mood': mood.toJson(),
        'anxiety': anxiety.toJson(),
        'energy': energy.toJson(),
        'appetite': appetite.toJson(),
        'activity': activity.toJson(),
      };
}

class MetricTrendInput {
  const MetricTrendInput({
    required this.dailyValues,
    this.direction = TrendDirection.insufficientData,
  });

  final List<DatedMetricValue> dailyValues;
  final TrendDirection direction;

  Map<String, dynamic> toJson() => {
        'direction': direction.name,
        'dailyValues': dailyValues.map((item) => item.toJson()).toList(),
      };
}

enum TrendDirection {
  increasing,
  decreasing,
  stable,
  fluctuating,
  insufficientData
}

class SymptomSummaryInput {
  const SymptomSummaryInput({
    required this.name,
    required this.occurrenceDays,
    required this.averageSeverity,
  });

  final String name;
  final int occurrenceDays;
  final double averageSeverity;

  Map<String, dynamic> toJson() => {
        'name': name,
        'occurrenceDays': occurrenceDays,
        'averageSeverity': averageSeverity,
      };
}

class BodyMeasurementChangeInput {
  const BodyMeasurementChangeInput({
    required this.name,
    required this.unit,
    required this.startValue,
    required this.latestValue,
    required this.change,
  });

  final String name;
  final String unit;
  final double startValue;
  final double latestValue;
  final double change;

  Map<String, dynamic> toJson() => {
        'name': name,
        'unit': unit,
        'startValue': startValue,
        'latestValue': latestValue,
        'change': change,
      };
}

class MedicationDoseChangeInput {
  const MedicationDoseChangeInput({
    required this.medicationName,
    required this.adjustedAt,
    required this.beforeDose,
    required this.afterDose,
  });

  final String medicationName;
  final DateTime adjustedAt;
  final DoseInput? beforeDose;
  final DoseInput? afterDose;

  Map<String, dynamic> toJson() => {
        'medicationName': medicationName,
        'adjustedAt': adjustedAt.toUtc().toIso8601String(),
        'beforeDose': beforeDose?.toJson(),
        'afterDose': afterDose?.toJson(),
      };
}

class DoseInput {
  const DoseInput({required this.value, required this.unit, this.schedule});

  final double value;
  final String unit;
  final String? schedule;

  Map<String, dynamic> toJson() => {
        'value': value,
        'unit': unit,
        if (schedule != null) 'schedule': schedule,
      };
}

class DiscussionSelectionInput {
  const DiscussionSelectionInput({
    required this.topics,
    this.details = '',
  });

  final List<String> topics;
  final String details;

  Map<String, dynamic> toJson() => {'topics': topics, 'details': details};
}

class FollowUpDiscussionTopicInput {
  const FollowUpDiscussionTopicInput({
    required this.type,
    required this.label,
    required this.selected,
    this.note = '',
  });

  final String type;
  final String label;
  final bool selected;
  final String note;

  Map<String, dynamic> toJson() => {
        'type': type,
        'label': label,
        'selected': selected,
        'note': note,
      };
}

/// V1 input is deliberately assembled by the app. The AI receives computed
/// observations instead of raw records, so it never needs to calculate dates,
/// averages, counts, or dose differences itself.
class FollowUpAiV1Input {
  const FollowUpAiV1Input({
    required this.statistics,
    required this.discussionTopics,
    required this.discussionDetails,
    required this.additionalNotes,
    required this.wellbeingTrends,
    required this.sleep,
    required this.highFrequencySymptoms,
    required this.bodyMeasurements,
    required this.currentMedications,
    required this.medicationTimeline,
    required this.dataLimitations,
    this.diaryContext = const [],
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final FollowUpStatistics statistics;
  final List<FollowUpDiscussionTopicInput> discussionTopics;
  final String discussionDetails;
  final String additionalNotes;
  final WellbeingTrendsInput wellbeingTrends;
  final Map<String, dynamic> sleep;
  final List<Map<String, dynamic>> highFrequencySymptoms;
  final List<Map<String, dynamic>> bodyMeasurements;
  final List<Map<String, dynamic>> currentMedications;
  final List<Map<String, dynamic>> medicationTimeline;
  final List<String> dataLimitations;
  final List<Map<String, dynamic>> diaryContext;

  FollowUpAiV1Input copyWith({
    String? discussionDetails,
    String? additionalNotes,
    List<Map<String, dynamic>>? diaryContext,
  }) =>
      FollowUpAiV1Input(
        schemaVersion: schemaVersion,
        statistics: statistics,
        discussionTopics: discussionTopics,
        discussionDetails: discussionDetails ?? this.discussionDetails,
        additionalNotes: additionalNotes ?? this.additionalNotes,
        wellbeingTrends: wellbeingTrends,
        sleep: sleep,
        highFrequencySymptoms: highFrequencySymptoms,
        bodyMeasurements: bodyMeasurements,
        currentMedications: currentMedications,
        medicationTimeline: medicationTimeline,
        dataLimitations: dataLimitations,
        diaryContext: diaryContext ?? this.diaryContext,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'statistics': statistics.toJson(),
        'discussionTopics':
            discussionTopics.map((topic) => topic.toJson()).toList(),
        'discussionDetails': discussionDetails,
        'additionalNotes': additionalNotes,
        'wellbeingTrends': wellbeingTrends.toJson(),
        'sleep': sleep,
        'highFrequencySymptoms': highFrequencySymptoms,
        'bodyMeasurements': bodyMeasurements,
        'currentMedications': currentMedications,
        'medicationTimeline': medicationTimeline,
        'dataLimitations': dataLimitations,
        if (diaryContext.isNotEmpty) 'diaryContext': diaryContext,
      };
}

class FollowUpDiaryHighlight {
  const FollowUpDiaryHighlight({
    required this.date,
    required this.category,
    required this.summary,
    this.source = 'diary',
  });

  final String date;
  final String category;
  final String summary;
  final String source;

  Map<String, dynamic> toJson() => {
        'date': date,
        'category': category,
        'summary': summary,
        'source': source,
      };

  factory FollowUpDiaryHighlight.fromJson(Map<String, dynamic> json) =>
      FollowUpDiaryHighlight(
        date: (json['date'] ?? '').toString().trim(),
        category: (json['category'] ?? '').toString().trim(),
        summary: (json['summary'] ?? '').toString().trim(),
        source: (json['source'] ?? 'diary').toString().trim(),
      );
}

/// Response shape reserved for the future AI integration.
class FollowUpAiOutput {
  const FollowUpAiOutput({
    required this.keyChanges,
    required this.timelineRelations,
    required this.discussionPriorities,
    this.discussionItems = const [],
    this.followUpResponses = const [],
    this.userSharedNotes = const [],
    this.userReportedConcerns = const [],
    this.diaryHighlights = const [],
    required this.dataLimitations,
    required this.generatedAt,
    this.usedFallback = false,
  });

  final List<String> keyChanges;
  final List<String> timelineRelations;
  final List<String> discussionPriorities;
  final List<String> discussionItems;

  /// App-owned question/answer pairs from the pre-summary clarification step.
  /// These are preserved verbatim instead of relying on the model to repeat
  /// them in another output field.
  final List<Map<String, String>> followUpResponses;

  /// User-authored free-form notes. Kept separate from observed health data.
  final List<String> userSharedNotes;

  /// Legacy transport/storage field. New UI must use [userSharedNotes].
  final List<String> userReportedConcerns;
  final List<FollowUpDiaryHighlight> diaryHighlights;
  final List<String> dataLimitations;
  final DateTime generatedAt;
  final bool usedFallback;

  Map<String, dynamic> toJson() => {
        'keyChanges': keyChanges,
        'timelineRelations': timelineRelations,
        'discussionPriorities': discussionPriorities,
        'discussionItems': discussionItems,
        'followUpResponses': followUpResponses,
        'userSharedNotes': userSharedNotes,
        'userReportedConcerns': userReportedConcerns,
        'diaryHighlights':
            diaryHighlights.map((item) => item.toJson()).toList(),
        'dataLimitations': dataLimitations,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'usedFallback': usedFallback,
      };

  factory FollowUpAiOutput.fromJson(Map<String, dynamic> json) {
    final keyChanges = _strings(json['keyChanges']);
    if (keyChanges.length < 3 || keyChanges.length > 5) {
      throw const FormatException('keyChanges must contain 3 to 5 items');
    }
    return FollowUpAiOutput(
      keyChanges: keyChanges,
      timelineRelations: _strings(json['timelineRelations']),
      discussionPriorities: _strings(json['discussionPriorities']),
      discussionItems: _strings(json['discussionItems']),
      followUpResponses: _questionAnswers(json['followUpResponses']),
      userSharedNotes: _strings(json['userSharedNotes']),
      userReportedConcerns: _strings(json['userReportedConcerns']),
      diaryHighlights: _diaryHighlights(json['diaryHighlights']),
      dataLimitations: _strings(json['dataLimitations']),
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      usedFallback: json['usedFallback'] == true,
    );
  }
}

class FollowUpSummaryRecord {
  const FollowUpSummaryRecord({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
    required this.appointmentDate,
    required this.periodStart,
    required this.periodEnd,
    required this.validRecordDays,
    required this.selectedTopics,
    required this.discussionDetails,
    required this.additionalNotes,
    required this.aiOutput,
    required this.sleepSummary,
    required this.sleepTrend,
    required this.medicationTimeline,
    this.highFrequencySymptoms = const [],
    this.bodyMeasurements = const [],
    this.schemaVersion = 1,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime confirmedAt;
  final DateTime? appointmentDate;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int validRecordDays;
  final List<Map<String, dynamic>> selectedTopics;
  final String discussionDetails;
  final String additionalNotes;
  final FollowUpAiOutput aiOutput;
  final Map<String, dynamic> sleepSummary;
  final List<Map<String, dynamic>> sleepTrend;
  final List<Map<String, dynamic>> medicationTimeline;
  final List<Map<String, dynamic>> highFrequencySymptoms;
  final List<Map<String, dynamic>> bodyMeasurements;
  final int schemaVersion;

  Map<String, dynamic> toMap() => {
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'confirmedAt': confirmedAt,
        'appointmentDate': appointmentDate,
        'periodStart': periodStart,
        'periodEnd': periodEnd,
        'validRecordDays': validRecordDays,
        'selectedTopics': selectedTopics,
        'discussionDetails': discussionDetails,
        'additionalNotes': additionalNotes,
        'aiOutput': aiOutput.toJson(),
        'sleepSummary': sleepSummary,
        'sleepTrend': sleepTrend,
        'medicationTimeline': medicationTimeline,
        'highFrequencySymptoms': highFrequencySymptoms,
        'bodyMeasurements': bodyMeasurements,
        'schemaVersion': schemaVersion,
      };

  Map<String, dynamic> toDeidentifiedSnapshot({
    FollowUpSummaryShareOptions options = FollowUpSummaryShareOptions.all,
  }) {
    final display = FollowUpSummaryDisplayModel.fromRecord(
      this,
      options: options,
    );
    // The filtered legacy fields keep newly-generated shares readable while
    // Functions/Hosting are rolling between versions. They contain only the
    // categories the user explicitly selected; the current backend stores
    // only `display`.
    return {
      'appointmentDate': appointmentDate?.toIso8601String(),
      'periodStart': periodStart.toIso8601String(),
      'periodEnd': periodEnd.toIso8601String(),
      'validRecordDays': validRecordDays,
      'selectedTopics': options.discussionTopics ? selectedTopics : const [],
      'discussionDetails': options.discussionTopics ? discussionDetails : '',
      'additionalNotes': options.lifeUpdates ? additionalNotes : '',
      'aiOutput': {
        'keyChanges': display.keyChanges,
        'discussionItems': options.discussionTopics
            ? display.discussionItems
            : const <String>[],
        'diaryHighlights': options.lifeUpdates
            ? aiOutput.diaryHighlights.map((item) => item.toJson()).toList()
            : const [],
        'userSharedNotes': display.userSharedNotes,
        'userReportedConcerns': display.userSharedNotes,
        'dataLimitations': display.dataLimitations,
        'generatedAt': aiOutput.generatedAt.toUtc().toIso8601String(),
      },
      'sleepSummary': options.sleep ? sleepSummary : const {},
      'sleepTrend': options.sleep ? sleepTrend : const [],
      'medicationTimeline':
          options.medicationAdjustments ? medicationTimeline : const [],
      'highFrequencySymptoms':
          options.emotionsAndSymptoms ? highFrequencySymptoms : const [],
      'bodyMeasurements': options.bodyMeasurements ? bodyMeasurements : const [],
      'schemaVersion': schemaVersion,
      'display': display.toJson(),
    };
  }

  FollowUpSummaryRecord copyWith({
    FollowUpAiOutput? aiOutput,
    String? discussionDetails,
    String? additionalNotes,
    DateTime? updatedAt,
  }) =>
      FollowUpSummaryRecord(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        confirmedAt: confirmedAt,
        appointmentDate: appointmentDate,
        periodStart: periodStart,
        periodEnd: periodEnd,
        validRecordDays: validRecordDays,
        selectedTopics: selectedTopics,
        discussionDetails: discussionDetails ?? this.discussionDetails,
        additionalNotes: additionalNotes ?? this.additionalNotes,
        aiOutput: aiOutput ?? this.aiOutput,
        sleepSummary: sleepSummary,
        sleepTrend: sleepTrend,
        medicationTimeline: medicationTimeline,
        highFrequencySymptoms: highFrequencySymptoms,
        bodyMeasurements: bodyMeasurements,
        schemaVersion: schemaVersion,
      );

  factory FollowUpSummaryRecord.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final now = DateTime.now();
    return FollowUpSummaryRecord(
      id: id,
      createdAt: _dateTime(map['createdAt']) ?? now,
      updatedAt:
          _dateTime(map['updatedAt']) ?? _dateTime(map['createdAt']) ?? now,
      confirmedAt:
          _dateTime(map['confirmedAt']) ?? _dateTime(map['createdAt']) ?? now,
      appointmentDate: _dateTime(map['appointmentDate']),
      periodStart: _dateTime(map['periodStart']) ?? now,
      periodEnd: _dateTime(map['periodEnd']) ?? now,
      validRecordDays: (map['validRecordDays'] as num?)?.toInt() ?? 0,
      selectedTopics: _mapList(map['selectedTopics']),
      discussionDetails: (map['discussionDetails'] ?? '').toString(),
      additionalNotes: (map['additionalNotes'] ?? '').toString(),
      aiOutput: _safeAiOutput(map['aiOutput'], now),
      sleepSummary: _map(map['sleepSummary']),
      sleepTrend: _mapList(map['sleepTrend']),
      medicationTimeline: _mapList(map['medicationTimeline']),
      highFrequencySymptoms: _mapList(map['highFrequencySymptoms']),
      bodyMeasurements: _mapList(map['bodyMeasurements']),
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 0,
    );
  }
}

DateTime? _dateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<Map<String, dynamic>> _mapList(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
    : const [];

FollowUpAiOutput _safeAiOutput(dynamic value, DateTime fallbackDate) {
  final map = _map(value);
  return FollowUpAiOutput(
    keyChanges: _strings(map['keyChanges']),
    timelineRelations: _strings(map['timelineRelations']),
    discussionPriorities: _strings(map['discussionPriorities']),
    discussionItems: _strings(map['discussionItems']),
    followUpResponses: _questionAnswers(map['followUpResponses']),
    diaryHighlights: _diaryHighlights(map['diaryHighlights']),
    userSharedNotes: _strings(map['userSharedNotes']),
    userReportedConcerns: _strings(map['userReportedConcerns']),
    dataLimitations: _strings(map['dataLimitations']),
    generatedAt: _dateTime(map['generatedAt']) ?? fallbackDate,
    usedFallback: map['usedFallback'] == true,
  );
}

String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

List<String> _strings(dynamic value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

List<Map<String, String>> _questionAnswers(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => {
              'question': (item['question'] ?? '').toString().trim(),
              'answer': (item['answer'] ?? '').toString().trim(),
            })
        .where((item) =>
            item['question']!.isNotEmpty && item['answer']!.isNotEmpty)
        .toList(growable: false)
    : const [];

List<FollowUpDiaryHighlight> _diaryHighlights(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => FollowUpDiaryHighlight.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) =>
            item.date.isNotEmpty &&
            item.summary.isNotEmpty &&
            item.source == 'diary')
        .toList(growable: false)
    : const [];

/// Presentation-only normalization shared by App, PDF and QR snapshots.
/// It never writes punctuation back to Firestore.
class FollowUpSummaryTextFormatter {
  const FollowUpSummaryTextFormatter._();

  static String sentence(String value) {
    var text = value.trim().replaceFirst(RegExp(r'^[•・\-]\s*'), '');
    if (text.isEmpty) return '';
    final ending = RegExp(r'[。！？；]+$').firstMatch(text);
    if (ending != null) {
      final marks = ending.group(0)!;
      text =
          text.substring(0, ending.start) + marks.substring(marks.length - 1);
      return text;
    }
    return '$text。';
  }

  static String comparisonKey(String value) => value
      .trim()
      .replaceAll(RegExp(r'[\s。！？；，,.!?;]+'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();

  static List<String> sentences(Iterable<String> values) {
    final seen = <String>{};
    return values
        .expand((value) => value.split(RegExp(r'[\r\n]+')))
        .map(sentence)
        .where((item) => item.isNotEmpty)
        .where((item) => seen.add(comparisonKey(item)))
        .toList(growable: false);
  }

  static bool isQuestionAnswerTranscript(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    return RegExp(
      r'(AI\s*補問|使用者(?:原始)?回答|問題[一二三四五0-9]|(?:^|[\s　])問[：:]|(?:^|[\s　])答[：:]|回答[：:])',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static List<String> withoutQuestionAnswerTranscripts(
    Iterable<String> values,
  ) =>
      sentences(values)
          .where((item) => !isQuestionAnswerTranscript(item))
          .toList(growable: false);

  static List<String> preserveUserEnteredNotes(
    Iterable<String> preservedValues, {
    Iterable<String> derivedValues = const [],
  }) {
    final seen = <String>{};
    final items = <String>[];

    void append(
      Iterable<String> values, {
      required bool filterQuestionAnswerTranscript,
    }) {
      for (final item in values
          .expand((value) => value.split(RegExp(r'[\r\n]+')))
          .map(sentence)
          .where((item) => item.isNotEmpty)) {
        if (filterQuestionAnswerTranscript &&
            isQuestionAnswerTranscript(item)) {
          continue;
        }
        if (seen.add(comparisonKey(item))) {
          items.add(item);
        }
      }
    }

    append(
      preservedValues,
      filterQuestionAnswerTranscript: false,
    );
    append(
      derivedValues,
      filterQuestionAnswerTranscript: true,
    );
    return items;
  }

  static List<String> safeDiscussionItems(Iterable<String> values) =>
      withoutQuestionAnswerTranscripts(values).take(5).toList(growable: false);
}

class FollowUpSummaryShareOptions {
  const FollowUpSummaryShareOptions({
    required this.discussionTopics,
    required this.sleep,
    required this.emotionsAndSymptoms,
    required this.medicationAdjustments,
    required this.lifeUpdates,
    required this.dataLimitations,
    required this.bodyMeasurements,
  });

  static const none = FollowUpSummaryShareOptions(
    discussionTopics: false,
    sleep: false,
    emotionsAndSymptoms: false,
    medicationAdjustments: false,
    lifeUpdates: false,
    dataLimitations: false,
    bodyMeasurements: false,
  );
  static const all = FollowUpSummaryShareOptions(
    discussionTopics: true,
    sleep: true,
    emotionsAndSymptoms: true,
    medicationAdjustments: true,
    lifeUpdates: true,
    dataLimitations: true,
    bodyMeasurements: true,
  );

  final bool discussionTopics;
  final bool sleep;
  final bool emotionsAndSymptoms;
  final bool medicationAdjustments;
  final bool lifeUpdates;
  final bool dataLimitations;
  final bool bodyMeasurements;

  bool get hasSelection =>
      discussionTopics ||
      sleep ||
      emotionsAndSymptoms ||
      medicationAdjustments ||
      lifeUpdates ||
      dataLimitations ||
      bodyMeasurements;

  FollowUpSummaryShareOptions copyWith({
    bool? discussionTopics,
    bool? sleep,
    bool? emotionsAndSymptoms,
    bool? medicationAdjustments,
    bool? lifeUpdates,
    bool? dataLimitations,
    bool? bodyMeasurements,
  }) =>
      FollowUpSummaryShareOptions(
        discussionTopics: discussionTopics ?? this.discussionTopics,
        sleep: sleep ?? this.sleep,
        emotionsAndSymptoms: emotionsAndSymptoms ?? this.emotionsAndSymptoms,
        medicationAdjustments:
            medicationAdjustments ?? this.medicationAdjustments,
        lifeUpdates: lifeUpdates ?? this.lifeUpdates,
        dataLimitations: dataLimitations ?? this.dataLimitations,
        bodyMeasurements: bodyMeasurements ?? this.bodyMeasurements,
      );
}

class FollowUpSummaryDisplayModel {
  const FollowUpSummaryDisplayModel({
    required this.visitInfo,
    required this.topicLabels,
    required this.discussionItems,
    required this.keyChanges,
    required this.timelineRelations,
    required this.symptoms,
    required this.bodyMeasurements,
    required this.userSharedNotes,
    required this.sleepSummaryItems,
    required this.sleepTrend,
    required this.medicationTimeline,
    required this.dataLimitations,
    required this.generatedAt,
    required this.includedSections,
  });

  final List<String> visitInfo;
  final List<String> topicLabels;
  final List<String> discussionItems;
  final List<String> keyChanges;
  final List<String> timelineRelations;
  final List<String> symptoms;
  final List<String> bodyMeasurements;
  final List<String> userSharedNotes;
  final List<String> sleepSummaryItems;
  final List<Map<String, dynamic>> sleepTrend;
  final List<String> medicationTimeline;
  final List<String> dataLimitations;
  final String generatedAt;
  final List<String> includedSections;

  factory FollowUpSummaryDisplayModel.fromRecord(
    FollowUpSummaryRecord record, {
    FollowUpSummaryShareOptions options = FollowUpSummaryShareOptions.all,
  }) {
    final output = record.aiOutput;
    final labels = record.selectedTopics
        .map((item) => item['label']?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
    final legacy = output.userSharedNotes.isEmpty
        ? output.userReportedConcerns
        : const <String>[];
    final notes = FollowUpSummaryTextFormatter.preserveUserEnteredNotes(
      [
        if (record.additionalNotes.trim().isNotEmpty) record.additionalNotes,
      ],
      derivedValues: [
        ...output.userSharedNotes,
        ...output.diaryHighlights.map(_formatDiaryHighlight),
        ...legacy.where((item) =>
            FollowUpSummaryTextFormatter.comparisonKey(item) ==
            FollowUpSummaryTextFormatter.comparisonKey(record.additionalNotes)),
      ],
    );
    final movedLegacy = legacy.where((item) {
      final key = FollowUpSummaryTextFormatter.comparisonKey(item);
      return key.isNotEmpty &&
          key !=
              FollowUpSummaryTextFormatter.comparisonKey(
                  record.additionalNotes) &&
          key !=
              FollowUpSummaryTextFormatter.comparisonKey(
                  record.discussionDetails);
    });
    return FollowUpSummaryDisplayModel(
      visitInfo: [
        '統計期間：${_displayDate(record.periodStart)}～${_displayDate(record.periodEnd)}',
        '有效紀錄天數：${record.validRecordDays} 天',
      ],
      topicLabels: options.discussionTopics ? labels : const [],
      discussionItems: options.discussionTopics
          ? FollowUpSummaryTextFormatter.safeDiscussionItems([
              if (record.discussionDetails.trim().isNotEmpty)
                record.discussionDetails,
              ...output.discussionItems,
              ...output.discussionPriorities,
            ])
          : const [],
      keyChanges: options.emotionsAndSymptoms
          ? _withoutMedicationTimelineDuplicates(
              record,
              _keyChangeItems(
                record,
                source: [...output.keyChanges, ...movedLegacy],
                includeBodyMeasurements: options.bodyMeasurements,
              ),
            ).take(5).toList(growable: false)
          : const [],
      // Kept in the view model only for wire compatibility. Renderers must
      // ignore legacy timeline relations.
      timelineRelations: const [],
      symptoms: options.emotionsAndSymptoms
          ? _symptomItems(record)
          : const [],
      bodyMeasurements:
          options.bodyMeasurements ? _bodyMeasurementItems(record) : const [],
      userSharedNotes: options.lifeUpdates ? notes : const [],
      sleepSummaryItems: options.sleep
          ? _sleepSummaryItems(
              record.sleepSummary,
              sleepTrend: record.sleepTrend,
            )
          : const [],
      sleepTrend: options.sleep ? record.sleepTrend : const [],
      medicationTimeline: options.medicationAdjustments
          ? FollowUpSummaryTextFormatter.sentences(
              record.medicationTimeline.map(_formatMedicationEvent),
            )
          : const [],
      dataLimitations: options.dataLimitations
          ? FollowUpSummaryTextFormatter.withoutQuestionAnswerTranscripts(
              output.dataLimitations,
            )
          : const [],
      generatedAt: _displayDateTime(output.generatedAt),
      includedSections: [
        if (options.discussionTopics) 'discussion',
        if (options.sleep) 'sleep',
        if (options.emotionsAndSymptoms) 'emotionsAndSymptoms',
        if (options.medicationAdjustments) 'medicationAdjustments',
        if (options.lifeUpdates) 'lifeUpdates',
        if (options.dataLimitations) 'dataLimitations',
        if (options.bodyMeasurements) 'bodyMeasurements',
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'visitInfo': visitInfo,
        'topicLabels': topicLabels,
        'discussionItems': discussionItems,
        'keyChanges': keyChanges,
        'timelineRelations': timelineRelations,
        'symptoms': symptoms,
        'bodyMeasurements': bodyMeasurements,
        'userSharedNotes': userSharedNotes,
        'sleepSummaryItems': sleepSummaryItems,
        'sleepTrend': sleepTrend,
        'medicationTimeline': medicationTimeline,
        'dataLimitations': dataLimitations,
        'generatedAt': generatedAt,
        'includedSections': includedSections,
        'disclaimer': '摘要僅供回診溝通參考，不取代醫師判斷。',
      };

  static List<String> _keyChangeItems(
    FollowUpSummaryRecord record, {
    required List<String> source,
    bool includeBodyMeasurements = true,
  }) {
    final duration = _map(record.sleepSummary['durationHours']);
    var values = source.where((item) => !item.contains('睡眠')).toList();
    
    // Always filter out body measurement values from key changes
    // Actual values should never appear in keyChanges, only in bodyMeasurements
    values = values.where((item) {
      // Remove items that contain body measurement data with actual values
      return !_isBodyMeasurementWithValues(item);
    }).toList();
    
    final comparison = _map(duration['comparison']);
    final change = comparison['change'] is num
        ? comparison['change'] as num
        : _sleepTrendChange(record.sleepTrend);
    if (change is num && change.abs() >= .4) {
      values.add(
        '睡眠時間較前期${change > 0 ? '增加' : '減少'}：${_compactNumber(change.abs())}小時',
      );
    }
    return FollowUpSummaryTextFormatter.withoutQuestionAnswerTranscripts(
      values,
    );
  }
  
  static bool _isBodyMeasurementWithValues(String text) {
    // Check if the text contains body measurement patterns with actual values
    // Patterns like: "體重：75kg → 74.5kg" or "體重從 75kg 變化到 74.5kg"
    final bodyMeasurementPattern = RegExp(
      r'(體重|體脂率|腰圍|body\s*weight|body\s*fat|waist)',
      caseSensitive: false,
    );
    
    if (!bodyMeasurementPattern.hasMatch(text)) {
      return false;
    }
    
    // If it mentions body measurement, check if it has actual numeric values
    final hasNumbers = RegExp(r'\d+\.?\d*\s*(kg|%|cm|公斤|公分|百分比)').hasMatch(text);
    return hasNumbers;
  }

  static List<String> _withoutMedicationTimelineDuplicates(
    FollowUpSummaryRecord record,
    List<String> keyChanges,
  ) {
    final medicationKeys = record.medicationTimeline
        .map(_formatMedicationEvent)
        .map(FollowUpSummaryTextFormatter.comparisonKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    return keyChanges
        .where((item) => !medicationKeys.contains(
              FollowUpSummaryTextFormatter.comparisonKey(item),
            ))
        .toList(growable: false);
  }

  static String _formatDiaryHighlight(FollowUpDiaryHighlight highlight) =>
      '${highlight.date}（來自日記）：${highlight.summary}';

  static num? _sleepTrendChange(List<Map<String, dynamic>> trend) {
    final values = trend
        .map((point) => point['value'])
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
    if (values.length < 3) return null;
    final half = values.length ~/ 2;
    double average(Iterable<double> items) =>
        items.reduce((a, b) => a + b) / items.length;
    final earlier = average(values.take(half));
    final recent = average(values.skip(half));
    return ((recent - earlier) * 100).round() / 100;
  }

  static String _compactNumber(num value) {
    final number = value.toDouble();
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number
        .toString()
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static List<String> _sleepSummaryItems(
    Map<String, dynamic> sleep, {
    List<Map<String, dynamic>>? sleepTrend,
  }) =>
      FollowUpSleepSummaryViewModel.fromData(
        sleep,
        sleepTrend: sleepTrend,
      ).displayItems;

  static List<String> _symptomItems(FollowUpSummaryRecord record) {
    String compact(dynamic value) {
      final number = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (number == null) return value?.toString().trim() ?? '';
      return number == number.roundToDouble()
          ? number.toInt().toString()
          : number.toStringAsFixed(1);
    }

    final symptoms = record.highFrequencySymptoms.take(5).map((symptom) {
      final name = symptom['name']?.toString().trim() ?? '';
      final days = (symptom['occurrenceDays'] as num?)?.toInt();
      final severity = symptom['averageSeverity'];
      return [
        name,
        if (days != null) '出現 $days 天',
        if (severity is num) '平均程度 ${compact(severity)}',
      ].where((part) => part.isNotEmpty).join('，');
    });

    return FollowUpSummaryTextFormatter.sentences(symptoms);
  }

  static List<String> _bodyMeasurementItems(FollowUpSummaryRecord record) {
    String compact(dynamic value) {
      final number = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (number == null) return value?.toString().trim() ?? '';
      return number == number.roundToDouble()
          ? number.toInt().toString()
          : number.toStringAsFixed(1);
    }

    final measurements = record.bodyMeasurements.map((measurement) {
      final name = measurement['name']?.toString().trim() ?? '';
      final unit = measurement['unit']?.toString().trim() ?? '';
      final change = compact(measurement['change']);
      if (name.isEmpty) return '';
      final changeNum = double.tryParse(change);
      if (changeNum == null || changeNum == 0) {
        return '$name：無明顯變化';
      }
      final direction = changeNum > 0 ? '增加' : '減少';
      final absChange = changeNum.abs().toString();
      return '$name：$direction $absChange$unit';
    });

    return FollowUpSummaryTextFormatter.sentences(measurements);
  }

  static String _formatMedicationEvent(Map<String, dynamic> event) {
    final date = event['date']?.toString().trim() ?? '';
    final name = event['medicationName']?.toString().trim() ?? '';
    final prefix = [date, name].where((part) => part.isNotEmpty).join(' ');
    final type = event['type']?.toString().trim() ?? '';
    final beforeDose = _dose(event['beforeDose']);
    final afterDose = _dose(event['afterDose']);
    final rawBeforeUnit = event['beforeUnit']?.toString().trim() ?? '';
    final rawAfterUnit = event['afterUnit']?.toString().trim() ?? '';
    final beforeUnit = rawBeforeUnit.isEmpty ? rawAfterUnit : rawBeforeUnit;
    final afterUnit = rawAfterUnit.isEmpty ? rawBeforeUnit : rawAfterUnit;
    final beforeTimes = _strings(event['beforeTimes']).join('、');
    final afterTimes = _strings(event['afterTimes']).join('、');

    String doseWithUnit(String? dose, String unit) =>
        dose == null ? '' : '$dose${unit.isEmpty ? '' : ' $unit'}';
    String doseChange(String label) {
      final before = doseWithUnit(beforeDose, beforeUnit);
      final after = doseWithUnit(afterDose, afterUnit);
      if (before.isNotEmpty && after.isNotEmpty && before != after) {
        return '$label：$before → $after';
      }
      final value = after.isNotEmpty ? after : before;
      return value.isEmpty ? label : '劑量：$value';
    }

    final detail = switch (type) {
      'scheduleChanged' => beforeTimes.isNotEmpty &&
              afterTimes.isNotEmpty &&
              beforeTimes != afterTimes
          ? '服藥時間：$beforeTimes → $afterTimes'
          : (afterTimes.isNotEmpty || beforeTimes.isNotEmpty)
              ? '服藥時間：${afterTimes.isNotEmpty ? afterTimes : beforeTimes}'
              : '服藥時間調整',
      'added' => afterDose == null
          ? '新增'
          : '新增，劑量 ${doseWithUnit(afterDose, afterUnit)}',
      'increased' => doseChange('劑量增加'),
      'decreased' => doseChange('劑量減少'),
      'doseChanged' => doseChange('劑量調整'),
      'stopped' => '停用',
      'resumed' => afterDose == null
          ? '恢復使用'
          : '恢復使用，劑量 ${doseWithUnit(afterDose, afterUnit)}',
      _ => type,
    };
    return [prefix, detail].where((part) => part.isNotEmpty).join('：');
  }

  static String? _dose(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().trim() ?? '');
    if (number == null) return null;
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  static String _displayDate(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  static String _displayDateTime(DateTime value) {
    final local = value.toLocal();
    return '${_displayDate(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
