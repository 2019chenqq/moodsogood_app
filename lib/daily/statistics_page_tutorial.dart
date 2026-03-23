import 'package:flutter/material.dart';
import '../widgets/interactive_tutorial.dart';

/// 統計分析頁面導覽步驟生成器
class StatisticsPageTutorial {
  /// 生成統計頁面的完整導覽步驟
  static List<TutorialStep> generateSteps() {
    return [
      TutorialStep(
        title: '📊 統計分析頁面',
        description: '歡迎來到統計分析頁面。'
            '這裡您可以看到所有的歷史記錄和數據分析。',
        targetArea: null,
        targetSize: null,
      ),
      TutorialStep(
        title: '📅 日期篩選',
        description: '使用日期選擇器選擇您想要查看的日期範圍。'
            '例如：查看過去一週或一個月的數據。',
        targetArea: const Offset(20, 80),
        targetSize: const Size(340, 60),
      ),
      TutorialStep(
        title: '📈 統計圖表',
        description: '這些圖表顯示您的情緒、睡眠和其他指標的趨勢。'
            '顏色和高度表示不同的值。',
        targetArea: const Offset(20, 180),
        targetSize: const Size(340, 200),
      ),
      TutorialStep(
        title: '💭 情緒分析',
        description: '查看您在選定期間內的情緒分布。'
            '這可以幫助您識別常見的心理狀態。',
        targetArea: const Offset(20, 420),
        targetSize: const Size(340, 100),
      ),
      TutorialStep(
        title: '🛏️ 睡眠統計',
        description: '查看您的平均睡眠時間和睡眠品質趨勢。'
            '良好的睡眠對心理健康非常重要。',
        targetArea: const Offset(20, 540),
        targetSize: const Size(340, 100),
      ),
      TutorialStep(
        title: '📋 詳細列表',
        description: '向下滑動查看所有每日紀錄的詳細列表。'
            '點擊任何紀錄可以查看完整詳情或編輯。',
        targetArea: const Offset(20, 680),
        targetSize: const Size(340, 100),
      ),
    ];
  }

  /// 生成簡略版導覽
  static List<TutorialStep> generateSimpleSteps() {
    return [
      TutorialStep(
        title: '📊 查看您的進度',
        description: '統計分析頁面顯示您的心理健康數據。'
            '使用它來追蹤進度和識別模式。',
        targetArea: null,
        targetSize: null,
      ),
      TutorialStep(
        title: '📅 選擇時間範圍',
        description: '選擇您想要分析的日期範圍。'
            '您可以查看一週、一個月或更長的時期。',
        targetArea: const Offset(20, 80),
        targetSize: const Size(340, 60),
      ),
      TutorialStep(
        title: '📊 查看圖表',
        description: '圖表顯示您的情緒和睡眠趨勢。'
            '向上移動表示更好的狀態。',
        targetArea: const Offset(20, 200),
        targetSize: const Size(340, 200),
      ),
      TutorialStep(
        title: '📝 查看詳細記錄',
        description: '向下滑動查看詳細的日常記錄。'
            '點擊任何記錄以查看完整信息。',
        targetArea: const Offset(20, 500),
        targetSize: const Size(340, 150),
      ),
      TutorialStep(
        title: '💡 提示：尋找模式',
        description: '定期查看您的數據以識別模式。'
            '例如：某些活動是否影響您的心情或睡眠？',
        targetArea: null,
        targetSize: null,
      ),
    ];
  }
}
