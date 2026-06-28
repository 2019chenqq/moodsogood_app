enum InjectionIntervalUnit { hour, day, week, month, year }

class MedicationScheduleUtils {
  MedicationScheduleUtils._();

  static const Set<String> injectionKeywords = {
    '注射',
    '針',
    '針劑',
    '注射劑',
    '注射液',
    '點滴',
    '滴注',
    '輸注',
  };

  static const Set<String> dropsKeywords = {
    '滴劑',
    '滴液',
    '眼藥水',
    '耳滴劑',
    '鼻滴劑',
    '口服液',
    '口服溶液',
    '懸液',
    '乳膏',
    '凝膠',
    '軟膏',
    '貼片',
    '噴霧',
  };

  static const Set<String> oralKeywords = {
    '口服',
    '錠',
    '片',
    '膠囊',
    '顆粒',
    '口溶',
    '口崩',
  };

  static const List<InjectionIntervalUnit> intervalUnits = [
    InjectionIntervalUnit.hour,
    InjectionIntervalUnit.day,
    InjectionIntervalUnit.week,
    InjectionIntervalUnit.month,
    InjectionIntervalUnit.year,
  ];

  static String normalizeMedicationType(String? raw) {
    final text = _normalizedText(raw);
    if (text.isEmpty) return 'tablet';
    if (_containsAny(text, injectionKeywords)) return 'injection';
    if (_containsAny(text, dropsKeywords)) return 'drops';
    if (_containsAny(text, oralKeywords)) return 'tablet';

    switch (text) {
      case 'tablet':
      case 'oral':
      case 'po':
        return 'tablet';
      case 'injection':
      case 'inject':
      case 'shot':
        return 'injection';
      case 'drops':
      case 'drop':
      case 'solution':
        return 'drops';
      default:
        return 'tablet';
    }
  }

  static String? medicationTypeFromDosageForm(String? dosageForm) {
    final text = _normalizedText(dosageForm);
    if (text.isEmpty) return null;
    if (_containsAny(text, injectionKeywords)) return 'injection';
    if (_containsAny(text, dropsKeywords)) return 'drops';
    if (_containsAny(text, oralKeywords)) return 'tablet';
    return null;
  }

  static String resolveMedicationType({
    String? dosageForm,
    String? manualMedicationType,
  }) {
    return medicationTypeFromDosageForm(dosageForm) ??
        normalizeMedicationType(manualMedicationType);
  }

  static bool isInjectionMedication({
    String? dosageForm,
    String? manualMedicationType,
  }) {
    return resolveMedicationType(
          dosageForm: dosageForm,
          manualMedicationType: manualMedicationType,
        ) ==
        'injection';
  }

  static bool isDropsMedication({
    String? dosageForm,
    String? manualMedicationType,
  }) {
    return resolveMedicationType(
          dosageForm: dosageForm,
          manualMedicationType: manualMedicationType,
        ) ==
        'drops';
  }

  static int? parseInjectionIntervalValue(dynamic raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null) return parsed;
      final parsedDouble = double.tryParse(raw.trim());
      if (parsedDouble != null) return parsedDouble.round();
    }
    return null;
  }

  static String normalizeInjectionIntervalUnit(dynamic raw) {
    final text = _normalizedText(raw);
    switch (text) {
      case 'hour':
      case 'hours':
      case 'hr':
      case 'hrs':
      case '小時':
        return 'hour';
      case 'day':
      case 'days':
      case '天':
        return 'day';
      case 'week':
      case 'weeks':
      case '週':
      case '週次':
        return 'week';
      case 'month':
      case 'months':
      case '月':
        return 'month';
      case 'year':
      case 'years':
      case '年':
        return 'year';
      default:
        return 'day';
    }
  }

  static String injectionIntervalUnitLabel(String unit) {
    switch (normalizeInjectionIntervalUnit(unit)) {
      case 'hour':
        return '小時';
      case 'week':
        return '週';
      case 'month':
        return '月';
      case 'year':
        return '年';
      case 'day':
      default:
        return '天';
    }
  }

  static DateTime calculateNextInjectionDate({
    required DateTime lastInjectionDate,
    required int intervalValue,
    required String intervalUnit,
  }) {
    final safeValue = intervalValue <= 0 ? 1 : intervalValue;
    switch (normalizeInjectionIntervalUnit(intervalUnit)) {
      case 'hour':
        return lastInjectionDate.add(Duration(hours: safeValue));
      case 'week':
        return lastInjectionDate.add(Duration(days: safeValue * 7));
      case 'month':
        return _addMonthsSafely(lastInjectionDate, safeValue);
      case 'year':
        return _addMonthsSafely(lastInjectionDate, safeValue * 12);
      case 'day':
      default:
        return lastInjectionDate.add(Duration(days: safeValue));
    }
  }

  static String describeInterval({
    required int intervalValue,
    required String intervalUnit,
  }) {
    final unit = normalizeInjectionIntervalUnit(intervalUnit);
    final label = injectionIntervalUnitLabel(unit);
    return '每 $intervalValue $label';
  }

  static Map<String, dynamic> readInjectionIntervalFields(
    Map<String, dynamic> data,
  ) {
    final value = parseInjectionIntervalValue(
          data['injectionIntervalValue'],
        ) ??
        parseInjectionIntervalValue(data['injectionIntervalDays']) ??
        parseInjectionIntervalValue(data['intervalDays']);

    final unitRaw = data['injectionIntervalUnit'] ?? data['intervalUnit'];
    final unit = value == null
        ? null
        : normalizeInjectionIntervalUnit(
            unitRaw ?? (data['intervalDays'] != null ? 'day' : null));

    return {
      'injectionIntervalValue': value,
      'injectionIntervalUnit': unit,
    };
  }

  static Map<String, dynamic> writeInjectionIntervalFields({
    required int? intervalValue,
    required String? intervalUnit,
  }) {
    final unit = normalizeInjectionIntervalUnit(intervalUnit);
    final value =
        intervalValue != null && intervalValue > 0 ? intervalValue : null;
    final legacyValue = unit == 'day' ? value : null;
    return {
      'injectionIntervalValue': value,
      'injectionIntervalUnit': value == null ? null : unit,
      'injectionIntervalDays': legacyValue,
      'intervalDays': legacyValue,
    };
  }

  static DateTime _addMonthsSafely(DateTime input, int monthsToAdd) {
    final anchor = DateTime(
      input.year,
      input.month + monthsToAdd,
      1,
      input.hour,
      input.minute,
      input.second,
      input.millisecond,
      input.microsecond,
    );
    final lastDayOfTargetMonth = DateTime(anchor.year, anchor.month + 1, 0).day;
    final safeDay =
        input.day <= lastDayOfTargetMonth ? input.day : lastDayOfTargetMonth;
    return DateTime(
      anchor.year,
      anchor.month,
      safeDay,
      input.hour,
      input.minute,
      input.second,
      input.millisecond,
      input.microsecond,
    );
  }

  static bool _containsAny(String text, Set<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  static String _normalizedText(dynamic raw) {
    return (raw?.toString() ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('（', '(')
        .replaceAll('）', ')');
  }
}
