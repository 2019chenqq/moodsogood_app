import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/calendar_day_summary.dart';
import '../models/daily_check_in.dart';
import '../models/daily_record.dart';
import '../models/health_event.dart';
import '../models/life_timeline_item.dart';
import '../daily/daily_state_dimensions.dart';
import '../meds/med_symptom_compare_models.dart';
import '../meds/medication_subjective_response.dart';
import '../utils/health_data_encryption_service.dart';
import 'calendar_summary_service.dart';

class LifeTimelineService {
  LifeTimelineService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    CalendarSummaryService? calendarSummaryService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _calendarSummaryService = calendarSummaryService ??
            CalendarSummaryService(auth: auth, firestore: firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final CalendarSummaryService _calendarSummaryService;

  /// Fallback order for date-only items. Keep this policy centralized: these
  /// ranks provide stable ordering but are not synthetic clock times.
  static const fallbackTypeOrder = <String, int>{
    LifeTimelineType.sleep: 10,
    LifeTimelineType.dailyCheckIn: 20,
    LifeTimelineType.emotion: 30,
    LifeTimelineType.symptom: 40,
    LifeTimelineType.period: 50,
    LifeTimelineType.diary: 60,
    LifeTimelineType.activity: 70,
    LifeTimelineType.medication: 80,
    LifeTimelineType.subjectiveMedicationResponse: 90,
    LifeTimelineType.quickRecord: 100,
  };

  Future<List<LifeTimelineItem>> loadDay(DateTime date) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');

    final day = _day(date);
    final endExclusive = day.add(const Duration(days: 1));
    final user = _firestore.collection('users').doc(uid);

    final results = await Future.wait([
      _loadDailyRecordDocuments(user, day, endExclusive),
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('healthEvents')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(day))
            .where('timestamp', isLessThan: Timestamp.fromDate(endExclusive)),
      ),
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('dailyCheckIns')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(day))
            .where('date', isLessThan: Timestamp.fromDate(endExclusive)),
      ),
      _calendarSummaryService.loadMonthSummary(visibleMonth: day),
      HealthDataEncryptionService.getEncrypted(
        user.collection('medAdjustments'),
      ),
      HealthDataEncryptionService.getEncrypted(
        user.collection('medicationSubjectiveResponses'),
      ),
    ]);

    final dailyRecordDocs =
        results[0] as List<_TimelineDocument<Map<String, dynamic>>>;
    final eventDocs = results[1] as List<HealthDocument>;
    final checkInDocs = results[2] as List<HealthDocument>;
    final summaries = results[3] as Map<String, CalendarDaySummary>;
    final adjustmentDocs = results[4] as List<HealthDocument>;
    final responseDocs = results[5] as List<HealthDocument>;
    final adjustmentEvents = adjustmentDocs.expand(
      (doc) => MedicationAdjustmentEvent.fromRecord({
        'id': doc.id,
        ...doc.data,
      }),
    );
    final subjectiveResponses = <MedicationSubjectiveResponse>[];
    for (final doc in responseDocs) {
      try {
        final responseData = <String, dynamic>{
          'id': doc.id,
          ...doc.data,
        };
        for (final field in const ['changeDate', 'recordedAt']) {
          final value = responseData[field];
          if (value is Timestamp) responseData[field] = value.toDate();
        }
        subjectiveResponses.add(
          MedicationSubjectiveResponse.fromMap(responseData),
        );
      } on FormatException {
        // Incomplete legacy responses are skipped instead of breaking the day.
      } on ArgumentError {
        // Unsupported legacy follow-up days are not reliable timeline events.
      }
    }

    return buildDayItems(
      date: day,
      dailyRecords:
          dailyRecordDocs.map((doc) => DailyRecord.fromData(doc.id, doc.data)),
      quickRecords:
          eventDocs.map((doc) => HealthEvent.fromMap(doc.id, doc.data)),
      dailyCheckIns: checkInDocs.map((doc) => DailyCheckIn.fromData(doc.data)),
      calendarSummary: summaries[_dateKey(day)],
      medicationAdjustments: adjustmentEvents,
      subjectiveMedicationResponses: subjectiveResponses,
    );
  }

  Future<LifeTimelineRangeData> loadRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    final startDay = _day(start);
    final endDay = _day(end);
    if (endDay.isBefore(startDay)) {
      throw ArgumentError('end must not be before start');
    }
    final endExclusive = endDay.add(const Duration(days: 1));
    final user = _firestore.collection('users').doc(uid);
    final months = <DateTime>[];
    var month = DateTime(startDay.year, startDay.month);
    final lastMonth = DateTime(endDay.year, endDay.month);
    while (!month.isAfter(lastMonth)) {
      months.add(month);
      month = DateTime(month.year, month.month + 1);
    }

    final coreFuture = Future.wait([
      _loadDailyRecordDocuments(user, startDay, endExclusive),
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('healthEvents')
            .where('timestamp',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('timestamp', isLessThan: Timestamp.fromDate(endExclusive)),
      ),
      HealthDataEncryptionService.getEncrypted(
        user
            .collection('dailyCheckIns')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('date', isLessThan: Timestamp.fromDate(endExclusive)),
      ),
      HealthDataEncryptionService.getEncrypted(
          user.collection('medAdjustments')),
      HealthDataEncryptionService.getEncrypted(
        user.collection('medicationSubjectiveResponses'),
      ),
    ]);
    final summaryFuture = Future.wait(
      months.map(
        (value) =>
            _calendarSummaryService.loadMonthSummary(visibleMonth: value),
      ),
    );
    final core = await coreFuture;
    final summaryMaps = await summaryFuture;

    final dailyRecordDocs =
        core[0] as List<_TimelineDocument<Map<String, dynamic>>>;
    final eventDocs = core[1] as List<HealthDocument>;
    final checkInDocs = core[2] as List<HealthDocument>;
    final adjustmentDocs = core[3] as List<HealthDocument>;
    final responseDocs = core[4] as List<HealthDocument>;
    final records = dailyRecordDocs
        .map((doc) => DailyRecord.fromData(doc.id, doc.data))
        .toList(growable: false);
    final events = eventDocs
        .map((doc) => HealthEvent.fromMap(doc.id, doc.data))
        .toList(growable: false);
    final checkIns = checkInDocs
        .map((doc) => DailyCheckIn.fromData(doc.data))
        .toList(growable: false);
    final adjustments = adjustmentDocs
        .expand(
          (doc) => MedicationAdjustmentEvent.fromRecord({
            'id': doc.id,
            ...doc.data,
          }),
        )
        .toList(growable: false);
    final responses = _decodeSubjectiveResponses(responseDocs);
    final summaries = <String, CalendarDaySummary>{};
    for (final values in summaryMaps) {
      summaries.addAll(values);
    }

    final itemsByDate = <DateTime, List<LifeTimelineItem>>{};
    for (var date = startDay;
        !date.isAfter(endDay);
        date = date.add(const Duration(days: 1))) {
      itemsByDate[date] = buildDayItems(
        date: date,
        dailyRecords: records,
        quickRecords: events,
        dailyCheckIns: checkIns,
        calendarSummary: summaries[_dateKey(date)],
        medicationAdjustments: adjustments,
        subjectiveMedicationResponses: responses,
      );
    }
    return LifeTimelineRangeData(
      start: startDay,
      end: endDay,
      itemsByDate: Map.unmodifiable(itemsByDate),
    );
  }

  static List<LifeTimelineItem> buildDayItems({
    required DateTime date,
    Iterable<DailyRecord> dailyRecords = const [],
    Iterable<HealthEvent> quickRecords = const [],
    Iterable<DailyCheckIn> dailyCheckIns = const [],
    CalendarDaySummary? calendarSummary,
    Iterable<MedicationAdjustmentEvent> medicationAdjustments = const [],
    Iterable<MedicationSubjectiveResponse> subjectiveMedicationResponses =
        const [],
  }) {
    final day = _day(date);
    final records = dailyRecords.where((item) => _sameDay(item.date, day));
    final events = quickRecords
        .where((item) => _sameDay(item.timestamp, day))
        .toList(growable: false);
    final checkIns = dailyCheckIns.where((item) => _sameDay(item.date, day));
    final items = <LifeTimelineItem>[];

    final quickEmotionKeys = <String>{
      for (final event in events)
        for (final emotion in event.emotions)
          _scoredKey(emotion.name, emotion.intensity),
    };
    final quickSymptomNames = <String>{
      for (final event in events)
        for (final symptom in event.symptoms) symptom.name.trim(),
    };
    final quickActivityValues = <int>{
      for (final event in events)
        if (event.stateChanges['activity_change'] != null)
          event.stateChanges['activity_change']!,
    };

    for (final checkIn in checkIns) {
      items.add(
        LifeTimelineItem(
          time: day,
          type: LifeTimelineType.dailyCheckIn,
          title: 'Daily Check-in',
          summary:
              '整體情緒 ${checkIn.overallMood}/5、身體狀態 ${checkIn.healthStatus}/5',
          sourceId: _dateKey(checkIn.date),
          hasExplicitTime: false,
          metadata: {
            'overallMood': checkIn.overallMood,
            'healthStatus': checkIn.healthStatus,
            'noSpecialEvent': checkIn.noSpecialEvent,
            'moodScale': 5,
          },
        ),
      );
    }

    for (final event in events) {
      final activityValue = event.stateChanges['activity_change'];
      final hasOtherQuickContent = event.symptoms.isNotEmpty ||
          event.emotions.isNotEmpty ||
          event.stateChanges.keys.any((key) => key != 'activity_change') ||
          (event.context ?? '').trim().isNotEmpty ||
          (event.note ?? '').trim().isNotEmpty;
      final details = <String>[
        ...event.symptoms.map((item) => '${item.name} ${item.severity}'),
        ...event.emotions.map((item) => '${item.name} ${item.intensity}'),
        ...event.stateChanges.entries
            .where((item) => item.key != 'activity_change')
            .map((item) => '${item.key} ${item.value}'),
        if (activityValue != null && hasOtherQuickContent)
          '活動量：${_activityLabel(activityValue)}',
        if ((event.context ?? '').trim().isNotEmpty) event.context!.trim(),
        if ((event.note ?? '').trim().isNotEmpty) event.note!.trim(),
      ];
      if (activityValue == null || hasOtherQuickContent) {
        items.add(
          LifeTimelineItem(
            time: event.timestamp,
            type: LifeTimelineType.quickRecord,
            title: 'Quick Record',
            summary: details.isEmpty ? '已留下快速紀錄' : details.join('、'),
            sourceId: event.id.isEmpty ? null : event.id,
            metadata: {
              'sourceType': 'healthEvent',
              'timestampPrecision': 'timestamp',
              'symptoms': event.symptoms.map((item) => item.toMap()).toList(),
              'emotions': event.emotions.map((item) => item.toMap()).toList(),
              if (event.stateChanges.isNotEmpty)
                'stateChanges': Map<String, int>.from(event.stateChanges),
            },
          ),
        );
      }
      if (activityValue != null && !hasOtherQuickContent) {
        items.add(_activityItem(
          day: day,
          value: activityValue,
          sourceId: event.id.isEmpty ? null : event.id,
          time: event.timestamp,
          hasExplicitTime: true,
          sourceType: 'healthEvent',
        ));
      }
    }

    for (final record in records) {
      final sourceId = record.id.isEmpty ? null : record.id;
      final legacyEmotions = record.emotions
          .where((item) =>
              !quickEmotionKeys.contains(_scoredKey(item.name, item.value)))
          .toList(growable: false);
      final legacySymptoms = record.symptoms
          .where((name) => !quickSymptomNames.contains(name.trim()))
          .toList(growable: false);
      final activityValue = record.stateChanges['activity_change'];

      if (legacyEmotions.isNotEmpty || record.overallMood != null) {
        final parts = <String>[
          ...legacyEmotions.map((item) =>
              item.value == null ? item.name : '${item.name} ${item.value}'),
          if (record.overallMood != null)
            '整體情緒 ${_scoreText(record.overallMood!)}'
        ];
        items.add(
          LifeTimelineItem(
            time: day,
            type: LifeTimelineType.emotion,
            title: '情緒紀錄',
            summary: parts.join('、'),
            sourceId: sourceId,
            hasExplicitTime: false,
            metadata: {
              'sourceType': 'dailyRecord',
              'timestampPrecision': 'day',
              'moodScale': record.moodScale,
              'emotions': legacyEmotions
                  .map((item) => {'name': item.name, 'value': item.value})
                  .toList(growable: false),
              if (record.overallMood != null) 'overallMood': record.overallMood,
            },
          ),
        );
      }

      if (legacySymptoms.isNotEmpty) {
        items.add(
          LifeTimelineItem(
            time: day,
            type: LifeTimelineType.symptom,
            title: '症狀紀錄',
            summary: legacySymptoms.join('、'),
            sourceId: sourceId,
            hasExplicitTime: false,
            metadata: {
              'sourceType': 'dailyRecord',
              'timestampPrecision': 'day',
              'symptoms': legacySymptoms,
            },
          ),
        );
      }

      if (_hasSleepData(record.sleep)) {
        final sleepStart = record.sleep.effectiveSleepStart;
        final sleepTime = sleepStart == null
            ? day
            : DateTime(day.year, day.month, day.day, sleepStart.hour,
                sleepStart.minute);
        final parts = <String>[
          if (record.sleep.durationHours != null)
            '${record.sleep.durationHours} 小時',
          if (record.sleep.quality != null) '品質 ${record.sleep.quality}',
        ];
        items.add(
          LifeTimelineItem(
            time: sleepTime,
            type: LifeTimelineType.sleep,
            title: '睡眠',
            summary: parts.isEmpty ? '已留下睡眠紀錄' : parts.join('、'),
            sourceId: sourceId,
            hasExplicitTime: sleepStart != null,
            metadata: {
              'sourceType': 'dailyRecord',
              'timestampPrecision': sleepStart != null ? 'timestamp' : 'day',
              if (record.sleep.quality != null) 'quality': record.sleep.quality,
              if (record.sleep.flags.isNotEmpty) 'flags': record.sleep.flags,
              if (record.sleep.wakeTime != null)
                'wakeTime': _timeText(record.sleep.wakeTime!),
              if (record.sleep.finalWakeTime != null)
                'finalWakeTime': _timeText(record.sleep.finalWakeTime!),
            },
          ),
        );
      }
      if (activityValue != null &&
          !quickActivityValues.contains(activityValue)) {
        items.add(_activityItem(
          day: day,
          value: activityValue,
          sourceId: sourceId,
          time: day,
          hasExplicitTime: false,
          sourceType: 'dailyRecord',
        ));
      }
    }

    for (final event in medicationAdjustments.where(
      (item) => _sameDay(item.effectiveDateTime, day),
    )) {
      final precise = _hasClockPrecision(event.effectiveDateTime);
      items.add(
        LifeTimelineItem(
          time: precise ? event.effectiveDateTime : day,
          type: LifeTimelineType.medication,
          title: '${event.medName} ${event.typeLabel}',
          summary: event.changeSummary,
          sourceId: event.eventKey,
          hasExplicitTime: precise,
          metadata: {
            'sourceType': 'medAdjustment',
            'timestampPrecision': precise ? 'timestamp' : 'day',
            'adjustmentId': event.adjustmentId,
            'itemIndex': event.itemIndex,
            'medicationId': event.medDocId,
            'medicationName': event.medName,
            'eventType': event.type,
            'adjustmentDateTime': event.date.toIso8601String(),
            'effectiveDateTime': event.effectiveDateTime.toIso8601String(),
            if (event.oldDose != null) 'oldDose': event.oldDose,
            if (event.newDose != null) 'newDose': event.newDose,
            if (event.oldUnit != null) 'oldUnit': event.oldUnit,
            if (event.newUnit != null) 'newUnit': event.newUnit,
          },
        ),
      );
    }

    for (final response in subjectiveMedicationResponses.where(
      (item) => _sameDay(item.recordedAt, day),
    )) {
      final precise = _hasClockPrecision(response.recordedAt);
      final detail = <String>[
        response.medicationName,
        _overallResponseLabel(response.overallResponse),
        if (response.changedAreas.isNotEmpty) response.changedAreas.join('、'),
        if (response.note.trim().isNotEmpty) response.note.trim(),
      ];
      items.add(
        LifeTimelineItem(
          time: precise ? response.recordedAt : day,
          type: LifeTimelineType.subjectiveMedicationResponse,
          title: '用藥反應｜第 ${response.followUpDay} 天',
          summary: detail.join('｜'),
          sourceId: response.id,
          hasExplicitTime: precise,
          metadata: {
            'sourceType': 'medicationSubjectiveResponse',
            'timestampPrecision': precise ? 'timestamp' : 'day',
            'responseId': response.id,
            'adjustmentId': response.changeRecordId,
            'medicationId': response.medicationId,
            'medicationName': response.medicationName,
            'followUpDay': response.followUpDay,
            'overallResponse': response.overallResponse.name,
          },
        ),
      );
    }

    final summary = calendarSummary;
    if (summary != null && _sameDay(summary.date, day)) {
      if (summary.hasDiary) {
        items.add(
          LifeTimelineItem(
            time: day,
            type: LifeTimelineType.diary,
            title: (summary.diaryTitle ?? '').trim().isEmpty
                ? '日記'
                : summary.diaryTitle!.trim(),
            // CalendarDaySummary's diarySummary can be derived from decrypted
            // full content, so the timeline intentionally keeps a safe status
            // summary instead of copying it.
            summary: '這一天有留下日記',
            sourceId: summary.diaryDocId,
            hasExplicitTime: false,
          ),
        );
      }
      if (summary.isPeriodDay || summary.isPredictedPeriodDay) {
        final predicted = !summary.isPeriodDay && summary.isPredictedPeriodDay;
        items.add(
          LifeTimelineItem(
            time: day,
            type: LifeTimelineType.period,
            title: predicted ? '預測生理期' : '生理期',
            summary: predicted ? '預測生理期標記' : '生理期標記',
            hasExplicitTime: false,
            metadata: {'predicted': predicted, 'dateKey': _dateKey(day)},
          ),
        );
      }
    }

    return sortAndDeduplicate(items);
  }

  static List<LifeTimelineItem> sortAndDeduplicate(
    Iterable<LifeTimelineItem> source,
  ) {
    final seen = <String>{};
    final output = <LifeTimelineItem>[];
    for (final item in source) {
      final key = _deduplicationKey(item);
      if (seen.add(key)) output.add(item);
    }
    output.sort(compareItems);
    return List.unmodifiable(output);
  }

  static int compareItems(LifeTimelineItem left, LifeTimelineItem right) {
    final timeOrder = left.time.compareTo(right.time);
    if (timeOrder != 0) return timeOrder;
    if (left.hasExplicitTime != right.hasExplicitTime) {
      return left.hasExplicitTime ? 1 : -1;
    }
    final rankOrder = (fallbackTypeOrder[left.type] ?? 999)
        .compareTo(fallbackTypeOrder[right.type] ?? 999);
    if (rankOrder != 0) return rankOrder;
    return _stableIdentity(left).compareTo(_stableIdentity(right));
  }

  Future<List<_TimelineDocument<Map<String, dynamic>>>>
      _loadDailyRecordDocuments(
    DocumentReference<Map<String, dynamic>> user,
    DateTime day,
    DateTime endExclusive,
  ) async {
    final collection = user.collection('dailyRecords');
    final byId = <String, _TimelineDocument<Map<String, dynamic>>>{};

    Future<void> collect(
      Future<List<_TimelineDocument<Map<String, dynamic>>>> Function() query,
    ) async {
      try {
        for (final doc in await query()) {
          byId[doc.id] = doc;
        }
      } catch (_) {
        // Older collections may not support every query shape.
      }
    }

    await collect(() async {
      final docs = await HealthDataEncryptionService.getEncrypted(
        collection
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(day))
            .where('date', isLessThan: Timestamp.fromDate(endExclusive)),
      );
      return docs
          .map((doc) => _TimelineDocument(doc.id, doc.data))
          .toList(growable: false);
    });
    await collect(() async {
      final lastDay = endExclusive.subtract(const Duration(days: 1));
      final docs = await HealthDataEncryptionService.getEncrypted(
        collection
            .orderBy(FieldPath.documentId)
            .where(
              FieldPath.documentId,
              isGreaterThanOrEqualTo: _dateKey(day),
            )
            .where(
              FieldPath.documentId,
              isLessThanOrEqualTo: _dateKey(lastDay),
            ),
      );
      return docs
          .map((doc) => _TimelineDocument(doc.id, doc.data))
          .toList(growable: false);
    });
    return byId.values.toList(growable: false);
  }

  static List<MedicationSubjectiveResponse> _decodeSubjectiveResponses(
    Iterable<HealthDocument> documents,
  ) {
    final responses = <MedicationSubjectiveResponse>[];
    for (final doc in documents) {
      try {
        final data = <String, dynamic>{'id': doc.id, ...doc.data};
        for (final field in const ['changeDate', 'recordedAt']) {
          final value = data[field];
          if (value is Timestamp) data[field] = value.toDate();
        }
        responses.add(MedicationSubjectiveResponse.fromMap(data));
      } on FormatException {
        // Ignore incomplete legacy responses.
      } on ArgumentError {
        // Ignore unsupported legacy follow-up days.
      }
    }
    return responses;
  }

  static String _deduplicationKey(LifeTimelineItem item) {
    final sourceId = (item.sourceId ?? '').trim();
    if (sourceId.isNotEmpty) return '${item.type}|source:$sourceId';
    if (item.hasExplicitTime) {
      return '${item.type}|time:${item.time.toUtc().toIso8601String()}';
    }
    return '${item.type}|day:${_dateKey(item.time)}|${_stableIdentity(item)}';
  }

  static String _stableIdentity(LifeTimelineItem item) =>
      '${item.sourceId ?? ''}|${item.type}|${item.summary}';

  static bool _hasSleepData(SleepData sleep) =>
      sleep.effectiveSleepStart != null ||
      sleep.wakeTime != null ||
      sleep.finalWakeTime != null ||
      sleep.quality != null ||
      sleep.durationHours != null ||
      sleep.flags.isNotEmpty ||
      (sleep.note ?? '').trim().isNotEmpty;

  static LifeTimelineItem _activityItem({
    required DateTime day,
    required int value,
    required String? sourceId,
    required DateTime time,
    required bool hasExplicitTime,
    required String sourceType,
  }) {
    return LifeTimelineItem(
      time: hasExplicitTime ? time : day,
      type: LifeTimelineType.activity,
      title: '活動量',
      summary: _activityLabel(value),
      sourceId: sourceId,
      hasExplicitTime: hasExplicitTime,
      metadata: {
        'sourceType': sourceType,
        'timestampPrecision': hasExplicitTime ? 'timestamp' : 'day',
        'dimension': 'activity_change',
        'value': value,
      },
    );
  }

  static String _activityLabel(int value) => dailyStateValueLabel(
        kDailyStateDimensionsById['activity_change']!,
        value,
      );

  static bool _hasClockPrecision(DateTime value) =>
      value.hour != 0 ||
      value.minute != 0 ||
      value.second != 0 ||
      value.millisecond != 0 ||
      value.microsecond != 0;

  static String _overallResponseLabel(MedicationOverallResponse value) =>
      switch (value) {
        MedicationOverallResponse.better => '感覺較好',
        MedicationOverallResponse.worse => '感覺較差',
        MedicationOverallResponse.mixed => '好壞皆有',
        MedicationOverallResponse.noChange => '沒有明顯變化',
        MedicationOverallResponse.unsure => '不確定',
      };

  static String _scoreText(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  static String _timeText(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String _scoredKey(String name, int? value) =>
      '${name.trim()}\u0000${value ?? ''}';

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _TimelineDocument<T> {
  const _TimelineDocument(this.id, this.data);

  final String id;
  final T data;
}

class LifeTimelineRangeData {
  const LifeTimelineRangeData({
    required this.start,
    required this.end,
    required this.itemsByDate,
  });

  final DateTime start;
  final DateTime end;
  final Map<DateTime, List<LifeTimelineItem>> itemsByDate;

  int get recordedDayCount =>
      itemsByDate.values.where((items) => items.isNotEmpty).length;
}
