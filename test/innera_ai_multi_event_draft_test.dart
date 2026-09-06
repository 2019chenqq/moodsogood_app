import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_health_event_draft.dart';
import 'package:moodsogood_app/ai/innera_ai_record_draft.dart';
import 'package:moodsogood_app/ai/innera_ai_record_draft_service.dart';

void main() {
  final morning = DateTime(2026, 8, 21, 9);

  List<InneraAiHealthEventDraft> apply(
    List<InneraAiHealthEventDraft> existing,
    String text, [
    DateTime? at,
  ]) =>
      mergeExplicitHealthEventDrafts(
        existing: existing,
        text: text,
        messageTime: at ?? morning,
      );

  test('case 1: different morning and afternoon times create two events', () {
    var drafts = apply(const [], '今天早上起床的時候頭很痛。');
    drafts = apply(drafts, '下午三點左右頭痛好多了，但是變得很累。');

    expect(drafts, hasLength(2));
    expect(drafts[0].timeLabel, '今天早上');
    expect(drafts[0].symptoms, contains('頭痛'));
    expect(drafts[1].timeLabel, '15:00');
    expect(drafts[1].symptoms, containsAll(['頭痛', '疲倦']));
  });

  test('case 2: same-time follow-up updates the active event', () {
    var drafts = apply(const [], '下午三點我很累。');
    drafts = apply(drafts, '那時候還有一點頭痛。');

    expect(drafts, hasLength(1));
    expect(drafts.single.symptoms, containsAll(['疲倦', '頭痛']));
  });

  test('case 3: three identifiable periods create three candidates', () {
    final drafts = apply(const [], '早上起來很累，中午比較好了，晚上又開始頭痛。');

    expect(drafts, hasLength(3));
    expect(drafts.map((item) => item.timeLabel), ['今天早上', '中午', '晚上']);
  });

  test('case 4: a later conversation turn preserves the earlier event', () {
    var drafts = apply(const [], '早上九點頭痛。');
    drafts = apply(
      drafts,
      '對了，下午四點左右我突然很沒精神。',
      DateTime(2026, 8, 21, 16, 30),
    );

    expect(drafts, hasLength(2));
    expect(
        drafts.map((item) => item.id), containsAll(['time-0900', 'time-1600']));
  });

  test('case 5: previous-night sleep does not replace the morning event', () {
    final drafts = apply(const [], '昨晚只睡四個小時，今天早上起來超累。');

    expect(drafts, hasLength(1));
    expect(drafts.single.timeLabel, '今天早上');
    expect(drafts.single.symptoms, contains('疲倦'));
    expect(drafts.single.rawUserEntries, isNot(contains('昨晚只睡四個小時')));
  });

  test('confirmation conversion creates one HealthEvent per valid draft', () {
    final candidates = apply(
      const [],
      '早上起來很累，中午比較好了，晚上又開始頭痛。',
    );
    final draft = InneraAiRecordDraft(
      dateKey: '2026-08-21',
      eventDrafts: candidates,
      updatedAt: morning,
    );

    final events = buildConfirmedHealthEvents(draft);

    expect(events, hasLength(3));
    expect(events.map((item) => item.id).toSet(), hasLength(3));
  });

  test('event drafts survive callable and persisted map round-trips', () {
    final candidates = apply(const [], '早上頭痛，晚上很累。');
    final draft = InneraAiRecordDraft(
      dateKey: '2026-08-21',
      eventDrafts: candidates,
      updatedAt: morning,
    );

    final restored = InneraAiRecordDraft.fromMap(draft.toCallablePayload());

    expect(restored.eventDrafts, hasLength(2));
    expect(restored.eventDrafts.map((item) => item.id).toSet(), hasLength(2));
  });

  test('persisted same-minute duplicate ids are consolidated on load', () {
    final restored = InneraAiRecordDraft.fromMap({
      'dateKey': '2026-08-24',
      'eventDrafts': [
        {
          'id': 'now',
          'eventTime': '2026-08-24T12:00:00.000',
          'timePrecision': 'approximate',
          'emotionMentions': const [],
          'symptoms': const [
            {'name': '心悸', 'severity': 4},
          ],
          'stateChanges': const {},
          'rawUserEntries': const [],
          'note': '第一筆',
        },
        {
          'id': 'current-status',
          'eventTime': '2026-08-24T12:00:00.000',
          'timePrecision': 'approximate',
          'emotionMentions': const [],
          'symptoms': const [
            {'name': '心悸', 'severity': 1},
          ],
          'stateChanges': const {},
          'rawUserEntries': const [],
          'note': '第二筆',
        },
      ],
    });

    expect(restored.eventDrafts, hasLength(1));
    expect(restored.eventDrafts.single.symptomSeverities['心悸'], 1);
    expect(restored.eventDrafts.single.note, '第二筆');
  });

  test('explicit symptom severity survives confirmation without a default', () {
    final candidates = apply(const [], '下午三點心悸，大概4分。現在反胃。');
    final draft = InneraAiRecordDraft(
      dateKey: '2026-08-21',
      eventDrafts: candidates,
      updatedAt: morning,
    );
    final events = buildConfirmedHealthEvents(draft);

    expect(events, hasLength(2));
    expect(events.first.symptoms.single.severity, 4);
    expect(events.last.symptoms.single.severity, isNull);
  });

  test('event-level emotion and symptom scores survive confirmation edits', () {
    final event = InneraAiHealthEventDraft(
      id: 'now',
      timeContext: '現在',
      emotions: const [
        AiEmotionDraft(
          rawText: '煩躁',
          normalizedDimensionId: '煩躁',
          normalizedDimensionName: '煩躁',
          score: 3,
        ),
      ],
      symptoms: const ['頭痛'],
      symptomSeverities: const {'頭痛': 2},
      stateChanges: const {'energy_change': 2},
    );
    final draft = InneraAiRecordDraft(
      dateKey: '2026-08-24',
      eventDrafts: [event],
      updatedAt: morning,
    )
        .withEventEmotionScore('now', '煩躁', 4)
        .withEventSymptomSeverity('now', '頭痛', 5)
        .withEventStateChange('now', 'energy_change', 3);

    final confirmed = buildConfirmedHealthEvents(draft).single;
    expect(confirmed.emotions.single.name, '煩躁');
    expect(confirmed.emotions.single.intensity, 4);
    expect(confirmed.symptoms.single.name, '頭痛');
    expect(confirmed.symptoms.single.severity, 5);
    expect(confirmed.stateChanges, {'energy_change': 3});
  });

  test('current event merges with AI now draft and displays the message time',
      () {
    const aiDraft = InneraAiHealthEventDraft(
      id: 'now',
      timeContext: 'now',
      symptoms: ['疲倦'],
    );
    final messageTime = DateTime(2026, 8, 24, 11, 8);

    final drafts = apply([aiDraft], '我現在覺得疲倦。', messageTime);

    expect(drafts, hasLength(1));
    expect(drafts.single.id, 'now');
    expect(drafts.single.eventTime, messageTime);
    expect(drafts.single.timeLabel, '11:08');
  });

  test('explicit clock time is displayed before a broad time context', () {
    final event = InneraAiHealthEventDraft(
      id: 'morning',
      eventTime: DateTime(2026, 8, 24, 8),
      timeContext: 'morning',
      timePrecision: AiEventTimePrecision.exact,
      note: '早上8點起床',
    );

    expect(event.timeLabel, '08:00');
  });

  test('local fallback merges a same-minute event with a different id', () {
    final atNoon = DateTime(2026, 8, 24, 12);
    final existing = InneraAiHealthEventDraft(
      id: 'current-status',
      eventTime: atNoon,
      timeContext: '現在',
      symptoms: const ['心悸'],
      symptomSeverities: const {'心悸': 4},
    );

    final drafts = apply([existing], '我現在心悸 1 分。', atNoon);

    expect(drafts, hasLength(1));
    expect(drafts.single.id, 'current-status');
    expect(drafts.single.symptomSeverities['心悸'], 1);
  });

  test('energy score updates energy without changing fatigue severity', () {
    const existing = InneraAiHealthEventDraft(
      id: 'now',
      eventTime: null,
      timeContext: '現在',
      symptoms: ['疲倦'],
      symptomSeverities: {'疲倦': 4},
    );

    final drafts = apply([existing], '我能量大概兩分。');

    expect(drafts, hasLength(1));
    expect(drafts.single.stateChanges['energy_change'], 2);
    expect(drafts.single.symptomSeverities['疲倦'], 4);
  });

  test('same-id response cannot overwrite an established event time', () {
    final original = InneraAiHealthEventDraft(
      id: 'stable',
      eventTime: DateTime(2026, 8, 24, 15, 15),
      timeContext: '現在',
      symptoms: const ['心悸'],
    );
    final modelPatch = InneraAiHealthEventDraft(
      id: 'stable',
      eventTime: DateTime(2026, 8, 24, 8),
      timeContext: '早上8點',
      timePrecision: AiEventTimePrecision.exact,
      symptoms: const ['心悸'],
    );

    final merged = original.merge(modelPatch);

    expect(merged.id, 'stable');
    expect(merged.eventTime, DateTime(2026, 8, 24, 15, 15));
    expect(merged.timeContext, '現在');
  });

  test('explicit correction updates only the active event without a duplicate',
      () {
    final unrelated = InneraAiHealthEventDraft(
      id: 'morning',
      eventTime: DateTime(2026, 8, 24, 8),
      timeContext: '早上8點',
      timePrecision: AiEventTimePrecision.exact,
      symptoms: const ['頭痛'],
    );
    final target = InneraAiHealthEventDraft(
      id: 'latest',
      eventTime: DateTime(2026, 8, 24, 15),
      timeContext: '下午3點',
      timePrecision: AiEventTimePrecision.exact,
      symptoms: const ['心悸'],
    );

    final drafts = apply(
      [unrelated, target],
      '剛剛那筆其實是下午2點，不是3點。',
      DateTime(2026, 8, 24, 15, 20),
    );

    expect(drafts, hasLength(2));
    expect(
      drafts.firstWhere((item) => item.id == 'latest').eventTime,
      DateTime(2026, 8, 24, 14),
    );
    expect(
      drafts.firstWhere((item) => item.id == 'morning').eventTime,
      DateTime(2026, 8, 24, 8),
    );
  });

  test(
      'physical continuation reuses backend-handled event with null time context',
      () {
    final existing = InneraAiHealthEventDraft(
      id: 'active-event',
      eventTime: DateTime(2026, 8, 26, 16, 1),
      symptoms: const ['心悸', '手抖', '噁心反胃'],
    );

    final drafts = mergeExplicitHealthEventDrafts(
      existing: [existing],
      text: '剛剛也有點噁心',
      messageTime: DateTime(2026, 8, 26, 16, 2),
      allowPhysicalContinuation: true,
    );

    expect(drafts, hasLength(1));
    expect(drafts.single.id, 'active-event');
    expect(drafts.single.eventTime, DateTime(2026, 8, 26, 16, 1));
    expect(drafts.single.symptoms, ['心悸', '手抖', '噁心反胃']);
  });

  test('physical explicit new time does not reuse the active event', () {
    final existing = InneraAiHealthEventDraft(
      id: 'active-event',
      eventTime: DateTime(2026, 8, 26, 16, 1),
      symptoms: const ['心悸'],
    );

    final drafts = mergeExplicitHealthEventDrafts(
      existing: [existing],
      text: '下午2點又心悸',
      messageTime: DateTime(2026, 8, 26, 16, 2),
      allowPhysicalContinuation: true,
    );

    expect(drafts, hasLength(2));
    expect(
      drafts.firstWhere((item) => item.id == 'active-event').eventTime,
      DateTime(2026, 8, 26, 16, 1),
    );
    expect(
      drafts.where((item) => item.eventTime == DateTime(2026, 8, 26, 14)),
      hasLength(1),
    );
  });

  test('physical conjunction without a new time updates the active event', () {
    final existing = InneraAiHealthEventDraft(
      id: 'active-event',
      eventTime: DateTime(2026, 8, 26, 16, 1),
      symptoms: const ['心悸'],
    );

    final drafts = mergeExplicitHealthEventDrafts(
      existing: [existing],
      text: '而且頭痛',
      messageTime: DateTime(2026, 8, 26, 16, 2),
      allowPhysicalContinuation: true,
    );

    expect(drafts, hasLength(1));
    expect(drafts.single.id, 'active-event');
    expect(drafts.single.symptoms, ['心悸', '頭痛']);
  });

  test('physical fallback canonicalizes aliases without duplicate symptoms',
      () {
    final existing = InneraAiHealthEventDraft(
      id: 'active-event',
      eventTime: DateTime(2026, 8, 26, 17, 30),
      symptoms: const ['噁心'],
      rawUserEntries: const ['我有點噁心'],
    );

    final drafts = mergeExplicitHealthEventDrafts(
      existing: [existing],
      text: '還是有點反胃',
      messageTime: DateTime(2026, 8, 26, 17, 31),
      allowPhysicalContinuation: true,
    );

    expect(drafts, hasLength(1));
    expect(drafts.single.symptoms, ['噁心反胃']);
  });

  test('physical fallback keeps explicit symptoms and per-symptom severity',
      () {
    final drafts = mergeExplicitHealthEventDrafts(
      existing: const [],
      text: '心悸4分，手抖，胃有點痛，還有點反胃',
      messageTime: DateTime(2026, 8, 26, 17, 30),
      allowPhysicalContinuation: true,
    );

    expect(drafts, hasLength(1));
    expect(
      drafts.single.symptoms,
      containsAll(['心悸', '手抖', '胃痛', '噁心反胃']),
    );
    expect(drafts.single.symptomSeverities, {'心悸': 4});
  });

  test('physical fallback carries one symptom into an explicit recurrence', () {
    final existing = InneraAiHealthEventDraft(
      id: 'recent',
      eventTime: DateTime(2026, 8, 26, 17, 30),
      symptoms: const ['頭痛'],
      rawUserEntries: const ['剛剛頭痛'],
    );

    final drafts = mergeExplicitHealthEventDrafts(
      existing: [existing],
      text: '晚上9點又痛了一次',
      messageTime: DateTime(2026, 8, 26, 18),
      allowPhysicalContinuation: true,
    );

    expect(drafts, hasLength(2));
    expect(drafts.firstWhere((item) => item.id == 'recent').symptoms, ['頭痛']);
    expect(
      drafts
          .firstWhere((item) => item.eventTime == DateTime(2026, 8, 26, 21))
          .symptoms,
      ['頭痛'],
    );
  });

  test('physical fallback does not guess an ambiguous recurrence symptom', () {
    final existing = InneraAiHealthEventDraft(
      id: 'recent',
      eventTime: DateTime(2026, 8, 26, 17, 30),
      symptoms: const ['頭痛', '心悸'],
      rawUserEntries: const ['剛剛頭痛又心悸'],
    );

    final drafts = mergeExplicitHealthEventDrafts(
      existing: [existing],
      text: '晚上9點又不舒服',
      messageTime: DateTime(2026, 8, 26, 18),
      allowPhysicalContinuation: true,
    );

    expect(drafts, hasLength(2));
    expect(
      drafts.firstWhere((item) => item.id == 'recent').symptoms,
      ['頭痛', '心悸'],
    );
    expect(
      drafts
          .firstWhere((item) => item.eventTime == DateTime(2026, 8, 26, 21))
          .symptoms,
      isEmpty,
    );
  });

  test('physical fallback creates the explicit 08:00 sleepiness event', () {
    final existing = InneraAiHealthEventDraft(
      id: 'current',
      eventTime: DateTime(2026, 8, 29, 9, 13),
      symptoms: const ['心悸', '手抖', '噁心反胃'],
    );

    final drafts = mergeExplicitHealthEventDrafts(
      existing: [existing],
      text: '早上8點嗜睡3分',
      messageTime: DateTime(2026, 8, 29, 9, 14),
      allowPhysicalContinuation: true,
    );

    expect(drafts, hasLength(2));
    final current = drafts.firstWhere((item) => item.id == 'current');
    expect(current.eventTime, DateTime(2026, 8, 29, 9, 13));
    expect(current.symptoms, ['心悸', '手抖', '噁心反胃']);
    expect(current.symptomSeverities, isEmpty);
    final morning = drafts.firstWhere(
      (item) => item.eventTime == DateTime(2026, 8, 29, 8),
    );
    expect(morning.symptoms, ['白天嗜睡']);
    expect(morning.symptomSeverities, {'白天嗜睡': 3});
  });
}
