enum MedicationTrackingChangeType {
  added,
  doseIncreased,
  doseDecreased,
  resumed,
}

class MedicationSubjectiveTrackingCycle {
  static const List<int> followUpDays = [3, 7, 14, 28];

  MedicationSubjectiveTrackingCycle({
    required String id,
    required String medicationId,
    required String changeRecordId,
    required this.changeDate,
    required String medicationName,
    required this.changeType,
    this.oldDose,
    this.newDose,
    this.doseUnit,
    required this.active,
    DateTime? endedAt,
    this.endReason,
    this.supersededByChangeRecordId,
  })  : id = _requiredText(id, 'id'),
        medicationId = _requiredText(medicationId, 'medicationId'),
        changeRecordId = _requiredText(changeRecordId, 'changeRecordId'),
        medicationName = _requiredText(medicationName, 'medicationName'),
        endedAt = active ? null : endedAt;

  final String id;
  final String medicationId;
  final String changeRecordId;
  final DateTime changeDate;
  final String medicationName;
  final MedicationTrackingChangeType changeType;
  final double? oldDose;
  final double? newDose;
  final String? doseUnit;
  final bool active;
  final DateTime? endedAt;
  final String? endReason;
  final String? supersededByChangeRecordId;

  Map<int, DateTime> get followUpDates => {
        for (final day in followUpDays)
          day: DateTime(
            changeDate.year,
            changeDate.month,
            changeDate.day + day,
          ),
      };

  MedicationSubjectiveTrackingCycle end({
    required DateTime endedAt,
    required String reason,
    String? supersededByChangeRecordId,
  }) {
    return MedicationSubjectiveTrackingCycle(
      id: id,
      medicationId: medicationId,
      changeRecordId: changeRecordId,
      changeDate: changeDate,
      medicationName: medicationName,
      changeType: changeType,
      oldDose: oldDose,
      newDose: newDose,
      doseUnit: doseUnit,
      active: false,
      endedAt: endedAt,
      endReason: reason,
      supersededByChangeRecordId: supersededByChangeRecordId,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'medicationId': medicationId,
        'changeRecordId': changeRecordId,
        'changeDate': changeDate.toIso8601String(),
        'medicationName': medicationName,
        'changeType': changeType.name,
        if (oldDose != null) 'oldDose': oldDose,
        if (newDose != null) 'newDose': newDose,
        if (doseUnit?.trim().isNotEmpty == true) 'doseUnit': doseUnit!.trim(),
        'active': active,
        'followUpDates': {
          for (final entry in followUpDates.entries)
            entry.key.toString(): entry.value.toIso8601String(),
        },
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
        if (endReason?.trim().isNotEmpty == true)
          'endReason': endReason!.trim(),
        if (supersededByChangeRecordId?.trim().isNotEmpty == true)
          'supersededByChangeRecordId': supersededByChangeRecordId!.trim(),
      };

  factory MedicationSubjectiveTrackingCycle.fromMap(
    Map<String, dynamic> map,
  ) {
    return MedicationSubjectiveTrackingCycle(
      id: map['id']?.toString() ?? '',
      medicationId: map['medicationId']?.toString() ?? '',
      changeRecordId: map['changeRecordId']?.toString() ?? '',
      changeDate: _date(map['changeDate'], 'changeDate'),
      medicationName: map['medicationName']?.toString() ?? '',
      changeType: _changeType(map['changeType']),
      oldDose: _number(map['oldDose']),
      newDose: _number(map['newDose']),
      doseUnit: _nullableText(map['doseUnit']),
      active: map['active'] == true,
      endedAt: _nullableDate(map['endedAt']),
      endReason: _nullableText(map['endReason']),
      supersededByChangeRecordId:
          _nullableText(map['supersededByChangeRecordId']),
    );
  }

  static String cycleId(String changeRecordId, String medicationId) =>
      '${Uri.encodeComponent(changeRecordId.trim())}_'
      '${Uri.encodeComponent(medicationId.trim())}';

  static String _requiredText(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw FormatException('$field must not be empty');
    return trimmed;
  }

  static MedicationTrackingChangeType _changeType(dynamic value) {
    for (final type in MedicationTrackingChangeType.values) {
      if (type.name == value?.toString()) return type;
    }
    throw FormatException('Invalid changeType: $value');
  }

  static double? _number(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime _date(dynamic value, String field) {
    final parsed = _nullableDate(value);
    if (parsed == null) throw FormatException('$field must be a valid date');
    return parsed;
  }

  static DateTime? _nullableDate(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }
}
