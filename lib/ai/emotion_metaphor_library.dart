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

class EmotionMetaphorPreference {
  const EmotionMetaphorPreference({
    this.categoryCounts = const {},
    this.recentSelectedIds = const [],
  });

  final Map<String, int> categoryCounts;
  final List<String> recentSelectedIds;
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
    EmotionMetaphor(
      id: 'object_phone_many_notifications',
      text: '像手機只剩一點電，通知卻還一直跳出來',
      emotionTags: ['焦慮', '疲憊', '壓力'],
      energyLevel: 2,
      valence: 1,
      intensity: 4,
      category: '日常物品',
    ),
    EmotionMetaphor(
      id: 'action_waiting_tired',
      text: '已經很累了，心裡卻還惦記著即將發生的事',
      emotionTags: ['焦慮', '疲憊', '期待'],
      energyLevel: 2,
      valence: 3,
      intensity: 3,
      category: '直接感受',
    ),
    EmotionMetaphor(
      id: 'transport_bus_arrival_board',
      text: '像盯著公車動態，期待它快來，又怕自己錯過',
      emotionTags: ['焦慮', '期待', '不安'],
      energyLevel: 4,
      valence: 3,
      intensity: 4,
      category: '交通',
    ),
    EmotionMetaphor(
      id: 'light_stage_before_show',
      text: '像上場前亮起的燈，緊張得心跳加快，也忍不住期待',
      emotionTags: ['焦慮', '期待', '興奮'],
      energyLevel: 5,
      valence: 4,
      intensity: 5,
      category: '光線',
    ),
    EmotionMetaphor(
      id: 'road_gps_recalculating',
      text: '像導航一直重新規劃路線，走著走著又不確定方向',
      emotionTags: ['焦慮', '迷惘', '不確定'],
      energyLevel: 3,
      valence: 2,
      intensity: 4,
      category: '道路',
    ),
    EmotionMetaphor(
      id: 'weather_fog_rushing',
      text: '像趕路時遇上濃霧，越想快點抵達，越看不清前面',
      emotionTags: ['焦慮', '迷惘', '焦急'],
      energyLevel: 4,
      valence: 1,
      intensity: 5,
      category: '天氣',
    ),
    EmotionMetaphor(
      id: 'object_remote_no_battery',
      text: '像按了很多次遙控器，畫面還是沒有反應',
      emotionTags: ['低落', '無力', '挫折'],
      energyLevel: 1,
      valence: 1,
      intensity: 3,
      category: '日常物品',
    ),
    EmotionMetaphor(
      id: 'action_sitting_after_tasks',
      text: '事情堆在眼前，自己卻只想坐著，連開始都很費力',
      emotionTags: ['低落', '無力', '壓力'],
      energyLevel: 1,
      valence: 1,
      intensity: 5,
      category: '直接感受',
    ),
    EmotionMetaphor(
      id: 'space_lit_empty_room',
      text: '像房間的燈都開著，卻沒有一個可以說話的人',
      emotionTags: ['低落', '孤單', '空虛'],
      energyLevel: 1,
      valence: 1,
      intensity: 4,
      category: '空間',
    ),
    EmotionMetaphor(
      id: 'sound_message_no_reply',
      text: '像訊息送出去很久，四周只剩安靜',
      emotionTags: ['孤單', '失落', '低落'],
      energyLevel: 2,
      valence: 1,
      intensity: 3,
      category: '聲音',
    ),
    EmotionMetaphor(
      id: 'temperature_hot_cold_words',
      text: '像一股熱氣堵在胸口，說出口的話卻冷冷的',
      emotionTags: ['生氣', '委屈', '難過'],
      energyLevel: 4,
      valence: 1,
      intensity: 5,
      category: '溫度',
    ),
    EmotionMetaphor(
      id: 'animal_cat_tail_stepped',
      text: '像被踩到尾巴的貓，又痛又氣，還不知道怎麼說',
      emotionTags: ['生氣', '委屈', '無奈'],
      energyLevel: 4,
      valence: 1,
      intensity: 4,
      category: '動物',
    ),
    EmotionMetaphor(
      id: 'object_engine_no_stop',
      text: '像引擎一直轉著，卻找不到可以停下來的地方',
      emotionTags: ['生氣', '壓力', '煩躁'],
      energyLevel: 5,
      valence: 1,
      intensity: 5,
      category: '機械',
    ),
    EmotionMetaphor(
      id: 'sound_alarm_wont_stop',
      text: '像鬧鐘一直響，耐心被一聲一聲磨掉',
      emotionTags: ['生氣', '壓力', '不耐煩'],
      energyLevel: 5,
      valence: 1,
      intensity: 4,
      category: '聲音',
    ),
    EmotionMetaphor(
      id: 'object_backpack_keep_walking',
      text: '像背著很重的包，還得繼續往前走',
      emotionTags: ['疲憊', '撐著', '壓力'],
      energyLevel: 2,
      valence: 2,
      intensity: 5,
      category: '重量',
    ),
    EmotionMetaphor(
      id: 'action_last_stair',
      text: '像爬到最後幾階樓梯，腿很痠，還是不想停在這裡',
      emotionTags: ['疲憊', '撐著', '堅持'],
      energyLevel: 3,
      valence: 3,
      intensity: 4,
      category: '行動',
    ),
    EmotionMetaphor(
      id: 'weather_cool_evening_rest',
      text: '像忙了一天後吹到晚風，累，但終於可以慢下來',
      emotionTags: ['疲憊', '平靜', '放鬆'],
      energyLevel: 1,
      valence: 4,
      intensity: 2,
      category: '天氣',
    ),
    EmotionMetaphor(
      id: 'texture_clean_sheets',
      text: '像洗完澡躺進乾淨被窩，身體沉沉的，心安靜了',
      emotionTags: ['疲憊', '平靜', '安心'],
      energyLevel: 1,
      valence: 5,
      intensity: 2,
      category: '觸感',
    ),
    EmotionMetaphor(
      id: 'sound_favorite_song_loud',
      text: '像最喜歡的歌一響，就忍不住跟著節拍動起來',
      emotionTags: ['開心', '興奮', '活力'],
      energyLevel: 5,
      valence: 5,
      intensity: 5,
      category: '音樂',
    ),
    EmotionMetaphor(
      id: 'animal_dog_door_greeting',
      text: '像狗狗聽見熟悉的人回來，開心得在門口轉圈',
      emotionTags: ['開心', '興奮', '期待'],
      energyLevel: 5,
      valence: 5,
      intensity: 4,
      category: '動物',
    ),
    EmotionMetaphor(
      id: 'object_checked_task_list',
      text: '像待辦清單終於一項一項打完勾，踏實又痛快',
      emotionTags: ['開心', '成就感', '滿足'],
      energyLevel: 4,
      valence: 5,
      intensity: 4,
      category: '日常物品',
    ),
    EmotionMetaphor(
      id: 'action_finish_line_smile',
      text: '像抵達自己設定的終點，喘著氣也還是很想笑',
      emotionTags: ['開心', '成就感', '疲憊'],
      energyLevel: 4,
      valence: 5,
      intensity: 5,
      category: '行動',
    ),
    EmotionMetaphor(
      id: 'light_night_home',
      text: '像晚歸時看見家裡留著的燈，知道有人在等',
      emotionTags: ['平靜', '安心', '被支持'],
      energyLevel: 1,
      valence: 5,
      intensity: 3,
      category: '光線',
    ),
    EmotionMetaphor(
      id: 'temperature_sun_warmed_wall',
      text: '像靠著曬過太陽的牆，溫度剛好，什麼都不用急',
      emotionTags: ['平靜', '安心', '溫暖'],
      energyLevel: 2,
      valence: 5,
      intensity: 2,
      category: '溫度',
    ),
    EmotionMetaphor(
      id: 'object_browser_many_tabs',
      text: '像腦袋開了太多分頁，一直關不完',
      emotionTags: ['混亂', '分心', '壓力'],
      energyLevel: 4,
      valence: 2,
      intensity: 4,
      category: '數位生活',
    ),
    EmotionMetaphor(
      id: 'space_room_many_conversations',
      text: '像同一個房間裡有好幾段對話，想專心卻一直被拉走',
      emotionTags: ['混亂', '分心', '煩躁'],
      energyLevel: 4,
      valence: 2,
      intensity: 3,
      category: '空間',
    ),
    EmotionMetaphor(
      id: 'object_blocked_printer',
      text: '像趕時間時印表機偏偏卡紙，越急越做不下去',
      emotionTags: ['壓力', '挫折', '焦急'],
      energyLevel: 5,
      valence: 1,
      intensity: 5,
      category: '日常物品',
    ),
    EmotionMetaphor(
      id: 'action_pushing_stuck_door',
      text: '像用力推一扇卡住的門，花了力氣卻只動了一點點',
      emotionTags: ['壓力', '挫折', '無力'],
      energyLevel: 3,
      valence: 1,
      intensity: 4,
      category: '行動',
    ),
    EmotionMetaphor(
      id: 'light_dawn_after_shift',
      text: '像熬過漫長一夜後看見天亮，累得睜不開眼，還是有點期待',
      emotionTags: ['希望', '疲憊', '期待'],
      energyLevel: 2,
      valence: 4,
      intensity: 4,
      category: '晨光',
    ),
    EmotionMetaphor(
      id: 'plant_dry_soil_sprout',
      text: '像乾土裡冒出一點嫩芽，力氣不多，仍想試著長大',
      emotionTags: ['希望', '疲憊', '堅持'],
      energyLevel: 2,
      valence: 4,
      intensity: 3,
      category: '植物',
    ),
    EmotionMetaphor(
      id: 'weather_sun_with_dark_cloud',
      text: '像一邊出太陽、一邊飄著烏雲，心情很難只用一個詞說完',
      emotionTags: ['開心', '低落', '複雜', '矛盾'],
      energyLevel: 3,
      valence: 3,
      intensity: 3,
      category: '天氣',
    ),
    EmotionMetaphor(
      id: 'transport_departure_platform',
      text: '像車要進站了，既想趕快出發，又捨不得離開',
      emotionTags: ['期待', '不捨', '焦慮', '複雜'],
      energyLevel: 4,
      valence: 3,
      intensity: 4,
      category: '交通',
    ),
    EmotionMetaphor(
      id: 'texture_warm_coat_tight',
      text: '像一件很暖卻有點緊的外套，被照顧著，也有些不自在',
      emotionTags: ['溫暖', '壓力', '矛盾'],
      energyLevel: 2,
      valence: 3,
      intensity: 3,
      category: '觸感',
    ),
    EmotionMetaphor(
      id: 'sound_laugh_with_sigh',
      text: '像笑聲後面跟著一口嘆氣，開心是真的，累也是真的',
      emotionTags: ['開心', '疲憊', '複雜'],
      energyLevel: 3,
      valence: 3,
      intensity: 3,
      category: '聲音',
    ),
    EmotionMetaphor(
      id: 'animal_bird_open_cage',
      text: '像籠門打開後還停在原地的鳥，想飛，也有點怕',
      emotionTags: ['希望', '害怕', '猶豫', '期待'],
      energyLevel: 3,
      valence: 3,
      intensity: 4,
      category: '動物',
    ),
    EmotionMetaphor(
      id: 'temperature_cold_hands_warm_drink',
      text: '像冷著手接過一杯熱飲，難受還在，但有一點被接住了',
      emotionTags: ['低落', '溫暖', '被支持', '希望'],
      energyLevel: 1,
      valence: 3,
      intensity: 3,
      category: '溫度',
    ),
  ];

  static List<DiaryDraftSuggestion> recommend(
    DiaryEmotionAnalysis profile, {
    int limit = 5,
    String variationSeed = '',
    EmotionMetaphorPreference preference = const EmotionMetaphorPreference(),
  }) {
    final primaryEmotion = profile.primaryEmotion.trim();
    final secondaryEmotions = profile.secondaryEmotions
        .map((emotion) => emotion.trim())
        .where((emotion) => emotion.isNotEmpty && emotion != primaryEmotion)
        .toSet();
    final tags = {
      if (primaryEmotion.isNotEmpty) primaryEmotion,
      ...secondaryEmotions,
    };
    final ranked = items.where((item) => item.isReviewed).map((item) {
      final matchedTags = item.emotionTags
          .where(
            (itemTag) => tags.any(
              (profileTag) => _tagAffinity(profileTag, itemTag) > 0,
            ),
          )
          .toList();
      final primaryAffinity = primaryEmotion.isEmpty
          ? 0
          : item.emotionTags.fold<int>(
              0,
              (best, itemTag) {
                final affinity = _tagAffinity(primaryEmotion, itemTag);
                return affinity > best ? affinity : best;
              },
            );
      final primaryScore = switch (primaryAffinity) {
        3 => 24,
        2 => 16,
        1 => 10,
        _ => 0,
      };
      final secondaryScore = secondaryEmotions.fold<int>(0, (total, emotion) {
        final affinity = item.emotionTags.fold<int>(
          0,
          (best, itemTag) {
            final candidate = _tagAffinity(emotion, itemTag);
            return candidate > best ? candidate : best;
          },
        );
        return total +
            switch (affinity) {
              3 => 12,
              2 => 8,
              1 => 4,
              _ => 0,
            };
      });
      final distancePenalty = (item.energyLevel - profile.energy).abs() * 2 +
          (item.valence - profile.valence).abs() * 2 +
          (item.intensity - profile.intensity).abs() * 3;
      final categoryCount = preference.categoryCounts[item.category] ?? 0;
      final preferenceScore = categoryCount >= 3
          ? 2
          : categoryCount > 0
              ? 1
              : 0;
      final repetitionPenalty =
          preference.recentSelectedIds.contains(item.id) ? 1 : 0;
      final tieBreaker = _stableHash('$variationSeed|${item.id}');
      return (
        item: item,
        matchedTags: matchedTags,
        score: primaryScore +
            secondaryScore -
            distancePenalty +
            preferenceScore -
            repetitionPenalty,
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
    if (limit <= 0 || ranked.isEmpty) return const [];

    // Category diversity may reorder only candidates that are already very
    // close to the best match. It never pulls a clearly lower-scoring item
    // ahead of the ranked remainder.
    final highScoreFloor = ranked.first.score - 4;
    final highScorePool = ranked
        .where((entry) => entry.score >= highScoreFloor)
        .toList(growable: false);
    final categories = <String>{};
    for (final entry in highScorePool) {
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

  static EmotionMetaphor? findByText(String text) {
    final normalized = text.trim();
    for (final item in items) {
      if (item.text == normalized) return item;
    }
    return null;
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
