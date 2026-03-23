import 'package:intl/intl.dart';
import '../models/daily_record.dart';
import 'export_config.dart';
import 'export_metrics.dart';
import 'pdf_export_service.dart';

/// ============================================================
/// STEP 5: PDF 頁面構建器
/// 負責組裝各頁面的內容
/// ============================================================
class PDFPageBuilder {
  final ExportMetrics metrics;
  final ExportConfig config;
  final String aiSummary;
  final List<String> medications;
  final List<DailyRecord> records;

  PDFPageBuilder({
    required this.metrics,
    required this.config,
    required this.aiSummary,
    required this.medications,
    required this.records,
  });

  /// 第 1 頁：總覽摘要
  PDFPageContent buildOverviewPage() {
    final formatter = DateFormat('yyyy年MM月dd日', 'zh_TW');
    final startStr = formatter.format(config.startDate);
    final endStr = formatter.format(config.endDate);

    final contentParts = <String>[];

    // 匯出期間
    contentParts.add('📅 匯出期間');
    contentParts.add('$startStr 至 $endStr（共 ${config.durationDays} 天）');
    contentParts.add('');

    // 核心情緒 Top3
    if (metrics.topEmotions.isNotEmpty) {
      contentParts.add('💭 核心情緒（Top 3）');
      for (int i = 0; i < metrics.topEmotions.length; i++) {
        final emotion = metrics.topEmotions[i];
        contentParts.add(
          '${i + 1}. ${emotion.name}: '
          '平均 ${emotion.averageScore.toStringAsFixed(1)}/10 分, '
          '出現 ${emotion.appearanceDays} 天 (${emotion.trendDescription})',
        );
      }
      contentParts.add('');
    }

    // 睡眠摘要
    if (metrics.sleepMetrics != null) {
      final sleep = metrics.sleepMetrics!;
      contentParts.add('😴 睡眠摘要');
      contentParts.add(
        '平均睡眠時數: ${sleep.averageDuration.toStringAsFixed(1)} 小時 '
        '(${sleep.qualityDescription})',
      );
      contentParts.add(
        '睡眠波動: ${sleep.volatilityDescription}, '
        '短睡眠（<5小時）${sleep.shortSleepDays} 晚',
      );
      contentParts.add('');
    }

    // 用藥清單
    if (medications.isNotEmpty) {
      contentParts.add('💊 用藥紀錄');
      for (final med in medications) {
        contentParts.add('• $med');
      }
      contentParts.add('');
    }

    // AI 關鍵變化摘要
    if (aiSummary.isNotEmpty) {
      contentParts.add('🤖 AI 關鍵發現');
      contentParts.add(aiSummary);
    }

    return PDFPageContent(
      title: '總覽摘要',
      content: contentParts.join('\n'),
      orientation: 'portrait',
    );
  }

  /// 第 2 頁：情緒趨勢
  PDFPageContent buildEmotionTrendPage() {
    final contentParts = <String>[];

    // 核心情緒折線圖描述
    contentParts.add('📈 核心情緒趨勢');
    contentParts.add('');

    for (final emotion in metrics.topEmotions) {
      contentParts.add('【${emotion.name}】');
      contentParts.add(
        '平均分數: ${emotion.averageScore.toStringAsFixed(1)}/10 '
        '| 最高分: ${emotion.maxScore}/10',
      );
      contentParts.add(
        '前14天: ${emotion.firstHalfAverage.toStringAsFixed(1)} '
        '| 後14天: ${emotion.secondHalfAverage.toStringAsFixed(1)} '
        '| 變化: ${emotion.trend.toStringAsFixed(1)} (${emotion.trendDescription})',
      );
      contentParts.add(
        '高峰（≥8分）: ${emotion.veryHighScoreCount} 次 | '
        '較高（≥7分）: ${emotion.highScoreCount} 次',
      );
      contentParts.add('');
    }

    // 其他情緒排行榜
    if (metrics.emotions.length > metrics.topEmotions.length) {
      contentParts.add('其他情緒排行榜:');
      for (int i = metrics.topEmotions.length;
          i < metrics.emotions.length && i < metrics.topEmotions.length + 5;
          i++) {
        final emotion = metrics.emotions[i];
        contentParts.add(
          '${i + 1}. ${emotion.name}: ${emotion.averageScore.toStringAsFixed(1)}/10 (${emotion.appearanceDays}天)',
        );
      }
    }

    return PDFPageContent(
      title: '情緒趨勢分析',
      content: contentParts.join('\n'),
      orientation: 'portrait',
      isChart: true,
      chartType: 'line',
    );
  }

  /// 第 3 頁：睡眠紀錄（橫式）
  PDFPageContent buildSleepPage() {
    final contentParts = <String>[];

    if (metrics.sleepMetrics == null) {
      return PDFPageContent(
        title: '睡眠紀錄',
        content: '此期間無睡眠數據',
        orientation: 'landscape',
      );
    }

    final sleep = metrics.sleepMetrics!;

    contentParts.add('😴 睡眠統計');
    contentParts.add('');
    contentParts.add('平均睡眠時數: ${sleep.averageDuration.toStringAsFixed(1)} 小時');
    contentParts.add('最短: ${sleep.minDuration.toStringAsFixed(1)}h | 最長: ${sleep.maxDuration.toStringAsFixed(1)}h');
    contentParts.add('短睡眠天數 (<5h): ${sleep.shortSleepDays}');
    contentParts.add('睡眠波動 (標準差): ${sleep.standardDeviation.toStringAsFixed(2)}');
    contentParts.add('波動級別: ${sleep.volatilityDescription}');
    contentParts.add('');

    // 睡眠分布表格
    contentParts.add('每日睡眠時數:');
    for (int i = 0; i < sleep.allDurations.length && i < 28; i++) {
      final day = config.startDate.add(Duration(days: i));
      final dayStr = DateFormat('M/d', 'zh_TW').format(day);
      final duration = sleep.allDurations[i];
      final durationStr = duration.toStringAsFixed(1);
      contentParts.add('$dayStr: ${durationStr}h');
    }

    return PDFPageContent(
      title: '睡眠紀錄',
      content: contentParts.join('\n'),
      orientation: 'landscape',
      isTable: true,
    );
  }

  /// 第 4 頁：藥物 × 症狀 × 情緒
  PDFPageContent buildMedicationSymptomEmotionPage() {
    final contentParts = <String>[];

    contentParts.add('💊📊 用藥、症狀與情緒關聯');
    contentParts.add('');

    // 用藥變動時間軸
    if (medications.isNotEmpty) {
      contentParts.add('【用藥時間軸】');
      for (final med in medications) {
        contentParts.add('• $med');
      }
      contentParts.add('');
    }

    // 症狀趨勢
    if (metrics.symptoms.isNotEmpty) {
      contentParts.add('【症狀趨勢】');
      for (final symptom in metrics.symptoms) {
        contentParts.add('【${symptom.name}】');
        contentParts.add(
          '高分次數 (≥7): ${symptom.highScoreCount} | '
          '與情緒重疊: ${symptom.emotionOverlapCount} 次 '
          '(${symptom.overlapPercentage.toStringAsFixed(0)}%)',
        );
        if (symptom.hasSignificantOverlap) {
          contentParts.add('→ 常於相近日期與高峰情緒同時出現');
        } else {
          contentParts.add('→ 未見與情緒明顯同步');
        }
        contentParts.add('');
      }
    }

    // 情緒與症狀關聯摘要
    contentParts.add('【關聯性分析】');
    if (metrics.emotionSleepCorrelation != null &&
        metrics.emotionSleepCorrelation!.hasSignificantCorrelation) {
      contentParts.add(
        '• 短睡眠與隔日情緒呈現關聯 '
        '(短睡眠${metrics.emotionSleepCorrelation!.shortSleepDays}晚，'
        '隔日情緒變化${metrics.emotionSleepCorrelation!.emotionChangeAfterShortSleep.toStringAsFixed(1)})',
      );
    }

    return PDFPageContent(
      title: '用藥、症狀與情緒關聯',
      content: contentParts.join('\n'),
      orientation: 'landscape',
      isChart: true,
      chartType: 'bar',
    );
  }

  /// 第 5-6 頁：每日詳細摘要
  PDFPageContent buildDailyDetailPage() {
    final contentParts = <String>[];

    contentParts.add('📝 每日詳細摘要');
    contentParts.add('');

    for (final record in records) {
      if (record.date.isBefore(config.startDate) ||
          record.date.isAfter(config.endDate)) {
        continue;
      }

      final dateStr = DateFormat('MM月dd日 (E)', 'zh_TW').format(record.date);
      contentParts.add('【$dateStr】');

      // 情緒
      if (record.emotions.isNotEmpty) {
        final emotionStrs = record.emotions
            .where((e) => e.value != null && e.value! > 0)
            .map((e) => '${e.name} ${e.value}/10')
            .toList();
        if (emotionStrs.isNotEmpty) {
          contentParts.add('情緒: ${emotionStrs.join(', ')}');
        }
      }

      // 睡眠
      if (record.sleep.durationHours != null) {
        contentParts.add('睡眠: ${record.sleep.durationHours}h');
      }

      // 症狀
      if (record.symptoms.isNotEmpty) {
        contentParts.add('症狀: ${record.symptoms.join(', ')}');
      }

      // 筆記
      if (record.sleep.note != null && record.sleep.note!.isNotEmpty) {
        contentParts.add('備註: ${record.sleep.note}');
      }

      contentParts.add('');
    }

    // 文字分析摘要
    if (metrics.textMetrics != null) {
      contentParts.add('【文字分析】');
      contentParts.add('高頻關鍵詞: ${metrics.textMetrics!.topKeyword}');
      contentParts.add('出現次數: ${metrics.textMetrics!.topKeywordCount}');
      if (metrics.textMetrics!.primaryTheme != null) {
        contentParts.add('主要主題: ${_getThemeLabel(metrics.textMetrics!.primaryTheme!)}');
      }
    }

    return PDFPageContent(
      title: '每日詳細摘要',
      content: contentParts.join('\n'),
      orientation: 'portrait',
    );
  }

  String _getThemeLabel(String theme) {
    switch (theme) {
      case 'sleep':
        return '睡眠相關';
      case 'physical':
        return '身體不適';
      case 'rumination':
        return '反覆思考';
      case 'emotion':
        return '情緒描述';
      default:
        return '其他';
    }
  }
}
