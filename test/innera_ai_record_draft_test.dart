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
      expect(draft.emotions, hasLength(2));
      expect(
        draft.emotions.firstWhere((item) => item.name == '焦慮').score,
        4,
      );
      expect(
        draft.emotions.firstWhere((item) => item.name == '煩躁').score,
        isNull,
      );
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

    test('separates fatigue symptom from initial insomnia', () {
      final draft = InneraAiRecordDraft.empty(DateTime(2026, 7, 23))
          .mergeExplicitRecordFacts('今天很疲倦，晚上很難入睡。');

      expect(draft.symptoms, contains('疲倦'));
      expect(draft.symptoms, isNot(contains('入睡困難')));
      expect(draft.sleep.flags, contains('initInsomnia'));
    });

    test('moves physical and behavioral states out of AI emotions', () {
      final draft = InneraAiRecordDraft.fromMap({
        'dateKey': '2026-07-29',
        'emotionMentions': [
          {'rawText': '疲倦'},
          {'rawText': '動力不足'},
          {'rawText': '食慾增加'},
          {'rawText': '想吐'},
          {'rawText': '煩躁', 'value': 5},
        ],
        'symptoms': ['疲倦', '想吐'],
      });

      expect(draft.emotions.map((item) => item.name), ['煩躁']);
      expect(
        draft.symptoms,
        containsAll(['疲倦', '動力不足', '食慾增加', '想吐']),
      );
      expect(draft.symptoms.toSet(), hasLength(4));
    });

    test('extracts motivation appetite and nausea as symptoms', () {
      final draft = InneraAiRecordDraft.empty(DateTime(2026, 7, 29))
          .mergeExplicitRecordFacts('以前喜歡畫畫，現在完全沒有動力；食慾增加，吃完又會想吐。');

      expect(
        draft.symptoms,
        containsAll(['動力不足', '食慾增加', '想吐']),
      );
      expect(draft.emotions, isEmpty);
    });

    test('cleans symptom-like emotions already held by an open draft', () {
      final openDraft = InneraAiRecordDraft(
        dateKey: '2026-07-29',
        emotions: const [
          AiEmotionDraft(rawText: '動力不足'),
          AiEmotionDraft(rawText: '食慾增加'),
          AiEmotionDraft(rawText: '煩躁', score: 5),
        ],
        updatedAt: DateTime(2026, 7, 29),
      );

      final updated = openDraft.mergePatch({'symptoms': []});

      expect(updated.emotions.map((item) => item.name), ['煩躁']);
      expect(updated.symptoms, containsAll(['動力不足', '食慾增加']));
    });

    test('keeps mentioned boredom and emptiness with null scores', () {
      final draft = InneraAiRecordDraft.empty(DateTime(2026, 7, 23))
          .mergeExplicitRecordFacts('今天很無聊，也很空虛。');

      expect(draft.emotions.map((item) => item.rawText),
          containsAll(['無聊', '空虛']));
      expect(
        draft.emotions.map((item) => item.name),
        containsAll(['無聊', '空虛']),
      );
      expect(draft.emotions.every((item) => item.score == null), isTrue);
      expect(draft.emotions.every((item) => item.needsFollowUp), isTrue);
    });

    test('keeps emotions from different times and overall mood', () {
      final draft = InneraAiRecordDraft.empty(DateTime(2026, 7, 23))
          .mergeExplicitRecordFacts('早上很興奮，下午卻很空虛，心情3分。');

      final excited = draft.emotions.firstWhere((item) => item.name == '興奮');
      final empty = draft.emotions.firstWhere((item) => item.name == '空虛');
      expect(draft.overallMood, 3);
      expect(excited.timeContext, '早上');
      expect(empty.timeContext, '下午');
      expect(excited.score, isNull);
      expect(empty.score, isNull);
    });

    test('removes sleep descriptions from symptoms', () {
      final draft =
          InneraAiRecordDraft.empty(DateTime(2026, 7, 23)).mergePatch({
        'symptoms': ['疲倦', '入睡困難', '想吐'],
      }).mergeExplicitRecordFacts('很疲倦、入睡困難、想吐。');

      expect(draft.symptoms, containsAll(['疲倦', '想吐']));
      expect(draft.symptoms, isNot(contains('入睡困難')));
      expect(draft.sleep.flags, contains('initInsomnia'));
    });

    test('keeps scored and pending emotions together', () {
      final draft = InneraAiRecordDraft.empty(DateTime(2026, 7, 23))
          .mergeExplicitRecordFacts('焦慮4分，無聊但不知道幾分。');

      final anxious = draft.emotions.firstWhere((item) => item.name == '焦慮');
      final bored = draft.emotions.firstWhere((item) => item.name == '無聊');
      expect(anxious.score, 4);
      expect(anxious.needsFollowUp, isFalse);
      expect(bored.score, isNull);
      expect(bored.needsFollowUp, isTrue);
    });

    test('accepts old drafts without emotions or sleep flags', () {
      final draft = InneraAiRecordDraft.fromMap({
        'dateKey': '2026-07-23',
        'sleep': {'sleepTime': '23:30'},
      });

      expect(draft.emotions, isEmpty);
      expect(draft.sleep.flags, isEmpty);
      expect(draft.sleep.sleepTime, '23:30');
    });

    test('does not write previous-day sleep into today draft', () {
      final draft = InneraAiRecordDraft.empty(
        DateTime(2026, 7, 23),
      ).mergeExplicitRecordFacts('今天有點焦慮，昨天半夜醒來好幾次。');

      expect(draft.emotions.single.name, '焦慮');
      expect(draft.sleep.flags, isEmpty);
    });

    test('maps waking up and getting out of bed to different fields', () {
      final draft = InneraAiRecordDraft.empty(
        DateTime(2026, 7, 24),
      ).mergeExplicitRecordFacts('凌晨4點醒來，5點起床。');

      expect(draft.sleep.finalWakeTime, '04:00');
      expect(draft.sleep.wakeTime, '05:00');
    });

    test('explicit wording corrects AI-swapped wake fields', () {
      final draft =
          InneraAiRecordDraft.empty(DateTime(2026, 7, 24)).mergePatch({
        'sleep': {
          'finalWakeTime': '05:00',
          'wakeTime': '04:00',
        },
      }).mergeExplicitRecordFacts('凌晨4點醒來後一直躺著，5點多才起床。');

      expect(draft.sleep.finalWakeTime, '04:00');
      expect(draft.sleep.wakeTime, '05:00');
    });

    test('does not treat a nighttime awakening followed by sleep as final wake',
        () {
      final draft = InneraAiRecordDraft.empty(
        DateTime(2026, 7, 24),
      ).mergeExplicitRecordFacts('半夜2點醒來後又睡著。');

      expect(draft.sleep.finalWakeTime, isNull);
      expect(draft.sleep.flags, contains('interrupted'));
    });

    test('keeps an unknown raw emotion pending without inventing a dimension',
        () {
      final draft = InneraAiRecordDraft.fromMap({
        'dateKey': '2026-07-23',
        'emotionMentions': [
          {
            'rawText': '心裡很亂',
            'normalizedDimensionId': '混亂程度',
            'normalizedDimensionName': '混亂程度',
            'value': null,
            'needsConfirmation': false,
          },
        ],
      });

      final mention = draft.emotions.single;
      expect(mention.rawText, '心裡很亂');
      expect(mention.normalizedDimensionId, isNull);
      expect(mention.normalizedDimensionName, isNull);
      expect(mention.needsConfirmation, isTrue);
    });

    test('deduplicates aliases by the current normalized dimension', () {
      final draft = InneraAiRecordDraft.empty(DateTime(2026, 7, 23))
          .mergeExplicitRecordFacts('今天好無聊，真的很無聊。');

      expect(draft.emotions, hasLength(1));
      expect(draft.emotions.single.normalizedDimensionId, '無聊');
      expect(draft.emotions.single.normalizedDimensionName, '無聊');
    });

    test('keeps legacy degree names unresolved for read compatibility only',
        () {
      final draft = InneraAiRecordDraft.fromMap({
        'dateKey': '2026-07-23',
        'emotions': ['無聊程度'],
      });

      final mention = draft.emotions.single;
      expect(mention.rawText, '無聊程度');
      expect(mention.normalizedDimensionId, isNull);
      expect(mention.needsConfirmation, isTrue);
    });
  });
}
