import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/ai_diary_draft.dart';
import 'package:moodsogood_app/ai/emotion_metaphor_library.dart';

void main() {
  group('AiDiaryDraft parsing', () {
    test('keeps partial AI output usable instead of failing the whole draft',
        () {
      final draft = AiDiaryDraft.fromMap({
        'id': '2026-07-23',
        'recordDate': '2026-07-23',
        'titleSuggestions': [
          {
            'value': '疲憊但仍在整理的一天',
            'source': 'summarized',
            'confidence': 0.9,
            'evidence': '使用者提到疲憊與整理需求',
          },
        ],
        'missingFields': ['gratitude'],
      });

      expect(draft.titleSuggestions, hasLength(1));
      expect(draft.content, isNull);
      expect(draft.gratitudeSuggestions, isEmpty);
      expect(draft.missingFields, contains('gratitude'));
      expect(draft.status, AiDiaryDraftStatus.pendingReview);
    });

    test('unknown source is treated as missing, never as explicit', () {
      final item = DiaryDraftSuggestion.fromMap({
        'value': '沒有可靠來源的文字',
        'source': 'unknown',
        'confidence': 4,
      });

      expect(item.source, DiaryDraftSource.missing);
      expect(item.confidence, 1);
    });

    test('keeps only verified song results with stable IDs and links', () {
      final draft = AiDiaryDraft.fromMap({
        'id': '2026-07-23',
        'recordDate': '2026-07-23',
        'songRecommendations': [
          {
            'candidateId': 'candidate_01',
            'provider': 'spotify',
            'providerTrackId': 'spotify-id',
            'title': '真實歌名',
            'artist': '真實歌手',
            'externalUrl': 'https://open.spotify.com/track/spotify-id',
          },
          {
            'candidateId': 'candidate_02',
            'provider': 'spotify',
            'providerTrackId': '',
            'title': '缺少穩定 ID',
            'artist': '歌手',
            'externalUrl': 'https://example.com',
          },
        ],
      });

      expect(draft.songRecommendations, hasLength(1));
      expect(draft.songRecommendations.single.providerTrackId, 'spotify-id');
    });
  });

  group('EmotionMetaphorLibrary', () {
    test('returns three reviewed local candidates for an emotion profile', () {
      const profile = DiaryEmotionAnalysis(
        primaryEmotion: '疲憊',
        secondaryEmotions: ['希望'],
        valence: 2,
        energy: 2,
        intensity: 4,
      );

      final results = EmotionMetaphorLibrary.recommend(profile);

      expect(results, hasLength(3));
      expect(
        results.every((item) => item.source == DiaryDraftSource.suggested),
        isTrue,
      );
      expect(
        results.every((item) => item.evidence.contains('本地審核詞庫')),
        isTrue,
      );
    });
  });
}
