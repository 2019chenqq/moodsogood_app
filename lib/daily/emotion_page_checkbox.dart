import 'package:flutter/material.dart';
import 'daily_record_helpers.dart';
import 'daily_record_pages.dart';
import '../widgets/emotion_slider.dart';
import '../diary/diary_home_page.dart';

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
  }

  @override
  void dispose() {
    super.dispose();
  }

  // 定義三大類情緒
  static const Map<String, List<String>> _emotionCategories = {
    '整體狀態': ['平靜', '開心', '有力量', '疲憊', '沒動力'],
    '壓力情緒': ['焦慮', '緊張', '壓力大', '煩躁', '生氣'],
    '低落警訊': ['難過', '憂鬱', '無助', '崩潰感', '自殺意念'],
  };

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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _emotionCategories.entries.map((category) {
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
          _buildCollapsibleSliderSection(context, selectedEmotions, emotionIndices),

          // ========================================
          // BOTTOM SECTION: 日記連結
          // ========================================
          Container(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notes_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '今日日記',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '記錄今天的感受和故事',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => DiaryHomePage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('打開日記'),
                  ),
                ],
              ),
            ),
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
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '情緒評分',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              IconButton(
                icon: Icon(
                  _isSliderExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
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
            color: Theme.of(context).colorScheme.surface,
            constraints: const BoxConstraints(maxHeight: 400),
            child: selectedEmotions.isEmpty
                ? Center(
                    child: Text(
                      '請從上方選擇情緒',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
                          ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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

  /// 構建單個分類區塊
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
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Text(
            categoryName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: emotions.map((emotionName) {
            // 檢查這個情緒是否已存在於 items 中
            final index = emotionIndices[emotionName];
            final isSelected = index != null && widget.items[index].value != null;

            return FilterChip(
              label: Text(emotionName),
              selected: isSelected,
              onSelected: (selected) {
                if (index == null) {
                  // 如果該情緒不存在於 items，先添加
                  // 這裡需要通過 onAdd 來處理，但 onAdd 目前沒有參數
                  // 暫時跳過或者可以擴展 API
                  return;
                }
                widget.onToggleChecked(index, selected);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// 構建已選情緒卡片（帶 Slider）
  Widget _buildSelectedEmotionCard(
    BuildContext context, {
    required EmotionItem emotion,
    required int index,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    emotion.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '移除',
                  onPressed: () => widget.onToggleChecked(index, false),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
