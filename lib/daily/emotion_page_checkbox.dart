import 'package:flutter/material.dart';
import 'daily_record_helpers.dart';
import 'daily_record_pages.dart';
import '../constants/healing_design_system.dart';
import '../widgets/emotion_slider.dart';
import '../analytics_service.dart';

const Map<String, List<String>> kEmotionCheckboxCategories = {
  '喜悅': ['快樂', '興奮', '愉悅', '滿足', '自在'],
  '厭惡': ['厭倦', '無聊', '反感', '煩悶'],
  '悲傷': ['低落', '憂鬱', '孤單', '絕望', '沮喪'],
  '恐懼': ['緊張', '擔心', '惶恐', '焦慮', '忐忑不安'],
  '憤怒': ['生氣', '暴躁', '忌妒', '惱羞成怒'],
  '危險警訊': ['自殺意念'],
};

final List<String> kEmotionCheckboxNames = List.unmodifiable(
  kEmotionCheckboxCategories.values.expand((emotions) => emotions),
);

/// 新版：分類選擇 + 已選情緒評分
/// TOP: 三大類情緒（整體狀態、壓力情緒、低落警訊）以 Chip 方式選擇
/// MIDDLE: 已選情緒顯示 Slider (0~10)，可收合
/// BOTTOM: 日記頁面
class EmotionPageCheckbox extends StatefulWidget {
  const EmotionPageCheckbox({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onToggleChecked,
    required this.onChangeValue,
  });

  final List<EmotionItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  final void Function(int index, bool checked) onToggleChecked;
  final void Function(int index, int value) onChangeValue;

  @override
  State<EmotionPageCheckbox> createState() => _EmotionPageCheckboxState();
}

class _EmotionPageCheckboxState extends State<EmotionPageCheckbox> {
  bool _isSliderExpanded = true; // 控制 slider 區域的展開/收合

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('emotion_page_checkbox');
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 從 items 中找出已選擇的情緒（value != null）
    final selectedEmotions = <EmotionItem>[];
    final emotionIndices = <String, int>{}; // 情緒名稱 -> index 映射

    for (var i = 0; i < widget.items.length; i++) {
      emotionIndices[widget.items[i].name] = i;
      if (widget.items[i].value != null) {
        selectedEmotions.add(widget.items[i]);
      }
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // ========================================
          // TOP SECTION: 情緒分類選擇區
          // ========================================
          Container(
            padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
            color: HealingDesignSystem.softBlue.withOpacity(0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: kEmotionCheckboxCategories.entries.map((category) {
                return _buildCategorySection(
                  context,
                  categoryName: category.key,
                  emotions: category.value,
                  emotionIndices: emotionIndices,
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1, thickness: 2),

          // ========================================
          // MIDDLE SECTION: 已選情緒評分區（可收合）
          // ========================================
          _buildCollapsibleSliderSection(
              context, selectedEmotions, emotionIndices),

          // ========================================
          // BOTTOM SECTION: 日記連結
          // ========================================
          // Container(
          //   padding: const EdgeInsets.all(16),
          //   child: Center(
          //     child: Column(
          //       mainAxisAlignment: MainAxisAlignment.center,
          //       children: [
          //         Icon(
          //           Icons.notes_outlined,
          //           size: 56,
          //           color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
          //         ),
          //         const SizedBox(height: 16),
          //         Text(
          //           '今日日記',
          //           style: Theme.of(context).textTheme.titleLarge?.copyWith(
          //                 fontWeight: FontWeight.bold,
          //               ),
          //         ),
          //         const SizedBox(height: 8),
          //         Text(
          //           '記錄今天的感受和故事',
          //           style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          //                 color: Theme.of(context)
          //                     .colorScheme
          //                     .onSurface
          //                     .withOpacity(0.6),
          //               ),
          //         ),
          //         const SizedBox(height: 24),
          //         ElevatedButton.icon(
          //           onPressed: () {
          //             Navigator.of(context).push(
          //               MaterialPageRoute(
          //                 builder: (context) => DiaryPageDemo(date: DateTime.now()),
          //               ),
          //             );
          //           },
          //           icon: const Icon(Icons.open_in_new),
          //           label: const Text('打開日記'),
          //         ),
          //       ],
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }

  /// 構建可收合的 Slider 區域
  Widget _buildCollapsibleSliderSection(
    BuildContext context,
    List<EmotionItem> selectedEmotions,
    Map<String, int> emotionIndices,
  ) {
    return Column(
      children: [
        // 標題欄 + 收合按鈕
        Container(
          color: HealingDesignSystem.softBlue,
          padding: const EdgeInsets.symmetric(
            horizontal: HealingDesignSystem.paddingL,
            vertical: HealingDesignSystem.paddingM,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '情緒評分',
                    style: HealingDesignSystem.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.info_outline,
                        color: HealingDesignSystem.primaryBlue),
                    tooltip: '評分說明',
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('評分說明'),
                          content: const Text('1分為程度最低，10分為程度最高，請依自身狀況評分'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('關閉'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  _isSliderExpanded ? Icons.expand_less : Icons.expand_more,
                  color: HealingDesignSystem.primaryBlue,
                ),
                onPressed: () {
                  setState(() => _isSliderExpanded = !_isSliderExpanded);
                },
              ),
            ],
          ),
        ),

        // 內容區（展開時顯示）
        if (_isSliderExpanded)
          Container(
            color: HealingDesignSystem.softBlue.withOpacity(0.2),
            constraints: const BoxConstraints(maxHeight: 400),
            child: selectedEmotions.isEmpty
                ? Center(
                    child: Text(
                      '請從上方選擇情緒',
                      style: HealingDesignSystem.bodyMedium.copyWith(
                        color: HealingDesignSystem.mutedText,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
                      child: Column(
                        children: selectedEmotions.map((emotion) {
                          final index = emotionIndices[emotion.name]!;
                          return _buildSelectedEmotionCard(
                            context,
                            emotion: emotion,
                            index: index,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }

  /// 構建單個分類區塊 - 用療癒卡片替代 Chip
  Widget _buildCategorySection(
    BuildContext context, {
    required String categoryName,
    required List<String> emotions,
    required Map<String, int> emotionIndices,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            bottom: HealingDesignSystem.paddingM,
            top: HealingDesignSystem.paddingM,
          ),
          child: Text(
            categoryName,
            style: HealingDesignSystem.titleMedium,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.start,
          spacing: HealingDesignSystem.paddingL,
          runSpacing: HealingDesignSystem.paddingL,
          children: emotions.map((emotionName) {
            // 檢查這個情緒是否已存在於 items 中
            final index = emotionIndices[emotionName];
            final isSelected =
                index != null && widget.items[index].value != null;

            return _buildEmotionCard(
              emotionName: emotionName,
              isSelected: isSelected,
              onTap: () {
                if (index == null) {
                  return;
                }
                widget.onToggleChecked(index, !isSelected);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: HealingDesignSystem.paddingL),
      ],
    );
  }

  /// 療癒風格情緒卡片 - 替代 FilterChip
  Widget _buildEmotionCard({
    required String emotionName,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: HealingDesignSystem.paddingM,
            vertical: HealingDesignSystem.paddingS,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? HealingDesignSystem.primaryBlue.withOpacity(0.15)
                : HealingDesignSystem.cardBg,
            border: Border.all(
              color: isSelected
                  ? HealingDesignSystem.primaryBlue
                  : HealingDesignSystem.lineColor,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
            boxShadow: isSelected
                ? [HealingDesignSystem.shadowLight()]
                : [
                    BoxShadow(
                      color: HealingDesignSystem.primaryBlue.withOpacity(0.05),
                      blurRadius: 6,
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                const Icon(
                  Icons.check_circle,
                  size: 18,
                  color: HealingDesignSystem.primaryBlue,
                ),
                const SizedBox(width: HealingDesignSystem.paddingS),
              ],
              Text(
                emotionName,
                style: TextStyle(
                  color: isSelected
                      ? HealingDesignSystem.primaryBlue
                      : HealingDesignSystem.deepText,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 構建已選情緒卡片（帶 Slider）- 療癒設計
  Widget _buildSelectedEmotionCard(
    BuildContext context, {
    required EmotionItem emotion,
    required int index,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: HealingDesignSystem.paddingL),
      decoration: HealingDesignSystem.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    emotion.name,
                    style: HealingDesignSystem.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: HealingDesignSystem.mutedText,
                  ),
                  tooltip: '移除',
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => widget.onToggleChecked(index, false),
                ),
              ],
            ),
            const SizedBox(height: HealingDesignSystem.paddingM),
            EmotionSlider(
              label: emotion.name,
              value: emotion.value ?? 1,
              onChanged: (v) => widget.onChangeValue(index, v),
              leftIcon: 'assets/emotion/default.png',
              rightIcon: emotionRightIconMap[emotion.name] ??
                  'assets/emotion/default.png',
              gradientColors: const [
                Color(0xFF9AD0EC),
                Color(0xFFFFE08A),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
