// diary_ai_prompt_builder.dart

/// 建立日記 AI 回饋用的結構化輸入。
///
/// 重點：
/// 1. 不讓 AI 自由發揮。
/// 2. 明確禁止診斷、用藥建議、誇大判斷。
/// 3. 要求固定 JSON 格式。
/// 4. 先由 App 做初步風險標記，再交給 AI 溫和整理。

Map<String, dynamic> buildDiaryAiPrompt({
  required String date,
  required String diaryText,
  required List<Map<String, dynamic>> emotionScores,
  required Map<String, dynamic> sleep,
  required List<String> symptoms,
  required List<String> medications,
  bool? isPeriodDay,
  bool? isPredictedPeriodDay,
}) {
  final cleanDiaryText = diaryText.trim();

  final hasDiary = cleanDiaryText.isNotEmpty;
  final hasEmotions = emotionScores.isNotEmpty;
  final hasSleep = sleep.isNotEmpty;
  final hasSymptoms = symptoms.isNotEmpty;
  final hasMedications = medications.isNotEmpty;

  final localFlags = <String>[];

  final lowerDiary = cleanDiaryText.toLowerCase();

  final highRiskKeywords = [
    '想死',
    '自殺',
    '不想活',
    '活不下去',
    '消失',
    '傷害自己',
    '結束生命',
    '不想存在',
  ];

  final hasHighRiskText = highRiskKeywords.any(
    (keyword) => lowerDiary.contains(keyword.toLowerCase()),
  );

  if (hasHighRiskText) {
    localFlags.add('日記文字中出現可能與自傷或求助風險相關的語句');
  }

  final overallMood = _extractOverallMood(emotionScores);
  if (overallMood != null && overallMood <= 2) {
    localFlags.add('整體情緒分數偏低');
  }

  final sleepHours = _extractSleepHours(sleep);
  if (sleepHours != null && sleepHours < 5) {
    localFlags.add('睡眠時數偏短');
  }

  final sleepQuality = _extractSleepQuality(sleep);
  if (sleepQuality != null && sleepQuality <= 2) {
    localFlags.add('睡眠品質偏低');
  }

  if (symptoms.length >= 3) {
    localFlags.add('今日症狀項目較多');
  }

  if (!hasDiary && !hasEmotions && !hasSleep && !hasSymptoms && !hasMedications) {
    localFlags.add('今日資料不足，只能提供非常初步的觀察');
  }

  return {
    'systemInstruction': '''
你是「心域」App 的心理健康日記輔助回饋系統。

你的角色：
- 你不是醫師。
- 你不是心理師。
- 你不是診斷工具。
- 你只能根據使用者提供的日記、情緒分數、睡眠、症狀、生理期與藥物文字紀錄，進行溫和、保守、非診斷性的整理。

重要限制：
1. 不可以診斷疾病。
2. 不可以說使用者有憂鬱症、躁鬱症、焦慮症、創傷後壓力症候群或任何精神疾病。
3. 不可以建議停藥、加藥、減藥、換藥或自行調整用藥。
4. 不可以過度解讀。
5. 不可以把少量資料說成確定結論。
6. 不可以使用恐嚇式語氣。
7. 不可以說「你一定是」、「你就是」、「這代表你有」。
8. 如果資料不足，請明確說「今天資料較少，只能提供初步觀察」。
9. 請使用繁體中文。
10. 語氣要溫和、簡短、具陪伴感，但不要過度灌雞湯。
11. 只能根據使用者明確提供的內容回饋。
12. 不可以自行補充使用者沒有寫出的事件、感受、動機或成長意義。
13. 不可以把「日記有寫到」解讀成「使用者很會覺察」。
14. 如果日記內容很短，只能簡短整理，不可以延伸成深度心理分析。
15. 不可以使用「你願意面對自己」「你正在成長」「這顯示你有自我照顧」這類沒有資料支持的句子。
16. 若資料只有吃東西、日常事件、簡短抱怨，請回覆生活化觀察，不要心理化。

高風險處理：
- 如果 riskLevel 是 high，請不要做深入心理分析。
- 請溫和提醒使用者尋求可信任的人或專業協助。
- 若有立即危險，請提醒使用者聯絡當地緊急資源。
''',
    'userData': {
      'date': date,
      'diaryText': cleanDiaryText,
      'emotionScores': emotionScores,
      'sleep': sleep,
      'symptoms': symptoms,
      'medications': medications,
      'period': {
        'isPeriodDay': isPeriodDay,
        'isPredictedPeriodDay': isPredictedPeriodDay,
      },
      'localFlags': localFlags,
      'dataCompleteness': {
        'hasDiary': hasDiary,
        'hasEmotions': hasEmotions,
        'hasSleep': hasSleep,
        'hasSymptoms': hasSymptoms,
        'hasMedications': hasMedications,
      },
    },
    'outputRequirement': {
      'format': 'json_only',
      'language': 'zh-Hant',
      'schema': {
        'summary': 'string',
        'emotionObservation': 'string',
        'possibleFactors': 'array<string>',
        'gentleFeedback': 'string',
        'selfCareSuggestion': 'string',
        'riskLevel': 'low | medium | high',
        'disclaimer': 'string',
      },
      'riskLevelRules': {
        'low': '沒有明顯高風險文字，資料只顯示一般情緒起伏或輕度壓力。',
        'medium': '情緒分數偏低、睡眠差、症狀較多，或文字呈現明顯痛苦，但沒有直接自傷或自殺語句。',
        'high': '日記中出現自傷、自殺、不想活、想消失、傷害自己等高風險語句。',
      },
      'requiredDisclaimer': '此回饋僅根據今日紀錄整理，不能取代專業醫療、心理諮詢或危機處理。',
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