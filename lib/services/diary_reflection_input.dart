import '../models/daily_check_in.dart';

int? diaryReflectionMood(DailyCheckIn? checkIn, DateTime date) {
  if (checkIn == null ||
      checkIn.date.year != date.year ||
      checkIn.date.month != date.month ||
      checkIn.date.day != date.day ||
      checkIn.overallMood < 1 ||
      checkIn.overallMood > 5) {
    return null;
  }
  return checkIn.overallMood;
}

Map<String, dynamic> buildDiaryReflectionInput({
  required Map<String, dynamic> diary,
  required DailyCheckIn? checkIn,
  required DateTime date,
}) {
  const fields = {
    'title': '標題',
    'content': '內容',
    'themeSong': '今日主題曲',
    'highlight': '最想記錄的瞬間',
    'metaphor': '今天的感受意象',
    'conceited': '為自己感到驕傲',
    'proudOf': '做得不錯的地方',
    'selfCare': '可多照顧自己的地方',
  };
  final mood = diaryReflectionMood(checkIn, date);
  return {
    'date':
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'mode': 'basic',
    'moodScale': 5,
    'diaryText': fields.entries
        .where((entry) => (diary[entry.key] ?? '').toString().trim().isNotEmpty)
        .map((entry) => '${entry.value}: ${diary[entry.key].toString().trim()}')
        .join('\n'),
    'emotions': <Map<String, dynamic>>[
      if (mood != null) {'name': '整體情緒', 'score': mood},
    ],
    'allowedAnalysisScope': [
      '僅可根據今日日記文字與每日 check-in 整體情緒分數進行整理',
      '不可推論睡眠、症狀、藥物或長期趨勢',
      '不可做診斷、不可判斷病情嚴重度',
      '如果資料不足，請明確說明資料有限，不要自行補充內容',
    ],
  };
}
