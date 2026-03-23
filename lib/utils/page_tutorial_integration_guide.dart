import 'package:flutter/material.dart';
import '../widgets/interactive_tutorial.dart';
import '../utils/page_tutorial_controller.dart';

/// 在頁面上集成導覽的示例和工具函數

/// 示例：在 FloatingActionButton 中添加導覽幫助按鈕
/// 將此添加到您的頁面的 floatingActionButton 或 bottomNavigationBar 中
Widget buildTutorialHelpButton({
  required BuildContext context,
  required List<TutorialStep> steps,
  required VoidCallback onTutorialComplete,
}) {
  return Tooltip(
    message: '開始導覽',
    child: FloatingActionButton.small(
      onPressed: () async {
        await PageTutorialController.showPageTutorial(context, steps);
        onTutorialComplete();
      },
      child: const Icon(Icons.help_outline),
    ),
  );
}

/// 示例：在 AppBar 中添加導覽幫助按鈕
Widget buildTutorialAppBarButton({
  required BuildContext context,
  required List<TutorialStep> steps,
  required VoidCallback onTutorialComplete,
}) {
  return IconButton(
    icon: const Icon(Icons.help_outline),
    tooltip: '開始導覽',
    onPressed: () async {
      await PageTutorialController.showPageTutorial(context, steps);
      onTutorialComplete();
    },
  );
}

/// 如何在頁面上集成
/// 
/// 1. 在您的頁面的 State 類中導入：
///    import '../daily/daily_record_page_tutorial.dart';
///    import '../utils/page_tutorial_controller.dart';
///
/// 2. 在 initState 中檢查是否需要顯示導覽：
///    @override
///    void initState() {
///      super.initState();
///      _checkAndShowTutorial();
///    }
///    
///    Future<void> _checkAndShowTutorial() async {
///      final shouldShow = await PageTutorialController.shouldShowDailyRecordPageTutorial();
///      if (shouldShow && mounted) {
///        WidgetsBinding.instance.addPostFrameCallback((_) {
///          _showTutorial();
///        });
///      }
///    }
///
/// 3. 創建顯示導覽的方法：
///    void _showTutorial() {
///      final steps = DailyRecordPageTutorial.generateSteps();
///      PageTutorialController.showPageTutorial(context, steps).then((_) {
///        PageTutorialController.markDailyRecordPageTutorialSeen();
///      });
///    }
///
/// 4. 在 AppBar 中添加幫助按鈕：
///    AppBar(
///      title: const Text('每日紀錄'),
///      actions: [
///        buildTutorialAppBarButton(
///          context: context,
///          steps: DailyRecordPageTutorial.generateSteps(),
///          onTutorialComplete: () {
///            // 完成後的處理
///          },
///        ),
///      ],
///    )
///
/// 5. 或在 floatingActionButton 中添加：
///    Row(
///      mainAxisAlignment: MainAxisAlignment.end,
///      children: [
///        buildTutorialHelpButton(
///          context: context,
///          steps: DailyRecordPageTutorial.generateSteps(),
///          onTutorialComplete: () {
///            // 完成後的處理
///          },
///        ),
///        const SizedBox(width: 16),
///        FloatingActionButton(
///          onPressed: _saveDailyRecord,
///          child: const Icon(Icons.save),
///        ),
///      ],
///    )
///
/// 重要提示：
/// - TutorialStep 中的 targetArea 應該是相對於屏幕的絕對位置
/// - 使用 GlobalKey 和 RenderBox 可以獲得準確的位置：
///   
///   GlobalKey _emotionKey = GlobalKey();
///   
///   // 獲取位置
///   RenderBox box = _emotionKey.currentContext!.findRenderObject() as RenderBox;
///   Offset position = box.localToGlobal(Offset.zero);
///   Size size = box.size;

class PageTutorialIntegrationGuide {
  /// 用於獲取 Widget 的屏幕位置和大小
  /// 使用方法：
  /// 1. 為要高亮的 Widget 添加 GlobalKey：
  ///    GlobalKey _emotionKey = GlobalKey();
  /// 2. 將 key 傳遞給 Widget
  /// 3. 在需要時調用此函數獲取位置
  static Offset? getWidgetPosition(GlobalKey key) {
    try {
      final renderBox =
          key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return null;
      return renderBox.localToGlobal(Offset.zero);
    } catch (e) {
      return null;
    }
  }

  /// 獲取 Widget 的大小
  static Size? getWidgetSize(GlobalKey key) {
    try {
      final renderBox =
          key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return null;
      return renderBox.size;
    } catch (e) {
      return null;
    }
  }

  /// 創建動態導覽步驟（基於實際 Widget 位置）
  static List<TutorialStep> createDynamicSteps({
    required Map<String, GlobalKey> keyMap,
  }) {
    return [
      TutorialStep(
        title: '每日紀錄頁面',
        description: '歡迎！讓我向您介紹如何使用此頁面。',
        targetArea: null,
        targetSize: null,
      ),
      if (keyMap.containsKey('emotion')) ...[
        TutorialStep(
          title: '😊 選擇您的心情',
          description: '從這裡開始選擇您當前的心情。',
          targetArea: getWidgetPosition(keyMap['emotion']!),
          targetSize: getWidgetSize(keyMap['emotion']!),
        ),
      ],
      if (keyMap.containsKey('sleep')) ...[
        TutorialStep(
          title: '🛏️ 記錄睡眠',
          description: '在這裡記錄您的睡眠信息。',
          targetArea: getWidgetPosition(keyMap['sleep']!),
          targetSize: getWidgetSize(keyMap['sleep']!),
        ),
      ],
      if (keyMap.containsKey('save')) ...[
        TutorialStep(
          title: '💾 保存',
          description: '完成後點擊此按鈕保存。',
          targetArea: getWidgetPosition(keyMap['save']!),
          targetSize: getWidgetSize(keyMap['save']!),
        ),
      ],
    ];
  }
}
