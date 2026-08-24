import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../daily/emotion_dimensions.dart';
import '../daily/health_event_repository.dart';
import '../diary/diary_repository.dart';
import '../models/health_event.dart';
import '../utils/health_data_encryption_service.dart';
import '../models/daily_record.dart';
import 'innera_ai_record_draft.dart';

class InneraAiRecordDraftService {
  InneraAiRecordDraftService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _draftRef(
          String uid, String dateKey) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('aiRecordDrafts')
          .doc(dateKey);
  DocumentReference<Map<String, dynamic>> _recordRef(
          String uid, String dateKey) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .doc(dateKey);

  Future<InneraAiRecordDraft?> loadToday() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    final draft = InneraAiRecordDraft.empty(DateTime.now());
    final snapshot = await _draftRef(uid, draft.dateKey).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    final data =
        await HealthDataEncryptionService.decryptData(snapshot.data()!);
    return InneraAiRecordDraft.fromFirestore(data);
  }

  Future<InneraAiRecordDraft> loadOrCreateToday() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    final existing = await loadToday();
    if (existing != null) return existing;
    final draft = InneraAiRecordDraft.empty(DateTime.now());
    final record = await _recordRef(uid, draft.dateKey).get();
    final result = record.exists && record.data() != null
        ? _fromExistingRecord(
            draft,
            await HealthDataEncryptionService.decryptData(record.data()!),
          )
        : draft;
    await save(result);
    return result;
  }

  Future<void> save(InneraAiRecordDraft draft) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    await HealthDataEncryptionService.setEncrypted(
      _draftRef(uid, draft.dateKey),
      {
        ...draft.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> confirmAndMerge({
    required InneraAiRecordDraft draft,
    required String diaryContent,
    required bool replaceDiary,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    await _saveHealthEventDrafts(uid, draft);
    final recordRef = _recordRef(uid, draft.dateKey);
    await HealthDataEncryptionService.mutateEncrypted(recordRef, (current) {
      final currentEmotions = _emotionMap(current['emotions']);
      final hasLegacyTenPointEmotions =
          (current['moodScale'] as num?)?.toInt() == 10 &&
              currentEmotions.isNotEmpty;
      if (!hasLegacyTenPointEmotions) {
        for (final emotion
            in draft.emotions.where((item) => item.isEligibleUserEmotion)) {
          final score = emotion.score;
          final dimension =
              kEmotionDimensionsById[emotion.normalizedDimensionId];
          if (score != null &&
              dimension != null &&
              dimension.displayName == emotion.normalizedDimensionName) {
            currentEmotions[dimension.displayName] = score;
          }
        }
      }
      final currentSymptoms = _strings(current['symptoms']);
      final legacySymptoms = _strings(current['bodySymptoms']);
      final symptoms =
          {...currentSymptoms, ...legacySymptoms, ...draft.symptoms}.toList();
      final currentStateChanges = _stateChanges(current['stateChanges']);
      currentStateChanges.addAll(draft.stateChanges);
      final bodyMeasurement = Map<String, dynamic>.from(
        current['bodyMeasurement'] is Map
            ? current['bodyMeasurement'] as Map
            : const <String, dynamic>{},
      );
      final draftBodyMeasurement = draft.bodyMeasurement?.toJson();
      draftBodyMeasurement?.forEach((key, value) {
        if (value != null) bodyMeasurement[key] = value;
      });
      if (draft.bodyMeasurement?.measurementTiming != null) {
        bodyMeasurement['customMeasurementTime'] =
            draft.bodyMeasurement?.effectiveCustomMeasurementTime;
      }
      final sleep = Map<String, dynamic>.from(
        current['sleep'] is Map
            ? current['sleep'] as Map
            : const <String, dynamic>{},
      );
      final patchSleep = draft.sleep.toMap();
      patchSleep.forEach((key, value) {
        final meaningful =
            value is List ? value.isNotEmpty : value != null && value != '';
        if (meaningful) sleep[key] = value;
      });
      return {
        ...current,
        'date': Timestamp.fromDate(DateTime.parse(draft.dateKey)),
        if (!hasLegacyTenPointEmotions) ...{
          'moodScale': 5,
          'emotions': currentEmotions.entries
              .map((entry) => {'name': entry.key, 'value': entry.value})
              .toList(),
          'overallMood': draft.overallMood ?? current['overallMood'],
        },
        'symptoms': symptoms,
        'bodySymptoms': symptoms,
        'stateChanges': currentStateChanges,
        'symptomSectionCompleted': true,
        'emotionSectionCompleted': true,
        if (draft.stateChanges.isNotEmpty) 'stateSectionCompleted': true,
        if (bodyMeasurement.isNotEmpty) 'bodyMeasurement': bodyMeasurement,
        'sleep': sleep,
        'updatedAt': FieldValue.serverTimestamp(),
      };
    });

    if (diaryContent.trim().isNotEmpty) {
      final date = DateTime.parse(draft.dateKey);
      final diaryRepository = DiaryRepository();
      final existingDiary = await diaryRepository.getByDate(date);
      final nextDiary = diaryContent.trim();
      final existingContent = existingDiary?.content.trim() ?? '';
      final content = existingDiary == null || replaceDiary
          ? nextDiary
          : existingContent == nextDiary || existingContent.contains(nextDiary)
              ? existingContent
              : '$existingContent\n\n$nextDiary'.trim();
      await diaryRepository.upsert(DiaryEntry(
        date: date,
        title: existingDiary?.title ?? '每日紀錄',
        content: content,
        moodScore: draft.overallMood ?? existingDiary?.moodScore,
        moodKeyword: existingDiary?.moodKeyword,
      ));
    }
    await HealthDataEncryptionService.setEncrypted(
      _draftRef(uid, draft.dateKey),
      {
        ...draft.copyWith(confirmed: true).toFirestore(),
        'confirmedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> confirmHealthEvents(InneraAiRecordDraft draft) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    await _saveHealthEventDrafts(uid, draft);
    await save(draft.copyWith(confirmed: true));
  }

  Future<void> _saveHealthEventDrafts(
    String uid,
    InneraAiRecordDraft draft,
  ) async {
    final repository = HealthEventRepository();
    for (final event in buildConfirmedHealthEvents(draft)) {
      await repository.upsertConfirmedDraft(
        userId: uid,
        eventId: event.id,
        event: event,
      );
    }
  }

  InneraAiRecordDraft _fromExistingRecord(
      InneraAiRecordDraft base, Map<String, dynamic> data) {
    final isLegacyTenPoint = (data['moodScale'] as num?)?.toInt() == 10;
    final emotions =
        (isLegacyTenPoint ? <String, int>{} : _emotionMap(data['emotions']))
            .entries
            .map((entry) {
      final dimension = resolveEmotionDimension(entry.key);
      return AiEmotionDraft(
        rawText: entry.key,
        normalizedDimensionId: dimension?.id,
        normalizedDimensionName: dimension?.displayName,
        score: entry.value.clamp(1, 5),
        source: AiDraftSource.existingRecord,
        confidence: dimension == null ? 0 : 1,
        needsConfirmation: dimension == null,
        subjectType: AiEmotionSubjectType.user,
        subjectText: '我',
      );
    }).toList();
    final storedSleep = data['sleep'] is Map
        ? Map<String, dynamic>.from(data['sleep'] as Map)
        : <String, dynamic>{};
    return InneraAiRecordDraft(
      dateKey: base.dateKey,
      // Never reinterpret a stored 10-point score as a new 5-point score.
      overallMood: isLegacyTenPoint ? null : _score(data['overallMood']),
      emotions: emotions,
      symptoms: {
        ..._strings(data['symptoms']),
        ..._strings(data['bodySymptoms'])
      }.toList(),
      stateChanges: _stateChanges(data['stateChanges']),
      bodyMeasurement: data['bodyMeasurement'] is Map
          ? BodyMeasurement.fromJson(
              (data['bodyMeasurement'] as Map).cast<String, dynamic>(),
            )
          : null,
      sleep: AiSleepDraft.fromMap(storedSleep),
      eventDrafts: base.eventDrafts,
      updatedAt: DateTime.now(),
      hasExistingRecord: true,
    );
  }

  static Map<String, int> _emotionMap(dynamic value) {
    final result = <String, int>{};
    if (value is List) {
      for (final item in value.whereType<Map>()) {
        final name = item['name']?.toString().trim() ?? '';
        final score = (item['value'] as num?)?.toInt();
        if (name.isNotEmpty && score != null) {
          result[name] = score;
        }
      }
    } else if (value is Map) {
      value.forEach((key, item) {
        final score = (item as num?)?.toInt();
        if (key.toString().trim().isNotEmpty && score != null) {
          result[key.toString()] = score;
        }
      });
    }
    return result;
  }

  static List<String> _strings(dynamic value) => value is List
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];
  static Map<String, int> _stateChanges(dynamic value) {
    if (value is! Map) return <String, int>{};
    final result = <String, int>{};
    for (final entry in value.entries) {
      final score = (entry.value as num?)?.toInt();
      if (score != null && score >= 1 && score <= 5) {
        result[entry.key.toString()] = score;
      }
    }
    return result;
  }

  static double? _score(dynamic value) {
    final score = (value as num?)?.toDouble();
    return score != null && score >= 1 && score <= 5 ? score : null;
  }
}

List<HealthEvent> buildConfirmedHealthEvents(InneraAiRecordDraft draft) {
  final day = DateTime.parse(draft.dateKey);
  return draft.eventDrafts.where((item) => item.hasContent).map((item) {
    final sourceTime = item.eventTime ?? draft.updatedAt;
    final timestamp = DateTime(
      day.year,
      day.month,
      day.day,
      sourceTime.hour,
      sourceTime.minute,
    );
    final rawEventId =
        'ai-${draft.dateKey}-${item.id}'.replaceAll(RegExp(r'[/\\]'), '-');
    final eventId =
        rawEventId.length <= 240 ? rawEventId : rawEventId.substring(0, 240);
    return HealthEvent(
      id: eventId,
      timestamp: timestamp,
      symptoms: item.symptoms
          .map((name) => HealthEventSymptom(
                name: name,
                severity: item.symptomSeverities[name],
              ))
          .toList(),
      emotions: item.emotions
          .where((emotion) => emotion.score != null)
          .map(
            (emotion) => HealthEventEmotion(
              name: emotion.normalizedDimensionName ?? emotion.rawText,
              intensity: emotion.score!,
            ),
          )
          .toList(),
      stateChanges: item.stateChanges,
      timePrecision: item.timePrecision.name,
      context: item.timeContext,
      note: item.note.isNotEmpty ? item.note : item.rawUserEntries.join('\n'),
    );
  }).toList();
}
