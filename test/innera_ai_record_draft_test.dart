import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_record_draft.dart';

void main() {
  group('InneraAiRecordDraft', () {
    test('keeps all new AI drafts on the 1 to 5 mood scale', () {
      final draft =
          InneraAiRecordDraft.empty(DateTime(2026, 7, 17)).mergePatch({
        'moodScale': 10,
        'emotions': [
          {'name': '焦慮', 'score': 4},
          {'name': '煩躁', 'score': 8},
        ],
      });

      expect(draft.moodScale, 5);
      expect(draft.emotions, hasLength(1));
      expect(draft.emotions.single.name, '焦慮');
      expect(draft.emotions.single.score, 4);
    });

    test('merges later explicit information without clearing sleep', () {
      final initial =
          InneraAiRecordDraft.empty(DateTime(2026, 7, 17)).mergePatch({
        'sleep': {'sleepTime': '02:00', 'wakeTime': '08:00'},
        'symptoms': ['疲倦'],
      });
      final updated = initial.mergePatch({
        'emotions': [
          {'name': '煩躁', 'score': 5},
        ],
        'symptoms': ['頭痛'],
      });

      expect(updated.sleep.sleepTime, '02:00');
      expect(updated.sleep.wakeTime, '08:00');
      expect(updated.symptoms, containsAll(['疲倦', '頭痛']));
      expect(updated.emotions.single.score, 5);
    });
  });
}
