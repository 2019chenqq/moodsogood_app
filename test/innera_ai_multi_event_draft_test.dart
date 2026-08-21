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
    expect(drafts[1].timeLabel, '下午 3 點左右');
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
    expect(drafts.map((item) => item.timeLabel),
        ['今天早上', '中午', '晚上']);
  });

  test('case 4: a later conversation turn preserves the earlier event', () {
    var drafts = apply(const [], '早上九點頭痛。');
    drafts = apply(
      drafts,
      '對了，下午四點左右我突然很沒精神。',
      DateTime(2026, 8, 21, 16, 30),
    );

    expect(drafts, hasLength(2));
    expect(drafts.map((item) => item.id), containsAll(['time-0900', 'time-1600']));
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
}
