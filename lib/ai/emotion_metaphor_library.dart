import 'ai_diary_draft.dart';

class EmotionMetaphor {
  const EmotionMetaphor({
    required this.id,
    required this.text,
    required this.emotionTags,
    required this.energyLevel,
    required this.valence,
    required this.intensity,
    required this.category,
    this.isReviewed = true,
  });

  final String id;
  final String text;
  final List<String> emotionTags;
  final int energyLevel;
  final int valence;
  final int intensity;
  final String category;
  final bool isReviewed;
}

class EmotionMetaphorLibrary {
  static const items = <EmotionMetaphor>[
    EmotionMetaphor(
      id: 'weather_cloudy',
      text: '像一片暫時散不開的陰天',
      emotionTags: ['低落', '疲憊', '迷惘'],
      energyLevel: 2,
      valence: 2,
      intensity: 3,
      category: '天氣',
    ),
    EmotionMetaphor(
      id: 'light_small_lamp',
      text: '像陰天裡仍亮著的一盞小燈',
      emotionTags: ['疲憊', '期待', '希望'],
      energyLevel: 2,
      valence: 3,
      intensity: 3,
      category: '光線',
    ),
    EmotionMetaphor(
      id: 'ocean_waves',
      text: '像一波接一波、還沒平靜下來的海面',
      emotionTags: ['焦慮', '混亂', '不安'],
      energyLevel: 4,
      valence: 2,
      intensity: 4,
      category: '海洋',
    ),
    EmotionMetaphor(
      id: 'plant_new_leaf',
      text: '像剛長出新葉、仍需要慢慢適應的植物',
      emotionTags: ['期待', '脆弱', '改變'],
      energyLevel: 3,
      valence: 4,
      intensity: 2,
      category: '植物',
    ),
    EmotionMetaphor(
      id: 'animal_hiding_cat',
      text: '像躲到安靜角落、暫時不想被打擾的貓',
      emotionTags: ['疲憊', '不安', '需要空間'],
      energyLevel: 1,
      valence: 2,
      intensity: 3,
      category: '動物',
    ),
    EmotionMetaphor(
      id: 'object_low_battery',
      text: '像電量不多、但還亮著的手機',
      emotionTags: ['疲憊', '撐著', '壓力'],
      energyLevel: 1,
      valence: 2,
      intensity: 4,
      category: '日常物品',
    ),
    EmotionMetaphor(
      id: 'space_crowded_room',
      text: '像待在堆滿東西、需要一點空間的房間',
      emotionTags: ['壓力', '混亂', '煩躁'],
      energyLevel: 3,
      valence: 2,
      intensity: 4,
      category: '空間',
    ),
    EmotionMetaphor(
      id: 'action_slow_walk',
      text: '像走得很慢，卻仍一步一步往前',
      emotionTags: ['疲憊', '堅持', '希望'],
      energyLevel: 2,
      valence: 3,
      intensity: 3,
      category: '行動',
    ),
  ];

  static List<DiaryDraftSuggestion> recommend(
    DiaryEmotionAnalysis profile, {
    int limit = 3,
  }) {
    final tags = {
      profile.primaryEmotion,
      ...profile.secondaryEmotions,
    }.where((item) => item.isNotEmpty).toSet();
    final ranked = items.where((item) => item.isReviewed).map((item) {
      final tagHits =
          item.emotionTags.where((tag) => tags.contains(tag)).length;
      final distance = (item.energyLevel - profile.energy).abs() +
          (item.valence - profile.valence).abs() +
          (item.intensity - profile.intensity).abs();
      return (item: item, score: tagHits * 4 - distance);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return ranked
        .take(limit)
        .map((entry) => DiaryDraftSuggestion(
              value: entry.item.text,
              source: DiaryDraftSource.suggested,
              confidence: (0.9 - (entry.score < 0 ? 0.2 : 0)).clamp(0, 1),
              evidence: '本地審核詞庫：${entry.item.category}；依情緒、活力與強度配對',
            ))
        .toList();
  }
}
