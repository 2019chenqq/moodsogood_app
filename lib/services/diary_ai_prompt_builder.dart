// diary_ai_prompt_builder.dart

/// 建立日記 AI 回饋用的結構化輸入。
///
/// 重點：
/// 1. 不讓 AI 自由發揮。
/// 2. 明確禁止診斷、用藥建議、誇大判斷。
/// 3. 要求固定 JSON 格式。
/// 4. 先由 App 做初步風險標記，再交給 AI 溫和整理。

Map<String, dynamic> buildDiaryAiPromptBasic({
  required String date,
  required String diaryText,
  required List<Map<String, dynamic>> emotions,
}) {
  return {
    'systemInstruction': '''
這是「基礎 AI 回饋」。
只能根據今日日記文字與整體情緒分數回應。
不可以提到睡眠、藥物、症狀，除非使用者在日記文字中明確寫到。
不可以說「你可能因為睡不好」「藥物影響」「症狀加重」這類沒有資料支撐的句子。
不可以診斷。
不可以判斷憂鬱、焦慮、躁鬱、病情嚴重程度。
主題（topics）只能從日記文字中明確出現的詞彙整理，不能推論、不能補出「工作成就」「身體健康」「自我照顧困難」這類推測性標籤。
主題數量最多 3 個。
如果資料不足，要說「目前資料有限，我只能根據你今天寫下的內容做簡短整理」。
請用繁體中文，語氣溫和、簡短、具陪伴感。
輸出格式固定為：
1. summary：今日簡短摘要
2. topics：明確出現在日記文字的主題（最多 3 個）
3. gentleFeedback：溫柔回饋
4. selfCareSuggestion：一個小小照顧自己的建議
''',
    'userData': {
      'date': date,
      'diaryText': diaryText,
      'emotions': emotions,
    },
    'outputRequirement': {
      'format': 'json_only',
      'language': 'zh-Hant',
      'schema': {
        'summary': 'string',
        'topics': 'List<string>',
        'gentleFeedback': 'string',
        'selfCareSuggestion': 'string',
      },
      'requiredDisclaimer': '此回饋僅根據今日記錄整理，不能取代專業醫療、心理諮詢或危機處理。',
    },
  };
}

double? _extractOverallMood(List<Map<String, dynamic>> emotionScores) {
  for (final item in emotionScores) {
    final name = item['name']?.toString() ?? '';
    if (name == '整體情緒') {
      final value = item['score'] ?? item['value'];
      if (value is num) return value.toDouble();
    }
  }
  return null;
}

double? _extractSleepHours(Map<String, dynamic> sleep) {
  final value = sleep['hours'] ?? sleep['durationHours'];
  if (value is num) return value.toDouble();
  return null;
}

int? _extractSleepQuality(Map<String, dynamic> sleep) {
  final value = sleep['quality'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}