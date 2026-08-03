import 'package:flutter/material.dart';
import '../daily_record_helpers.dart';
import '../../constants/healing_design_system.dart';
import '../../widgets/emotion_slider.dart';
import '../../analytics_service.dart';
import '../emotion_dimensions.dart';
import '../daily_state_dimensions.dart';

export '../emotion_dimensions.dart';

/// 每日情緒與狀態：正式情緒採 1～5 分強度；每日狀態則獨立記錄
/// 與平常相比的 1～5 分變化，兩者不共用資料或提示邏輯。
class EmotionPageCheckbox extends StatefulWidget {
  const EmotionPageCheckbox({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onToggleChecked,
    required this.onChangeValue,
    required this.stateChanges,
    required this.onChangeState,
    this.firstEmotionItemKey,
    this.emotionScoreKey,
    this.tutorialSliderKey,
    this.scrollController,
    this.showTutorialScorePreview = false,
  });

  final List<EmotionItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  final void Function(int index, bool checked) onToggleChecked;
  final void Function(int index, int value) onChangeValue;
  final Map<String, int> stateChanges;
  final void Function(String id, int? value) onChangeState;
  final GlobalKey? firstEmotionItemKey;
  final GlobalKey? emotionScoreKey;
  final GlobalKey? tutorialSliderKey;
  final ScrollController? scrollController;
  final bool showTutorialScorePreview;

  @override
  State<EmotionPageCheckbox> createState() => _EmotionPageCheckboxState();
}

class _EmotionPageCheckboxState extends State<EmotionPageCheckbox> {
  bool _isSliderExpanded = true; // 控制 slider 區域的展開/收合
  bool _isStateExpanded = false;

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
      controller: widget.scrollController,
      child: Column(
        children: [
          // ========================================
          // TOP SECTION: 情緒分類選擇區
          // ========================================
          Container(
            padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
            color: HealingDesignSystem.adaptiveFill(context).withOpacity(0.45),
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

          const Divider(height: 1, thickness: 2),
          _buildDailyStateSection(context),

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

  Widget _buildDailyStateSection(BuildContext context) {
    return Container(
      color: HealingDesignSystem.adaptiveFill(context),
      child: ExpansionTile(
        initiallyExpanded: _isStateExpanded,
        onExpansionChanged: (value) => setState(() => _isStateExpanded = value),
        title: Text(
          '今天的狀態變化',
          style: HealingDesignSystem.titleMedium.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        subtitle: const Text('選填・請和平常的自己相比'),
        childrenPadding: const EdgeInsets.fromLTRB(
          HealingDesignSystem.paddingL,
          0,
          HealingDesignSystem.paddingL,
          HealingDesignSystem.paddingL,
        ),
        children: [
          Text(
            '請和平常的自己相比。3 分代表和平常差不多，越靠左代表降低，越靠右代表增加。',
            style: HealingDesignSystem.bodySmall.copyWith(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
            ),
          ),
          const SizedBox(height: HealingDesignSystem.paddingM),
          ...kDailyStateDimensions
              .map((dimension) => _buildDailyStateCard(context, dimension)),
        ],
      ),
    );
  }

  Widget _buildDailyStateCard(
    BuildContext context,
    DailyStateDimensionDefinition dimension,
  ) {
    final value = widget.stateChanges[dimension.id];
    return Container(
      margin: const EdgeInsets.only(bottom: HealingDesignSystem.paddingL),
      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(dimension.displayName,
                    style: HealingDesignSystem.titleSmall.copyWith(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    )),
              ),
              if (value != null)
                TextButton(
                  onPressed: () => widget.onChangeState(dimension.id, null),
                  child: const Text('清除'),
                )
              else
                const Text('尚未填寫',
                    style: TextStyle(color: HealingDesignSystem.mutedText)),
            ],
          ),
          Text(dimension.question,
              style: HealingDesignSystem.bodyMedium.copyWith(
                color: HealingDesignSystem.adaptiveSecondaryText(context),
              )),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: Text(dimension.lowLabel, textAlign: TextAlign.left)),
              Expanded(
                  child:
                      Text(dimension.middleLabel, textAlign: TextAlign.center)),
              Expanded(
                  child: Text(dimension.highLabel, textAlign: TextAlign.right)),
            ],
          ),
          Slider(
            value: (value ?? 3).toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: value?.toString() ?? '尚未填寫',
            onChanged: (next) =>
                widget.onChangeState(dimension.id, next.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) => Text('${index + 1}')),
          ),
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
          color: HealingDesignSystem.adaptiveFill(context),
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
                    style: HealingDesignSystem.titleMedium.copyWith(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
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
                          content: const Text('1分為程度最低，5分為程度最高，請依自身狀況評分'),
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
            key: selectedEmotions.isNotEmpty || widget.showTutorialScorePreview
                ? widget.emotionScoreKey
                : null,
            color: HealingDesignSystem.adaptiveFill(context).withOpacity(0.3),
            constraints: selectedEmotions.isEmpty
                ? const BoxConstraints()
                : const BoxConstraints(maxHeight: 400),
            child: selectedEmotions.isEmpty
                ? widget.showTutorialScorePreview
                    ? _buildTutorialScorePreview(context)
                    : Center(
                        child: Text(
                          '請從上方選擇情緒',
                          style: HealingDesignSystem.bodyMedium.copyWith(
                            color: HealingDesignSystem.mutedText,
                          ),
                        ),
                      )
                : SingleChildScrollView(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(HealingDesignSystem.paddingL),
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
  Widget _buildTutorialScorePreview(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
      child: Container(
        padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
        decoration: HealingDesignSystem.adaptiveCardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '情緒強度示範',
              style: HealingDesignSystem.titleSmall.copyWith(
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
            ),
            const SizedBox(height: HealingDesignSystem.paddingM),
            EmotionSlider(
              sliderKey: widget.tutorialSliderKey,
              label: '平靜',
              value: 3,
              maxScore: 5,
              onChanged: (_) {},
              leftIcon: 'assets/emotion/default.png',
              rightIcon: 'assets/emotion/default.png',
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
            style: HealingDesignSystem.titleMedium.copyWith(
              color: HealingDesignSystem.adaptivePrimaryText(context),
            ),
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

            final isFirstEmotion = kEmotionCheckboxNames.isNotEmpty &&
                emotionName == kEmotionCheckboxNames.first;

            return KeyedSubtree(
              key: isFirstEmotion ? widget.firstEmotionItemKey : null,
              child: _buildEmotionCard(
                emotionName: emotionName,
                isSelected: isSelected,
                onTap: () {
                  if (index == null) {
                    return;
                  }
                  widget.onToggleChecked(index, !isSelected);
                },
              ),
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
                : HealingDesignSystem.adaptiveSurface(context),
            border: Border.all(
              color: isSelected
                  ? HealingDesignSystem.primaryBlue
                  : HealingDesignSystem.adaptiveCardBorder(context),
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
                      : HealingDesignSystem.adaptivePrimaryText(context),
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
    // 自殺意念：改為簡單的「有/無」切換，點選即跳出求救管道
    if (emotion.name == '自殺意念') {
      return Container(
        margin: const EdgeInsets.only(bottom: HealingDesignSystem.paddingL),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '自殺意念',
                      style: HealingDesignSystem.titleSmall.copyWith(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w700,
                      ),
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
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => widget.onToggleChecked(index, false),
                  ),
                ],
              ),
              const SizedBox(height: HealingDesignSystem.paddingM),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            emotion.value != null ? Colors.red : null,
                        backgroundColor: emotion.value != null
                            ? Colors.red.withOpacity(0.1)
                            : null,
                        side: BorderSide(
                          color: emotion.value != null
                              ? Colors.red
                              : Colors.grey.shade300,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        widget.onChangeValue(index, 1);
                      },
                      child: const Text('有',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            emotion.value == null ? Colors.green : null,
                        backgroundColor: emotion.value == null
                            ? Colors.green.withOpacity(0.1)
                            : null,
                        side: BorderSide(
                          color: emotion.value == null
                              ? Colors.green
                              : Colors.grey.shade300,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        widget.onToggleChecked(index, false);
                      },
                      child: const Text('無',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              if (emotion.value != null) ...[
                const SizedBox(height: 12),
                Text(
                  '如果你正在經歷強烈痛苦或有自傷/自殺念頭，請優先尋求即時協助。',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: HealingDesignSystem.paddingL),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
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
                    style: HealingDesignSystem.titleSmall.copyWith(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
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
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
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
              rightIcon: 'assets/emotion/default.png',
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
