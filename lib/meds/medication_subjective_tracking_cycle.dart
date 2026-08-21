enum MedicationTrackingChangeType {
  added,
  doseIncreased,
  doseDecreased,
  doseAdjusted,
  resumed,
  scheduleChanged,
  stopped,
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
    List<String> oldTimes = const [],
    List<String> newTimes = const [],
    required this.active,
    DateTime? endedAt,
    this.endReason,
    this.supersededByChangeRecordId,
    String? episodeId,
    DateTime? episodeStartDate,
    List<String>? changeRecordIds,
    List<String>? medicationIds,
    List<String>? adjustmentTypes,
  })  : id = _requiredText(id, 'id'),
        medicationId = _requiredText(medicationId, 'medicationId'),
        changeRecordId = _requiredText(changeRecordId, 'changeRecordId'),
        medicationName = _requiredText(medicationName, 'medicationName'),
        episodeId = _nullableText(episodeId) ?? changeRecordId.trim(),
        episodeStartDate = episodeStartDate ?? changeDate,
        changeRecordIds = List.unmodifiable(
          _normalizedOrFallback(changeRecordIds, changeRecordId),
        ),
        medicationIds = List.unmodifiable(
          _normalizedOrFallback(medicationIds, medicationId),
        ),
        adjustmentTypes = List.unmodifiable(
          _normalizedOrFallback(adjustmentTypes, changeType.name),
        ),
        oldTimes = List.unmodifiable(oldTimes),
        newTimes = List.unmodifiable(newTimes),
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
  final List<String> oldTimes;
  final List<String> newTimes;
  final bool active;
  final DateTime? endedAt;
  final String? endReason;
  final String? supersededByChangeRecordId;
  final String episodeId;
  final DateTime episodeStartDate;
  final List<String> changeRecordIds;
  final List<String> medicationIds;
  final List<String> adjustmentTypes;

  Map<int, DateTime> get followUpDates => {
        for (final day in followUpDays)
          day: changeDate.add(Duration(days: day)),
      };

  bool get hasScheduleChange =>
      oldTimes.isNotEmpty &&
      newTimes.isNotEmpty &&
      oldTimes.join('\u0000') != newTimes.join('\u0000');

  String get adjustmentSummary {
    final schedule = hasScheduleChange
        ? '服藥時間：${oldTimes.join('、')} → ${newTimes.join('、')}'
        : null;
    final primary = switch (changeType) {
      MedicationTrackingChangeType.added => '新增藥物',
      MedicationTrackingChangeType.resumed => '恢復使用',
      MedicationTrackingChangeType.scheduleChanged => schedule ?? '調整服藥時間',
      MedicationTrackingChangeType.doseAdjusted => '調整劑量',
      MedicationTrackingChangeType.stopped => '停止使用',
      MedicationTrackingChangeType.doseIncreased ||
      MedicationTrackingChangeType.doseDecreased =>
        _doseSummary(),
    };
    if (schedule == null ||
        changeType == MedicationTrackingChangeType.scheduleChanged) {
      return primary;
    }
    return '$primary；$schedule';
  }

  String _doseSummary() {
    final unit = doseUnit?.trim() ?? '';
    if (oldDose != null && newDose != null) {
      return '${_doseText(oldDose!)}$unit → ${_doseText(newDose!)}$unit';
    }
    return changeType == MedicationTrackingChangeType.doseIncreased
        ? '增加劑量'
        : '減少劑量';
  }

  static String _doseText(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

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
      oldTimes: oldTimes,
      newTimes: newTimes,
      active: false,
      endedAt: endedAt,
      endReason: reason,
      supersededByChangeRecordId: supersededByChangeRecordId,
      episodeId: episodeId,
      episodeStartDate: episodeStartDate,
      changeRecordIds: changeRecordIds,
      medicationIds: medicationIds,
      adjustmentTypes: adjustmentTypes,
    );
  }

  MedicationSubjectiveTrackingCycle asEpisode({
    required String id,
    required String episodeId,
    required DateTime episodeStartDate,
    required DateTime lastAdjustmentDate,
    required String latestChangeRecordId,
    required List<String> changeRecordIds,
    required List<String> medicationIds,
    required List<String> adjustmentTypes,
  }) {
    return MedicationSubjectiveTrackingCycle(
      id: id,
      medicationId: medicationId,
      changeRecordId: latestChangeRecordId,
      changeDate: lastAdjustmentDate,
      medicationName: medicationName,
      changeType: changeType,
      oldDose: oldDose,
      newDose: newDose,
      doseUnit: doseUnit,
      oldTimes: oldTimes,
      newTimes: newTimes,
      active: true,
      episodeId: episodeId,
      episodeStartDate: episodeStartDate,
      changeRecordIds: changeRecordIds,
      medicationIds: medicationIds,
      adjustmentTypes: adjustmentTypes,
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
        'oldTimes': oldTimes,
        'newTimes': newTimes,
        'active': active,
        'episodeId': episodeId,
        'episodeStartDate': episodeStartDate.toIso8601String(),
        'changeRecordIds': changeRecordIds,
        'medicationIds': medicationIds,
        'adjustmentTypes': adjustmentTypes,
        'followUpDays': followUpDays,
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
      oldTimes: _strings(map['oldTimes']),
      newTimes: _strings(map['newTimes']),
      active: map['active'] == true,
      endedAt: _nullableDate(map['endedAt']),
      endReason: _nullableText(map['endReason']),
      supersededByChangeRecordId:
          _nullableText(map['supersededByChangeRecordId']),
      episodeId: _nullableText(map['episodeId']),
      episodeStartDate: _nullableDate(map['episodeStartDate']),
      changeRecordIds: _strings(map['changeRecordIds']),
      medicationIds: _strings(map['medicationIds']),
      adjustmentTypes: _strings(map['adjustmentTypes']),
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

  static Set<String> _normalizedOrFallback(
    Iterable<String>? values,
    String fallback,
  ) {
    final normalized = values
            ?.map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet() ??
        <String>{};
    return normalized.isEmpty ? {fallback.trim()} : normalized;
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

  static List<String> _strings(dynamic value) => value is Iterable
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];
}
