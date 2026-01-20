import 'package:flutter/material.dart';
import '../widgets/interactive_tutorial.dart';

/// 日記頁面導覽步驟生成器
class DiaryPageTutorial {
  /// 生成日記頁面的完整導覽步驟
  static List<TutorialStep> generateSteps() {
    return [
      TutorialStep(
        title: '📖 日記首頁',
        description: '歡迎來到您的日記本。'
            '這是一個安全的地方，用來記錄您的想法、感受和經歷。',
        targetArea: null,
        targetSize: null,
      ),
      TutorialStep(
        title: '➕ 新增日記',
        description: '點擊這個按鈕開始撰寫新的日記。'
            '您可以為任何日期撰寫日記。',
        targetArea: const Offset(350, 700),
        targetSize: const Size(60, 60),
      ),
      TutorialStep(
        title: '📅 日記列表',
        description: '這裡顯示您所有的日記。'
            '點擊任何日記可以查看或編輯。'
            '向上滑動查看更多過去的日記。',
        targetArea: const Offset(20, 300),
        targetSize: const Size(340, 300),
      ),
      TutorialStep(
        title: '🔍 搜索功能',
        description: '使用搜索欄快速找到特定的日記。'
            '您可以按日期或關鍵詞搜索。',
        targetArea: const Offset(20, 60),
        targetSize: const Size(340, 50),
      ),
      TutorialStep(
        title: '✏️ 編輯日記',
        description: '點擊任何日記可以打開並編輯。'
            '您可以隨時修改或補充內容。',
        targetArea: const Offset(20, 200),
        targetSize: const Size(340, 80),
      ),
      TutorialStep(
        title: '💡 撰寫提示',
        description: '如果您不知道寫什麼，'
            '試著回答：今天發生了什麼？'
            '我的感受如何？什麼事情影響了我？',
        targetArea: null,
        targetSize: null,
      ),
    ];
  }

  /// 生成新日記撰寫頁面的導覽
  static List<TutorialStep> generateWritingSteps() {
    return [
      TutorialStep(
        title: '✍️ 開始撰寫日記',
        description: '您已進入日記撰寫頁面。'
            '這是您表達自己的地方，沒有限制或評判。',
        targetArea: null,
        targetSize: null,
      ),
      TutorialStep(
        title: '📅 選擇日期',
        description: '首先選擇日期。'
            '默認為今天，但您可以為任何過去的日期撰寫日記。',
        targetArea: const Offset(20, 80),
        targetSize: const Size(340, 50),
      ),
      TutorialStep(
        title: '📝 添加標題（可選）',
        description: '為您的日記添加一個簡短的標題。'
            '這可以幫助您以後快速識別日記的內容。',
        targetArea: const Offset(20, 150),
        targetSize: const Size(340, 50),
      ),
      TutorialStep(
        title: '✍️ 自由寫作區域',
        description: '在這個大文本框中自由寫作。'
            '沒有字數限制，不用擔心語法或拼寫。'
            '只需真誠地表達您的想法和感受。',
        targetArea: const Offset(20, 250),
        targetSize: const Size(340, 350),
      ),
      TutorialStep(
        title: '💾 保存日記',
        description: '完成寫作後，點擊「保存」按鈕保存您的日記。'
            '您的日記將被安全地加密保存。',
        targetArea: const Offset(100, 620),
        targetSize: const Size(200, 50),
      ),
      TutorialStep(
        title: '❌ 取消寫作',
        description: '如果您想放棄該日記並返回列表，'
            '點擊「取消」按鈕。'
            '已保存的內容不會丟失。',
        targetArea: const Offset(20, 620),
        targetSize: const Size(80, 50),
      ),
    ];
  }

  /// 生成簡略版導覽
  static List<TutorialStep> generateSimpleSteps() {
    return [
      TutorialStep(
        title: '📖 歡迎使用日記',
        description: '日記是您自由表達想法和感受的地方。'
            '所有內容都被安全加密，只有您可以看到。',
        targetArea: null,
        targetSize: null,
      ),
      TutorialStep(
        title: '➕ 開始新日記',
        description: '點擊浮動按鈕開始撰寫新日記。',
        targetArea: const Offset(350, 700),
        targetSize: const Size(60, 60),
      ),
      TutorialStep(
        title: '📚 查看您的日記',
        description: '所有日記都列在這裡。'
            '點擊打開、編輯或刪除。',
        targetArea: const Offset(20, 300),
        targetSize: const Size(340, 300),
      ),
      TutorialStep(
        title: '🚀 準備好開始了',
        description: '開始撰寫您的第一篇日記吧！'
            '記住，最好的日記就是真實的日記。',
        targetArea: null,
        targetSize: null,
      ),
    ];
  }
}
