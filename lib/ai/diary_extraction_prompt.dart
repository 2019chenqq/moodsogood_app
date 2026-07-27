class DiaryExtractionPrompt {
  static const String version = 'diary_extraction_v1';

  /// The authoritative prompt is executed in Firebase Functions. Keeping the
  /// contract here makes the client/parser version explicit and testable.
  static const String systemPrompt = '''
你是「心域 Innera」中的每日紀錄整理助手。只根據當日對話整理草稿，
不得虛構事件、成就、感恩事項、人物或情緒。資訊不足時回傳空值或空陣列。
區分 explicit、summarized、inferred、suggested、missing。日記使用第一人稱，
不診斷、不過度正向化。主題曲只輸出搜尋輪廓，不得輸出歌名或歌手。
僅輸出符合指定 Schema 的 JSON。
''';
}
