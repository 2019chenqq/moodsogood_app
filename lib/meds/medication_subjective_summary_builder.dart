import 'medication_subjective_response.dart';

class MedicationSubjectiveSummaryBuilder {
  const MedicationSubjectiveSummaryBuilder._();

  static List<Map<String, dynamic>> toAiInput(
    Iterable<MedicationSubjectiveResponse> responses, {
    int maxCycles = 6,
  }) {
    final grouped = <String, List<MedicationSubjectiveResponse>>{};
    for (final response in responses) {
      grouped.putIfAbsent(groupKey(response), () => []).add(response);
    }
    final groups = grouped.entries.map((entry) {
      final items = entry.value
        ..sort((left, right) => left.followUpDay.compareTo(right.followUpDay));
      final first = items.first;
      return <String, dynamic>{
        'medicationId': first.medicationId,
        'changeRecordId': first.changeRecordId,
        'medicationName': first.medicationName,
        'changeDate': _date(first.changeDate),
        'pairingStatus': first.medicationId ==
                MedicationSubjectiveResponse.legacyUnknownMedicationId
            ? 'legacy_unassigned'
            : 'matched_by_medication_id_and_change_record_id',
        'responses': items
            .map((item) => <String, dynamic>{
                  'followUpDay': item.followUpDay,
                  'overallResponse': item.overallResponse.name,
                  'changedAreas': item.changedAreas,
                  'perceivedRelation': item.perceivedRelation.name,
                  'otherFactors': item.otherFactors,
                  'note': _limitForAi(item.note.trim()),
                })
            .toList(),
      };
    }).toList()
      ..sort((left, right) => (right['changeDate'] as String)
          .compareTo(left['changeDate'] as String));
    return groups.take(maxCycles).toList().reversed.toList();
  }

  static String groupKey(MedicationSubjectiveResponse response) =>
      '${response.medicationId}\u0000${response.changeRecordId}';

  static List<MedicationSubjectiveResponse> forMedicationChange(
    Iterable<MedicationSubjectiveResponse> responses, {
    required String medicationId,
    required String changeRecordId,
    required Set<String> medicationIdsForChange,
  }) {
    final allowLegacyFallback = medicationIdsForChange.length <= 1;
    final result = responses.where((response) {
      if (response.changeRecordId != changeRecordId) return false;
      if (response.medicationId == medicationId) return true;
      return allowLegacyFallback &&
          response.medicationId ==
              MedicationSubjectiveResponse.legacyUnknownMedicationId;
    }).toList()
      ..sort((a, b) => a.followUpDay.compareTo(b.followUpDay));
    return result;
  }

  static List<String> fallbackSummaries(
    Iterable<Map<String, dynamic>> groups,
  ) =>
      groups.map(fallbackSummary).where((text) => text.isNotEmpty).toList();

  static String fallbackSummary(Map<String, dynamic> group) {
    final medicationName = group['medicationName']?.toString().trim() ?? '';
    final rawResponses = group['responses'];
    if (rawResponses is! List || rawResponses.isEmpty) return '';
    final responses = rawResponses
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort((left, right) => _day(left).compareTo(_day(right)));
    if (responses.isEmpty) return '';

    final pairingStatus = group['pairingStatus']?.toString() ?? '';
    final prefix = pairingStatus == 'unsafe_to_assign_to_one_medication'
        ? '無法安全配對至單一藥物的使用者主觀回報：'
        : medicationName.isEmpty
            ? '使用者主觀回報：'
            : '$medicationName（使用者主觀回報）：';
    if (responses.length == 1) {
      final response = responses.first;
      final parts = <String>[
        '使用者於調藥後第${_day(response)}天主觀回報整體感受為${_overall(response['overallResponse'])}',
      ];
      final areas = _strings(response['changedAreas']);
      if (areas.isNotEmpty) parts.add('變化方面包括${areas.join('、')}');
      parts.add('使用者認為與此次用藥調整${_relation(response['perceivedRelation'])}');
      final factors = _strings(response['otherFactors']);
      if (factors.isNotEmpty) {
        parts.add('同期紀錄顯示可能影響因素包括${factors.join('、')}');
      }
      final note = response['note']?.toString().trim() ?? '';
      if (note.isNotEmpty) parts.add('使用者另提到${_limit(note)}');
      return '$prefix${parts.join('；')}。';
    }

    final days = responses.map(_day).toList();
    final parts = <String>[
      '使用者於調藥後第${days.join('、')}天完成主觀回報',
    ];
    final firstOverall = _overall(responses.first['overallResponse']);
    final lastOverall = _overall(responses.last['overallResponse']);
    if (responses
            .map((item) => item['overallResponse']?.toString())
            .toSet()
            .length ==
        1) {
      parts.add('各次整體感受均為$firstOverall');
    } else {
      parts.add(
          '整體感受由第${days.first}天的$firstOverall，至第${days.last}天為$lastOverall');
    }

    final areaCounts = <String, int>{};
    for (final response in responses) {
      for (final area in _strings(response['changedAreas']).toSet()) {
        areaCounts[area] = (areaCounts[area] ?? 0) + 1;
      }
    }
    final persistentAreas = areaCounts.entries
        .where((entry) => entry.value >= 2)
        .map((entry) => entry.key)
        .toList();
    final occasionalAreas = areaCounts.entries
        .where((entry) => entry.value == 1)
        .map((entry) => entry.key)
        .toList();
    if (persistentAreas.isNotEmpty) {
      parts.add('持續回報的變化包括${persistentAreas.join('、')}');
    }
    if (occasionalAreas.isNotEmpty) {
      parts.add('另曾回報${occasionalAreas.join('、')}');
    }

    final relations =
        responses.map((item) => _relation(item['perceivedRelation'])).toList();
    if (relations.toSet().length == 1) {
      parts.add('使用者認為與此次用藥調整${relations.first}');
    } else {
      parts.add('使用者對關聯的看法由${relations.first}變為${relations.last}');
    }

    if (responses
        .any((item) => item['perceivedRelation']?.toString() == 'unsure')) {
      parts.add('使用者認為與此次用藥調整的關聯仍不確定');
    }
    if (responses
            .map((item) => item['overallResponse']?.toString())
            .toSet()
            .length >
        2) {
      parts.add(
        '各次整體感受依序為${responses.map((item) => '第${_day(item)}天${_overall(item['overallResponse'])}').join('、')}',
      );
    }

    final factors = responses
        .expand((item) => _strings(item['otherFactors']))
        .toSet()
        .toList();
    if (factors.isNotEmpty) {
      parts.add('同期紀錄顯示可能影響因素包括${factors.join('、')}');
    }
    final notes = responses
        .map((item) => item['note']?.toString().trim() ?? '')
        .where((note) => note.isNotEmpty)
        .toSet()
        .take(2)
        .map(_limit)
        .toList();
    if (notes.isNotEmpty) parts.add('使用者另提到${notes.join('；')}');
    return '$prefix${parts.join('；')}。';
  }

  static bool isSafeAiSummary(String value) {
    final text = value.trim();
    if (text.isEmpty || text.length > 500) return false;
    if (!const ['使用者主觀回報', '使用者認為', '同期紀錄顯示'].any(text.contains)) {
      return false;
    }
    return !RegExp(
      r'藥物(?:有效|無效)|副作用|診斷|建議(?:增藥|減藥|停藥|換藥)|確定(?:是|與)|導致|造成',
    ).hasMatch(text);
  }

  static int _day(Map<String, dynamic> item) => item['followUpDay'] is int
      ? item['followUpDay'] as int
      : int.tryParse(item['followUpDay']?.toString() ?? '') ?? 0;

  static List<String> _strings(dynamic value) => value is Iterable
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];

  static String _overall(dynamic value) => switch (value?.toString()) {
        'better' => '有改善',
        'worse' => '變差',
        'mixed' => '好壞都有',
        'noChange' => '沒有明顯變化',
        _ => '不確定',
      };

  static String _relation(dynamic value) => switch (value?.toString()) {
        'veryLikely' => '很可能有關',
        'likely' => '可能有關',
        'unlikely' => '可能無關',
        'veryUnlikely' => '幾乎無關',
        _ => '仍不確定',
      };

  static String _limit(String value) =>
      value.length <= 120 ? value : '${value.substring(0, 120)}…';

  static String _limitForAi(String value) =>
      value.length <= 300 ? value : '${value.substring(0, 300)}…';

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
