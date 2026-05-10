import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/calendar_day_summary.dart';

class CalendarSummaryService {
  CalendarSummaryService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<Map<String, CalendarDaySummary>> loadMonthSummary({
    required DateTime visibleMonth,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      debugPrint('[CalendarSummaryService] uid: null (not signed in)');
      return <String, CalendarDaySummary>{};
    }

    final range = _calendarVisibleRange(visibleMonth);
    debugPrint('[CalendarSummaryService] uid: $uid');
    debugPrint(
      '[CalendarSummaryService] range: ${_dateKey(range.start)} -> ${_dateKey(range.end)}',
    );

    final summaries = <String, CalendarDaySummary>{};

    final dailyCount = await _loadDailyRecords(
      uid: uid,
      range: range,
      summaries: summaries,
    );

    final diaryCount = await _loadDiary(
      uid: uid,
      range: range,
      summaries: summaries,
    );

    final periodCount = await _loadPeriodData(
      uid: uid,
      range: range,
      summaries: summaries,
    );

    final keys = summaries.keys.toList(growable: false);
    for (final key in keys) {
      final s = summaries[key]!;
      summaries[key] = s.copyWith(
        periodNote: _periodNote(s),
        ruleInsights: buildRuleInsights(s),
      );
    }

    final daysWithData = summaries.values.where(_hasAnyData).length;
    debugPrint('[CalendarSummaryService] dailyRecords docs: $dailyCount');
    debugPrint('[CalendarSummaryService] diary docs: $diaryCount');
    debugPrint('[CalendarSummaryService] period docs: $periodCount');
    debugPrint('[CalendarSummaryService] days with data: $daysWithData');

    return summaries;
  }

  List<String> buildRuleInsights(CalendarDaySummary summary) {
    final insights = <String>[];

    if (summary.sleepHours != null &&
        summary.sleepHours! < 6 &&
        summary.averageMood != null &&
        summary.averageMood! <= 5) {
      insights.add('這一天睡眠時間偏短，且情緒分數較低，可以留意睡眠不足是否和情緒波動同時出現。');
    }

    if (summary.hasSymptomData &&
        summary.averageMood != null &&
        summary.averageMood! <= 5) {
      insights.add('這一天同時有症狀紀錄與較低的情緒分數，建議回顧是否有壓力事件、身體不適或藥物變化。');
    }

    if ((summary.isPeriodDay || summary.isPredictedPeriodDay) &&
        summary.averageMood != null &&
        summary.averageMood! <= 5) {
      insights.add('這一天位於生理期或預測生理期附近，且情緒分數偏低，可以把身體週期作為觀察線索，但不需要直接歸因。');
    }

    if (summary.hasDiary &&
        summary.averageMood != null &&
        summary.averageMood! <= 5) {
      insights.add('這一天有日記與較低的情緒分數，可以查看日記內容，理解當天情緒下降的可能原因。');
    }

    if (summary.sleepHours != null &&
        summary.sleepHours! >= 7 &&
        summary.averageMood != null &&
        summary.averageMood! >= 7) {
      insights.add('這一天睡眠時間較充足，情緒分數也較穩定，可以作為日後回顧自身照顧方式的參考。');
    }

    if (insights.isEmpty) {
      insights.add('目前沒有明顯重疊訊號，可以先把這一天作為一般紀錄保存。');
    }

    return insights;
  }

  Future<int> _loadDailyRecords({
    required String uid,
    required _DateRange range,
    required Map<String, CalendarDaySummary> summaries,
  }) async {
    final dailyRef =
        _firestore.collection('users').doc(uid).collection('dailyRecords');

    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seen = <String>{};

    Future<void> collect(
        Query<Map<String, dynamic>> query, String label) async {
      try {
        final snap = await query.get();
        for (final doc in snap.docs) {
          if (seen.add(doc.reference.path)) {
            docs.add(doc);
          }
        }
      } catch (e) {
        debugPrint(
            '[CalendarSummaryService] dailyRecords $label query skipped: $e');
      }
    }

    await collect(
      dailyRef
          .orderBy(FieldPath.documentId)
          .where(FieldPath.documentId,
              isGreaterThanOrEqualTo: _dateKey(range.start))
          .where(FieldPath.documentId,
              isLessThanOrEqualTo: _dateKey(range.end)),
      'docId',
    );

    await collect(
      dailyRef
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(range.end)),
      'date',
    );

    var count = 0;
    for (final doc in docs) {
      final data = doc.data();
      final date = _resolveDate(doc.id, data);
      if (date == null || !_inRange(date, range)) continue;

      count++;

      final overallMood = _normalizeScore(_toDouble(data['overallMood']));
      final moodFromEmotions =
          _normalizeScore(_average(_extractNumericValues(data['emotions'])));
      final dayMood = overallMood ?? moodFromEmotions;

      final emotionNames = _extractNames(
        data['emotions'],
        preferredKeys: const ['name', 'label', 'emotion', 'title'],
      );
      final symptomNames = _extractNames(
        data['symptoms'],
        preferredKeys: const ['name', 'label', 'symptom', 'title'],
      );
      final medicationNames = _mergeStringLists(
        _extractNames(
          data['medications'] ?? data['medicines'],
          preferredKeys: const [
            'name',
            'label',
            'title',
            'drugName',
            'medicationName'
          ],
        ),
        _extractNames(
          data['medication'],
          preferredKeys: const [
            'name',
            'label',
            'title',
            'drugName',
            'medicationName'
          ],
        ),
      );
      final medicationText = _toCleanString(data['medication']);
      if (medicationText != null && !medicationNames.contains(medicationText)) {
        medicationNames.add(medicationText);
      }

      final sleepMap = _asMap(data['sleep']);
      final sleepDataMap = _asMap(data['sleepData']);
      final hypnoticName = _toCleanString(sleepMap?['hypnoticName']) ??
          _toCleanString(data['hypnoticName']);
      final hypnoticDose = _toCleanString(sleepMap?['hypnoticDose']) ??
          _toCleanString(data['hypnoticDose']);
      final tookHypnotic =
          sleepMap?['tookHypnotic'] == true || data['tookHypnotic'] == true;
      if (hypnoticName != null) {
        medicationNames.add(
            '安眠藥：$hypnoticName${hypnoticDose != null ? '（$hypnoticDose）' : ''}');
      }

      final sleepHours = _toDouble(data['sleepHours']) ??
          _toDouble(sleepMap?['durationHours']) ??
          _toDouble(sleepMap?['hours']) ??
          _toDouble(data['sleepDuration']) ??
          _toDouble(sleepMap?['duration']) ??
          _toDouble(sleepDataMap?['hours']) ??
          _toDouble(sleepDataMap?['duration']) ??
          _sleepHoursFromTimes(sleepMap) ??
          _sleepHoursFromTimes(sleepDataMap);

      final normalizedSleepHours =
          (sleepHours != null && sleepHours > 0 && sleepHours <= 24)
              ? sleepHours
              : null;

      final sleepQuality = _toDisplayString(data['sleepQuality']) ??
          _toDisplayString(sleepMap?['quality']) ??
          _toDisplayString(sleepDataMap?['quality']) ??
          _toDisplayString(data['overallSleepQuality']);

      final normalizedSleepQuality = (() {
        if (sleepQuality == null) return null;
        final score = double.tryParse(sleepQuality);
        if (score != null && (score <= 0 || score > 10)) {
          return null;
        }
        return sleepQuality;
      })();

      final hasEmotionData = dayMood != null ||
          emotionNames.isNotEmpty ||
          _hasCollectionData(data['emotions']);
      final hasSymptomData = symptomNames.isNotEmpty || _hasCollectionData(data['symptoms']);
      final hasSleepData =
          normalizedSleepHours != null ||
          normalizedSleepQuality != null ||
          _hasSleepContent(sleepMap) ||
          _hasSleepContent(sleepDataMap);
      final hasMedicationData = medicationNames.isNotEmpty ||
          tookHypnotic ||
          _hasCollectionData(data['medications']) ||
          _hasCollectionData(data['medicines']) ||
          _hasCollectionData(data['medication']);

      final periodData = _asMap(data['periodData']);
      final isPeriod =
          data['isPeriod'] == true || periodData?['isPeriod'] == true;

      final hasDailyRecordData =
          hasEmotionData || hasSymptomData || hasSleepData || hasMedicationData;

      _mergeDay(summaries, date, (current) {
        return current.copyWith(
          hasDailyRecord: current.hasDailyRecord || hasDailyRecordData,
          hasEmotionData: current.hasEmotionData || hasEmotionData,
          hasSymptomData: current.hasSymptomData || hasSymptomData,
          hasSleepData: current.hasSleepData || hasSleepData,
          hasMedicationData: current.hasMedicationData || hasMedicationData,
          isPeriodDay: current.isPeriodDay || isPeriod,
          averageMood: current.averageMood ?? dayMood,
          emotionNames: _mergeStringLists(current.emotionNames, emotionNames),
          symptomNames: _mergeStringLists(current.symptomNames, symptomNames),
          medicationNames: _mergeStringLists(current.medicationNames, medicationNames),
          sleepHours: current.sleepHours ?? normalizedSleepHours,
          sleepQuality: current.sleepQuality ?? normalizedSleepQuality,
          dailyRecordDocId: current.dailyRecordDocId ?? doc.id,
        );
      });
    }

    return count;
  }

  Future<int> _loadDiary({
    required String uid,
    required _DateRange range,
    required Map<String, CalendarDaySummary> summaries,
  }) async {
    final diaryRef =
        _firestore.collection('users').doc(uid).collection('diary');

    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seen = <String>{};

    Future<void> collect(
        Query<Map<String, dynamic>> query, String label) async {
      try {
        final snap = await query.get();
        for (final doc in snap.docs) {
          if (seen.add(doc.reference.path)) {
            docs.add(doc);
          }
        }
      } catch (e) {
        debugPrint('[CalendarSummaryService] diary $label query skipped: $e');
      }
    }

    await collect(
      diaryRef
          .orderBy(FieldPath.documentId)
          .where(FieldPath.documentId,
              isGreaterThanOrEqualTo: _dateKey(range.start))
          .where(FieldPath.documentId,
              isLessThanOrEqualTo: _dateKey(range.end)),
      'docId',
    );

    await collect(
      diaryRef
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(range.end)),
      'date',
    );

    await collect(
      diaryRef
          .where('updatedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('updatedAt',
              isLessThanOrEqualTo: Timestamp.fromDate(range.end)),
      'updatedAt',
    );

    var count = 0;
    for (final doc in docs) {
      final data = doc.data();
      final date = _resolveDate(doc.id, data);
      if (date == null || !_inRange(date, range)) continue;

      count++;

      final title = _toCleanString(data['title']);
      final content = _toCleanString(data['content']);
      final hasDiaryContent = (title != null && title.isNotEmpty) ||
          (content != null && content.isNotEmpty);

      final diarySummary = _buildDiarySummary(
        title: title,
        content: content,
      );

      final mood = hasDiaryContent
          ? _normalizeScore(
              _toDouble(data['overallMood']) ?? _toDouble(data['moodScore']))
          : null;

      _mergeDay(summaries, date, (current) {
        return current.copyWith(
          hasDiary: true,
          diaryDocId: current.diaryDocId ?? doc.id,
          diaryTitle: current.diaryTitle ?? title,
          diaryContent: current.diaryContent ?? content,
          diarySummary: current.diarySummary ?? diarySummary,
          averageMood: mood ?? current.averageMood,
        );
      });
    }

    return count;
  }

  Future<int> _loadPeriodData({
    required String uid,
    required _DateRange range,
    required Map<String, CalendarDaySummary> summaries,
  }) async {
    final cycleStarts = <DateTime>[];
    var periodDocs = 0;

    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('periodCycles')
          .get();

      periodDocs = snap.docs.length;

      for (final doc in snap.docs) {
        final data = doc.data();
        final start = _toDate(data['startDate']);
        if (start == null) continue;

        final end = _toDate(data['endDate']) ?? start;
        cycleStarts.add(_dateOnly(start));

        final s = _dateOnly(start);
        final e = _dateOnly(end);
        final startDay = s.isBefore(range.start) ? range.start : s;
        final endDay = e.isAfter(range.end) ? range.end : e;

        if (endDay.isBefore(range.start) || startDay.isAfter(range.end))
          continue;

        for (DateTime d = startDay;
            !d.isAfter(endDay);
            d = d.add(const Duration(days: 1))) {
          _mergeDay(summaries, d, (current) {
            return current.copyWith(
              isPeriodDay: true,
              clearPeriodNote: true,
              periodNote: '生理期',
            );
          });
        }
      }
    } catch (e) {
      debugPrint(
          '[CalendarSummaryService] periodCycles structure not available: $e');
    }

    final dailyStarts = _inferPeriodStartsFromSummaries(summaries, range);
    cycleStarts.addAll(dailyStarts);

    int? cycleLength;
    try {
      final config = await _firestore
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('periodTracker')
          .get();
      final value = (config.data()?['cycleLength'] as num?)?.toInt();
      if (value != null && value >= 21 && value <= 45) {
        cycleLength = value;
      }
    } catch (e) {
      debugPrint('[CalendarSummaryService] periodTracker config not found: $e');
    }

    cycleLength ??= _inferCycleLength(cycleStarts);

    if (cycleLength != null && cycleStarts.isNotEmpty) {
      cycleStarts.sort();
      final latest = cycleStarts.last;
      DateTime predicted = latest.add(Duration(days: cycleLength));

      while (predicted.isBefore(range.start)) {
        predicted = predicted.add(Duration(days: cycleLength));
      }

      while (!predicted.isAfter(range.end)) {
        for (var i = 0; i < 5; i++) {
          final day = predicted.add(Duration(days: i));
          if (!_inRange(day, range)) continue;
          _mergeDay(summaries, day, (current) {
            if (current.isPeriodDay) {
              return current.copyWith(
                clearPeriodNote: true,
                periodNote: '生理期',
              );
            }
            return current.copyWith(
              isPredictedPeriodDay: true,
              clearPeriodNote: true,
              periodNote: '預測生理期',
            );
          });
        }
        predicted = predicted.add(Duration(days: cycleLength));
      }
    }

    if (periodDocs == 0 && cycleLength == null) {
      debugPrint(
          '[CalendarSummaryService] period data not found, default to false');
    }

    return periodDocs;
  }

  List<DateTime> _inferPeriodStartsFromSummaries(
    Map<String, CalendarDaySummary> summaries,
    _DateRange range,
  ) {
    final daySet = summaries.values
        .where((s) => s.isPeriodDay)
        .map((s) => _dateOnly(s.date))
        .toSet();

    if (daySet.isEmpty) return const [];

    final sorted = daySet.toList()..sort();
    final starts = <DateTime>[];
    for (final day in sorted) {
      final prev = day.subtract(const Duration(days: 1));
      if (!daySet.contains(prev) && _inRange(day, range)) {
        starts.add(day);
      }
    }
    return starts;
  }

  int? _inferCycleLength(List<DateTime> starts) {
    if (starts.length < 2) return null;
    final sorted = starts.toSet().toList()..sort();

    final gaps = <int>[];
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].difference(sorted[i - 1]).inDays;
      if (gap >= 21 && gap <= 45) {
        gaps.add(gap);
      }
    }

    if (gaps.isEmpty) return null;
    final avg = gaps.reduce((a, b) => a + b) / gaps.length;
    return avg.round();
  }

  String? _periodNote(CalendarDaySummary s) {
    if (s.isPeriodDay) return '生理期';
    if (s.isPredictedPeriodDay) return '預測生理期';
    return null;
  }

  void _mergeDay(
    Map<String, CalendarDaySummary> summaries,
    DateTime date,
    CalendarDaySummary Function(CalendarDaySummary current) updater,
  ) {
    final normalized = _dateOnly(date);
    final key = _dateKey(normalized);
    final current = summaries[key] ?? CalendarDaySummary.empty(normalized);
    summaries[key] = updater(current);
  }

  bool _hasAnyData(CalendarDaySummary s) {
    return s.hasDailyRecord ||
        s.hasDiary ||
        s.hasEmotionData ||
        s.hasSymptomData ||
        s.hasSleepData ||
        s.isPeriodDay ||
        s.isPredictedPeriodDay ||
        s.averageMood != null;
  }

  _DateRange _calendarVisibleRange(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final firstWeekdayIndex = firstDay.weekday % 7;
    final start =
        _dateOnly(firstDay.subtract(Duration(days: firstWeekdayIndex)));

    final lastDay = DateTime(month.year, month.month + 1, 0);
    final trailing = 6 - (lastDay.weekday % 7);
    final end = _dateOnly(lastDay.add(Duration(days: trailing)));

    return _DateRange(start: start, end: end);
  }

  DateTime? _resolveDate(String docId, Map<String, dynamic> data) {
    final fromId = _dateFromKey(docId);
    if (fromId != null) return fromId;

    final fromDate = _toDate(data['date']);
    if (fromDate != null) return _dateOnly(fromDate);

    final fromCreated = _toDate(data['createdAt']);
    if (fromCreated != null) return _dateOnly(fromCreated);

    final fromUpdated = _toDate(data['updatedAt']);
    if (fromUpdated != null) return _dateOnly(fromUpdated);

    return null;
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final dateKey = _dateFromKey(value);
      if (dateKey != null) return dateKey;
      return DateTime.tryParse(value);
    }
    if (value is int) {
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    }
    return null;
  }

  DateTime? _dateFromKey(String value) {
    final m = RegExp(r'^\\d{4}-\\d{2}-\\d{2}$').firstMatch(value);
    if (m == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return _dateOnly(parsed);
  }

  bool _inRange(DateTime date, _DateRange range) {
    final d = _dateOnly(date);
    return !d.isBefore(range.start) && !d.isAfter(range.end);
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) {
        out[k.toString()] = v;
      });
      return out;
    }
    return null;
  }

  bool _hasCollectionData(dynamic value) {
    if (value is Iterable) {
      for (final item in value) {
        if (_hasMeaningfulValue(item)) return true;
      }
      return false;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (_hasMeaningfulValue(entry.value)) return true;
      }
      return false;
    }
    return _hasMeaningfulValue(value);
  }

  bool _hasMeaningfulValue(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num) return value != 0;
    if (value is Timestamp) return true;
    if (value is DateTime) return true;
    if (value is Iterable) {
      for (final item in value) {
        if (_hasMeaningfulValue(item)) return true;
      }
      return false;
    }
    if (value is Map) {
      for (final nested in value.values) {
        if (_hasMeaningfulValue(nested)) return true;
      }
      return false;
    }
    return true;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  String? _toCleanString(dynamic value) {
    if (value is! String) return null;
    final s = value.trim();
    return s.isEmpty ? null : s;
  }

  String? _toDisplayString(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final s = value.trim();
      return s.isEmpty ? null : s;
    }
    if (value is num) {
      if (value.isNaN || value.isInfinite) return null;
      return value % 1 == 0 ? value.toInt().toString() : value.toString();
    }
    return null;
  }

  double? _sleepHoursFromTimes(Map<String, dynamic>? sleepMap) {
    if (sleepMap == null || sleepMap.isEmpty) return null;

    final sleepTime = _toCleanString(sleepMap['sleepTime']);
    final wakeTime = _toCleanString(sleepMap['finalWakeTime']) ??
        _toCleanString(sleepMap['wakeTime']);
    if (sleepTime == null || wakeTime == null) return null;

    final start = _parseHmMinutes(sleepTime);
    final end = _parseHmMinutes(wakeTime);
    if (start == null || end == null) return null;

    var diff = end - start;
    if (diff <= 0) {
      diff += 24 * 60;
    }
    if (diff <= 0) return null;

    return diff / 60.0;
  }

  bool _hasSleepContent(Map<String, dynamic>? sleepMap) {
    if (sleepMap == null || sleepMap.isEmpty) return false;

    final hasTime = _hasMeaningfulTimeString(sleepMap['sleepTime']) ||
        _hasMeaningfulTimeString(sleepMap['wakeTime']) ||
        _hasMeaningfulTimeString(sleepMap['finalWakeTime']);

    final hasNote = _toCleanString(sleepMap['note']) != null;
    final hasMidWake = _toCleanString(sleepMap['midWakeList']) != null;

    final qualityText = _toDisplayString(sleepMap['quality']);
    final qualityNumber = qualityText != null ? double.tryParse(qualityText) : null;
    final hasQuality = qualityNumber != null
        ? (qualityNumber > 0 && qualityNumber <= 10)
        : qualityText != null;

    final hasFlags = (sleepMap['flags'] is Iterable) &&
        (sleepMap['flags'] as Iterable).any((item) => _toCleanString(item) != null);

    final hasNaps = (sleepMap['naps'] is Iterable) &&
        (sleepMap['naps'] as Iterable).isNotEmpty;

    return hasTime || hasNote || hasMidWake || hasQuality || hasFlags || hasNaps;
  }

  bool _hasMeaningfulTimeString(dynamic value) {
    if (value is! String) return false;
    final t = value.trim();
    if (t.isEmpty || t == '-' || t == '--' || t == '—' || t.toLowerCase() == 'null') {
      return false;
    }
    return _parseHmMinutes(t) != null;
  }

  int? _parseHmMinutes(String text) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (m == null) return null;

    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;

    return h * 60 + min;
  }

  double? _normalizeScore(double? value) {
    if (value == null) return null;
    if (value.isNaN || value.isInfinite) return null;
    if (value <= 0 || value > 10) return null;
    return value;
  }

  List<String> _extractNames(
    dynamic source, {
    required List<String> preferredKeys,
  }) {
    final names = <String>[];

    void addName(String? s) {
      if (s == null) return;
      final t = s.trim();
      if (t.isEmpty) return;
      if (!names.contains(t)) names.add(t);
    }

    String? pickFromMap(Map map) {
      for (final k in preferredKeys) {
        final v = map[k];
        if (v is String && v.trim().isNotEmpty) return v;
      }
      return null;
    }

    if (source is List) {
      for (final item in source) {
        if (item is String) {
          addName(item);
        } else if (item is Map) {
          addName(pickFromMap(item));
        }
      }
    } else if (source is Map) {
      source.forEach((key, value) {
        if (value is Map) {
          addName(pickFromMap(value));
        } else if (value is String) {
          addName(value);
        }

        // For map-style records like {"anxious": true}, only keep key when value is meaningful.
        if (_hasMeaningfulValue(value) && key is String && key.trim().isNotEmpty) {
          final lowered = key.trim().toLowerCase();
          final ignored = {'intensity', 'score', 'value', 'level'};
          if (!ignored.contains(lowered)) {
            addName(key);
          }
        }
      });
    }

    return names;
  }

  List<String> _mergeStringLists(List<String> a, List<String> b) {
    final out = <String>[...a];
    for (final item in b) {
      if (!out.contains(item)) out.add(item);
    }
    return out;
  }

  String? _buildDiarySummary({
    String? title,
    String? content,
  }) {
    if (content != null && content.isNotEmpty) {
      final trimmed = content.trim();
      if (trimmed.length <= 80) return trimmed;
      return '${trimmed.substring(0, 80)}...';
    }
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return null;
  }

  List<double> _extractNumericValues(dynamic emotions) {
    final values = <double>[];

    if (emotions is List) {
      for (final item in emotions) {
        final extracted = _extractNumericFromEmotionItem(item);
        if (extracted != null) values.add(extracted);
      }
    } else if (emotions is Map) {
      for (final entry in emotions.entries) {
        final extracted = _extractNumericFromEmotionItem(entry.value);
        if (extracted != null) {
          values.add(extracted);
          continue;
        }
        if (entry.value is num) {
          values.add((entry.value as num).toDouble());
        }
      }
    }

    return values;
  }

  double? _extractNumericFromEmotionItem(dynamic item) {
    if (item is num) return item.toDouble();

    if (item is Map) {
      for (final key in const ['intensity', 'score', 'value', 'level']) {
        final v = _toDouble(item[key]);
        if (v != null) return v;
      }
    }

    return null;
  }

  double? _average(List<double> values) {
    if (values.isEmpty) return null;
    final sum = values.reduce((a, b) => a + b);
    return sum / values.length;
  }
}

class _DateRange {
  final DateTime start;
  final DateTime end;

  const _DateRange({
    required this.start,
    required this.end,
  });
}
