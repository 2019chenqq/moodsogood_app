import 'package:flutter/material.dart';
import '../widgets/interactive_tutorial.dart';

/// 每日紀錄頁面導覽步驟生成器
class DailyRecordPageTutorial {
  /// 生成每日紀錄頁面的導覽步驟
  static List<TutorialStep> generateSteps() {
    return [
      TutorialStep(
        title: '📅 選擇紀錄日期',
        description: '使用日期選擇器選擇您要紀錄的日期。您可以記錄今天或過去的任何日期。',
        targetArea: const Offset(50, 100),
        targetSize: const Size(60, 60),
      ),
      TutorialStep(
        title: '😊 選擇您的心情',
        description: '從列表中選擇最能代表您當前心情的情緒。'
            '您可以多選，系統會記錄所有選擇。',
        targetArea: const Offset(20, 180),
        targetSize: const Size(300, 150),
      ),
      TutorialStep(
        title: '🏥 記錄症狀',
        description: '如果有任何身體症狀或不適，請記錄在這裡。'
            '您可以添加多個症狀。',
        targetArea: const Offset(20, 350),
        targetSize: const Size(300, 120),
      ),
      TutorialStep(
        title: '💊 記錄藥物',
        description: '如果服用了安眠藥或其他治療藥物，請在這裡記錄。'
            '包括藥物名稱和劑量。',
        targetArea: const Offset(20, 500),
        targetSize: const Size(300, 100),
      ),
      TutorialStep(
        title: '🛏️ 記錄睡眠',
        description: '記錄您的睡眠時間、醒來時間和睡眠品質。'
            '這些信息對追蹤心理健康非常重要。',
        targetArea: const Offset(20, 630),
        targetSize: const Size(300, 150),
      ),
      TutorialStep(
        title: '📝 添加備註',
        description: '在此添加任何其他備註或詳細信息。'
            '例如：發生了什麼、您的感受等。',
        targetArea: const Offset(20, 810),
        targetSize: const Size(300, 100),
      ),
      TutorialStep(
        title: '💾 保存紀錄',
        description: '完成所有填寫後，點擊「保存」按鈕保存您的每日紀錄。'
            '您的數據將被安全保存。',
        targetArea: const Offset(30, 920),
        targetSize: const Size(280, 50),
      ),
    ];
  }

  /// 生成簡略版導覽（只展示主要功能）
  static List<TutorialStep> generateSimpleSteps() {
    return [
      TutorialStep(
        title: '📅 每日紀錄頁面',
        description: '歡迎來到每日紀錄頁面。'
            '這是您追蹤心理和身體狀態的主要地方。'
            '讓我向您介紹各個部分。',
        targetArea: null,
        targetSize: null,
      ),
      TutorialStep(
        title: '😊 情緒選擇',
        description: '首先，選擇您現在的心情。'
            '您可以選擇多個情緒來更準確地反映您的感受。',
        targetArea: const Offset(20, 150),
        targetSize: const Size(300, 100),
      ),
      TutorialStep(
        title: '🛏️ 睡眠追蹤',
        description: '記錄您的睡眠信息。'
            '規律的睡眠對心理健康至關重要。',
        targetArea: const Offset(20, 500),
        targetSize: const Size(300, 100),
      ),
      TutorialStep(
        title: '💾 保存您的紀錄',
        description: '完成填寫後，點擊保存按鈕。'
            '您的數據將被安全地保存以供將來參考。',
        targetArea: const Offset(30, 920),
        targetSize: const Size(280, 50),
      ),
    ];
  }
}
