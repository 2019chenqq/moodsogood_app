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
    EmotionMetaphor(
      id: 'weather_sunshower',
      text: '像陽光和細雨同時落下，明亮裡也帶著一點潮濕',
      emotionTags: ['開心', '感傷', '複雜'],
      energyLevel: 3,
      valence: 3,
      intensity: 3,
      category: '天氣',
    ),
    EmotionMetaphor(
      id: 'weather_thunder_faraway',
      text: '像遠處傳來的悶雷，還沒靠近卻讓人一直留意',
      emotionTags: ['焦慮', '擔心', '警覺'],
      energyLevel: 4,
      valence: 2,
      intensity: 4,
      category: '聲音',
    ),
    EmotionMetaphor(
      id: 'weather_after_rain',
      text: '像大雨剛停，空氣還濕著，但已經能慢慢看清遠方',
      emotionTags: ['釋然', '疲憊', '希望'],
      energyLevel: 2,
      valence: 3,
      intensity: 3,
      category: '風景',
    ),
    EmotionMetaphor(
      id: 'water_still_lake',
      text: '像沒有風的湖面，安靜得能看見自己的倒影',
      emotionTags: ['平靜', '安心', '沉澱'],
      energyLevel: 1,
      valence: 4,
      intensity: 2,
      category: '水面',
    ),
    EmotionMetaphor(
      id: 'water_swirl',
      text: '像水裡的小漩渦，幾個念頭繞在一起還找不到出口',
      emotionTags: ['混亂', '糾結', '焦慮'],
      energyLevel: 3,
      valence: 2,
      intensity: 4,
      category: '水流',
    ),
    EmotionMetaphor(
      id: 'road_crossroads',
      text: '像站在岔路口，每個方向都看得見，卻還不確定要往哪裡走',
      emotionTags: ['猶豫', '迷惘', '不安'],
      energyLevel: 2,
      valence: 2,
      intensity: 3,
      category: '道路',
    ),
    EmotionMetaphor(
      id: 'road_downhill_bike',
      text: '像騎車順著緩坡前進，輕快得想多看看沿途風景',
      emotionTags: ['開心', '輕鬆', '期待'],
      energyLevel: 4,
      valence: 5,
      intensity: 3,
      category: '旅程',
    ),
    EmotionMetaphor(
      id: 'object_tangled_earphones',
      text: '像口袋裡纏在一起的耳機線，需要一點耐心慢慢解開',
      emotionTags: ['煩躁', '混亂', '無奈'],
      energyLevel: 3,
      valence: 2,
      intensity: 3,
      category: '日常物品',
    ),
    EmotionMetaphor(
      id: 'object_full_backpack',
      text: '像背著裝得太滿的背包，每一步都比平常更費力',
      emotionTags: ['壓力', '疲憊', '負擔'],
      energyLevel: 2,
      valence: 2,
      intensity: 4,
      category: '重量',
    ),
    EmotionMetaphor(
      id: 'object_kettle',
      text: '像水壺裡的熱氣越積越多，很需要一個能安全透氣的出口',
      emotionTags: ['生氣', '煩躁', '壓力'],
      energyLevel: 5,
      valence: 1,
      intensity: 5,
      category: '溫度',
    ),
    EmotionMetaphor(
      id: 'object_unread_book',
      text: '像翻到一本書的新章節，還不知道後面會發生什麼',
      emotionTags: ['好奇', '期待', '不確定'],
      energyLevel: 3,
      valence: 4,
      intensity: 2,
      category: '書頁',
    ),
    EmotionMetaphor(
      id: 'space_small_window',
      text: '像悶熱房間裡開了一扇小窗，終於有一點新鮮空氣進來',
      emotionTags: ['釋然', '希望', '安心'],
      energyLevel: 2,
      valence: 4,
      intensity: 3,
      category: '空間',
    ),
    EmotionMetaphor(
      id: 'space_empty_station',
      text: '像站在末班車離開後的月台，安靜裡帶著一點落空',
      emotionTags: ['孤單', '失落', '空虛'],
      energyLevel: 1,
      valence: 1,
      intensity: 4,
      category: '場景',
    ),
    EmotionMetaphor(
      id: 'space_busy_market',
      text: '像走進聲音很多的市場，注意力被四面八方拉著走',
      emotionTags: ['煩躁', '混亂', '緊張'],
      energyLevel: 5,
      valence: 2,
      intensity: 4,
      category: '人群',
    ),
    EmotionMetaphor(
      id: 'plant_bending_grass',
      text: '像被風吹彎的草，承受著力道，也還保留回彈的空間',
      emotionTags: ['壓力', '委屈', '堅持'],
      energyLevel: 3,
      valence: 2,
      intensity: 4,
      category: '植物',
    ),
    EmotionMetaphor(
      id: 'plant_blooming',
      text: '像花苞終於打開一點，想把此刻的喜悅好好留住',
      emotionTags: ['開心', '成就感', '期待'],
      energyLevel: 4,
      valence: 5,
      intensity: 4,
      category: '成長',
    ),
    EmotionMetaphor(
      id: 'animal_alert_deer',
      text: '像聽見細微聲響的小鹿，身體還維持著警覺',
      emotionTags: ['緊張', '不安', '害怕'],
      energyLevel: 4,
      valence: 2,
      intensity: 4,
      category: '動物',
    ),
    EmotionMetaphor(
      id: 'animal_basking_dog',
      text: '像在午後陽光裡伸懶腰的狗，暫時不需要趕往哪裡',
      emotionTags: ['放鬆', '安心', '滿足'],
      energyLevel: 2,
      valence: 5,
      intensity: 2,
      category: '休息',
    ),
    EmotionMetaphor(
      id: 'light_flickering_sign',
      text: '像接觸不良而忽明忽暗的燈，精神一下集中、一下又散開',
      emotionTags: ['疲憊', '不穩定', '分心'],
      energyLevel: 2,
      valence: 2,
      intensity: 3,
      category: '光線',
    ),
    EmotionMetaphor(
      id: 'light_sunrise',
      text: '像天色正一點點亮起來，事情還沒完全清楚，但已有新的可能',
      emotionTags: ['希望', '期待', '振作'],
      energyLevel: 3,
      valence: 4,
      intensity: 3,
      category: '晨光',
    ),
    EmotionMetaphor(
      id: 'sound_many_radios',
      text: '像好幾台收音機同時播放，腦中很難只聽清一個聲音',
      emotionTags: ['混亂', '焦慮', '分心'],
      energyLevel: 4,
      valence: 2,
      intensity: 4,
      category: '聲音',
    ),
    EmotionMetaphor(
      id: 'sound_soft_song',
      text: '像熟悉的旋律輕輕響著，不強烈，卻讓人感到被陪伴',
      emotionTags: ['安心', '溫暖', '感動'],
      energyLevel: 2,
      valence: 4,
      intensity: 3,
      category: '音樂',
    ),
    EmotionMetaphor(
      id: 'action_running_in_place',
      text: '像很努力地原地跑，耗了不少力氣卻還看不見距離',
      emotionTags: ['挫折', '疲憊', '焦急'],
      energyLevel: 4,
      valence: 1,
      intensity: 4,
      category: '行動',
    ),
    EmotionMetaphor(
      id: 'action_deep_breath',
      text: '像忙亂中終於停下來深呼吸，節奏正慢慢回到自己手上',
      emotionTags: ['釋然', '平靜', '找回自己'],
      energyLevel: 2,
      valence: 4,
      intensity: 3,
      category: '呼吸',
    ),
    EmotionMetaphor(
      id: 'texture_heavy_blanket',
      text: '像蓋著一條太厚的毯子，想動一動卻覺得全身沉重',
      emotionTags: ['低落', '疲憊', '無力'],
      energyLevel: 1,
      valence: 1,
      intensity: 4,
      category: '觸感',
    ),
    EmotionMetaphor(
      id: 'texture_warm_mug',
      text: '像雙手捧著溫熱的杯子，小小的暖意足以讓人安定一些',
      emotionTags: ['安心', '溫暖', '被支持'],
      energyLevel: 1,
      valence: 4,
      intensity: 2,
      category: '溫度',
    ),
  ];

  static List<DiaryDraftSuggestion> recommend(
    DiaryEmotionAnalysis profile, {
    int limit = 5,
    String variationSeed = '',
  }) {
    final tags = {
      profile.primaryEmotion,
      ...profile.secondaryEmotions,
    }.where((item) => item.isNotEmpty).toSet();
    final ranked = items.where((item) => item.isReviewed).map((item) {
      final matchedTags = item.emotionTags
          .where(
            (itemTag) => tags.any(
              (profileTag) => _tagAffinity(profileTag, itemTag) > 0,
            ),
          )
          .toList();
      final tagScore = item.emotionTags.fold<int>(
        0,
        (total, itemTag) =>
            total +
            tags.fold<int>(
              0,
              (best, profileTag) {
                final affinity = _tagAffinity(profileTag, itemTag);
                return affinity > best ? affinity : best;
              },
            ),
      );
      final distance = (item.energyLevel - profile.energy).abs() +
          (item.valence - profile.valence).abs() +
          (item.intensity - profile.intensity).abs();
      final tieBreaker = _stableHash('$variationSeed|${item.id}');
      return (
        item: item,
        matchedTags: matchedTags,
        // A small seed-based offset varies near-equal choices without letting
        // it outweigh a direct emotion-tag match.
        score: tagScore * 4 - distance + tieBreaker % 3,
        tieBreaker: tieBreaker,
      );
    }).toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.tieBreaker.compareTo(b.tieBreaker);
      });
    final selected = <({
      EmotionMetaphor item,
      List<String> matchedTags,
      int score,
      int tieBreaker
    })>[];
    final categories = <String>{};
    for (final entry in ranked) {
      if (selected.length >= limit) break;
      if (categories.add(entry.item.category)) selected.add(entry);
    }
    if (selected.length < limit) {
      for (final entry in ranked) {
        if (selected.length >= limit) break;
        if (!selected.contains(entry)) selected.add(entry);
      }
    }
    return selected
        .map((entry) => DiaryDraftSuggestion(
              value: entry.item.text,
              source: DiaryDraftSource.suggested,
              confidence: (0.92 - (entry.score < 0 ? 0.18 : 0)).clamp(0, 1),
              evidence: entry.matchedTags.isEmpty
                  ? '${entry.item.category}意象；依今天感受的活力、方向與強度配對'
                  : '貼近「${entry.matchedTags.join('、')}」；'
                      '${entry.item.category}意象，並參考活力與強度',
            ))
        .toList();
  }

  static int _tagAffinity(String left, String right) {
    final a = left.trim();
    final b = right.trim();
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 3;
    if (a.contains(b) || b.contains(a)) return 2;
    for (final group in _emotionGroups) {
      if (group.contains(a) && group.contains(b)) return 1;
    }
    return 0;
  }

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  static const _emotionGroups = <Set<String>>[
    {'低落', '難過', '悲傷', '沮喪', '失望', '失落', '孤單', '空虛', '無力'},
    {'焦慮', '擔心', '不安', '緊張', '害怕', '焦急', '警覺'},
    {'疲憊', '疲倦', '累', '無力', '撐著', '負擔'},
    {'生氣', '憤怒', '煩躁', '不耐煩', '委屈'},
    {'開心', '快樂', '喜悅', '興奮', '成就感', '滿足'},
    {'平靜', '放鬆', '安心', '釋然', '沉澱'},
    {'迷惘', '混亂', '糾結', '猶豫', '不確定', '分心'},
    {'壓力', '負擔', '挫折', '無奈', '焦急'},
    {'希望', '期待', '好奇', '振作', '堅持'},
    {'溫暖', '感動', '被支持', '被理解', '陪伴'},
  ];
}
