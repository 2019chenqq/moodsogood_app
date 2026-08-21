import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_health_event_draft.dart';
import 'package:moodsogood_app/ai/innera_ai_record_draft.dart';
import 'package:moodsogood_app/ai/innera_ai_record_draft_service.dart';

void main() {
  InneraAiHealthEventDraft event(String id, String context, String note) =>
      InneraAiHealthEventDraft(
        id: id,
        timeContext: context,
        timePrecision: AiEventTimePrecision.approximate,
        symptoms: const ['頭痛'],
        rawUserEntries: [note],
        note: note,
      );

  test('summary updates only its matching event id', () {
    final draft = InneraAiRecordDraft.empty(DateTime(2026, 8, 21)).mergePatch({
      'eventDrafts': [
        event('morning', '早上', '早上原文').toMap(),
        event('afternoon', '下午', '下午原文').toMap(),
        event('evening', '晚上', '晚上原文').toMap(),
      ],
    });
    final updated = draft.withEventSummary('afternoon', '下午感到疲累。');
    expect(updated.eventDrafts[0].note, '早上原文');
    expect(updated.eventDrafts[1].note, '下午感到疲累。');
    expect(updated.eventDrafts[2].note, '晚上原文');
  });

  test('three event summaries persist into three HealthEvent notes', () {
    var draft = InneraAiRecordDraft.empty(DateTime(2026, 8, 21)).mergePatch({
      'eventDrafts': [
        event('morning', '早上', '早上原文').toMap(),
        event('noon', '中午', '中午原文').toMap(),
        event('evening', '晚上', '晚上原文').toMap(),
      ],
    });
    draft = draft
        .withEventSummary('morning', '早上感到疲累。')
        .withEventSummary('noon', '中午精神不錯。')
        .withEventSummary('evening', '晚上開始頭痛。');
    final events = buildConfirmedHealthEvents(draft);
    expect(events, hasLength(3));
    expect(events.map((item) => item.note), [
      '早上感到疲累。',
      '中午精神不錯。',
      '晚上開始頭痛。',
    ]);
  });
}
