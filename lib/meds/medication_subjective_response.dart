enum MedicationOverallResponse { better, worse, mixed, noChange, unsure }

enum MedicationPerceivedRelation {
  veryLikely,
  likely,
  unsure,
  unlikely,
  veryUnlikely,
}

/// A user's subjective report for one follow-up point after one medication
/// change. This is a record of perception only; it does not represent a
/// clinical effectiveness, causality, or adverse-effect assessment.
class MedicationSubjectiveResponse {
  static const Set<int> allowedFollowUpDays = {3, 7, 14, 28};

  MedicationSubjectiveResponse({
    required String id,
    required String medicationId,
    required String medicationName,
    required String changeRecordId,
    required this.changeDate,
    required int followUpDay,
    required this.recordedAt,
    required this.overallResponse,
    required List<String> changedAreas,
    required this.perceivedRelation,
    required List<String> otherFactors,
    this.note = '',
  }) : id = _requiredText(id, 'id'),
       medicationId = _requiredText(medicationId, 'medicationId'),
       medicationName = _requiredText(medicationName, 'medicationName'),
       changeRecordId = _requiredText(changeRecordId, 'changeRecordId'),
       followUpDay = _followUpDay(followUpDay),
       changedAreas = List.unmodifiable(changedAreas),
       otherFactors = List.unmodifiable(otherFactors);

  final String id;
  final String medicationId;
  final String medicationName;
  final String changeRecordId;
  final DateTime changeDate;
  final int followUpDay;
  final DateTime recordedAt;
  final MedicationOverallResponse overallResponse;
  final List<String> changedAreas;
  final MedicationPerceivedRelation perceivedRelation;
  final List<String> otherFactors;
  final String note;

  Map<String, dynamic> toMap() => {
    'id': id,
    'medicationId': medicationId,
    'medicationName': medicationName,
    'changeRecordId': changeRecordId,
    'changeDate': changeDate.toIso8601String(),
    'followUpDay': followUpDay,
    'recordedAt': recordedAt.toIso8601String(),
    'overallResponse': overallResponse.name,
    'changedAreas': changedAreas,
    'perceivedRelation': perceivedRelation.name,
    'otherFactors': otherFactors,
    'note': note,
  };

  factory MedicationSubjectiveResponse.fromMap(Map<String, dynamic> map) {
    return MedicationSubjectiveResponse(
      id: map['id']?.toString() ?? '',
      medicationId: map['medicationId']?.toString() ?? '',
      medicationName: map['medicationName']?.toString() ?? '',
      changeRecordId: map['changeRecordId']?.toString() ?? '',
      changeDate: _date(map['changeDate'], 'changeDate'),
      followUpDay: _integer(map['followUpDay'], 'followUpDay'),
      recordedAt: _date(map['recordedAt'], 'recordedAt'),
      overallResponse: _enumByName(
        MedicationOverallResponse.values,
        map['overallResponse'],
        'overallResponse',
      ),
      changedAreas: _strings(map['changedAreas']),
      perceivedRelation: _enumByName(
        MedicationPerceivedRelation.values,
        map['perceivedRelation'],
        'perceivedRelation',
      ),
      otherFactors: _strings(map['otherFactors']),
      note: map['note']?.toString() ?? '',
    );
  }

  static String _requiredText(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw FormatException('$field must not be empty');
    return trimmed;
  }

  static int _followUpDay(int value) {
    if (!allowedFollowUpDays.contains(value)) {
      throw ArgumentError.value(
        value,
        'followUpDay',
        'must be 3, 7, 14, or 28',
      );
    }
    return value;
  }

  static int _integer(dynamic value, String field) {
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) throw FormatException('$field must be an integer');
    return parsed;
  }

  static DateTime _date(dynamic value, String field) {
    if (value is DateTime) return value;
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) throw FormatException('$field must be a valid date');
    return parsed;
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    dynamic value,
    String field,
  ) {
    final name = value?.toString();
    for (final candidate in values) {
      if (candidate.name == name) return candidate;
    }
    throw FormatException('Invalid $field: $name');
  }

  static List<String> _strings(dynamic value) {
    if (value is! Iterable) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
