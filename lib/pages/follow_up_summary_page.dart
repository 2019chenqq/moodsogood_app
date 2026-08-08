import 'package:flutter/material.dart';
import '../constants/healing_design_system.dart';
import '../services/follow_up_service.dart';
import '../analytics_service.dart';

/// 可選的主題標籤
const List<String> kTopicOptions = [
  '情緒狀況',
  '睡眠品質',
  '藥物副作用',
  '身體不適',
  '食慾變化',
  '生活壓力',
  '人際關係',
  '工作/學業',
  '運動習慣',
  '其他',
];

class FollowUpSummaryPage extends StatefulWidget {
  const FollowUpSummaryPage({super.key});

  @override
  State<FollowUpSummaryPage> createState() => _FollowUpSummaryPageState();
}

class _FollowUpSummaryPageState extends State<FollowUpSummaryPage> {
  DateTime? _selectedDate;
  final Set<String> _selectedTopics = {};
  final _noteCtrl = TextEditingController();
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('follow_up_summary_page');
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: DateTime(now.year + 5),
      helpText: '選擇回診日期（可選）',
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _generateSummary() async {
    if (_selectedTopics.isEmpty && _noteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少選擇一個主題或輸入想討論的內容')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    // 如果有選日期，自動新增一筆回診
    if (_selectedDate != null) {
      final label = _selectedTopics.isNotEmpty
          ? _selectedTopics.first
          : '回診';
      await FollowUpService.addAppointment(
        FollowUpAppointment(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          date: _selectedDate!,
          label: label,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        ),
      );
    }

    // 模擬產生中（後續可接真實 AI）
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    setState(() => _isGenerating = false);

    // 顯示成功訊息
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: const Color(0xFF43A047)),
            const SizedBox(width: 8),
            const Text('摘要已產生'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('回診摘要已準備完成！'),
            const SizedBox(height: 8),
            if (_selectedDate != null)
              Text('回診日期：${_selectedDate!.year}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.day.toString().padLeft(2, '0')}'),
            if (_selectedTopics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('討論主題：${_selectedTopics.join('、')}'),
              ),
            if (_noteCtrl.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('備註：${_noteCtrl.text.trim()}'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.primaryBlue,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(
            color: HealingDesignSystem.adaptivePrimaryText(context)),
        title: Text(
          '準備回診摘要',
          style: TextStyle(
            color: HealingDesignSystem.adaptivePrimaryText(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // 說明卡片
          Container(
            padding: const EdgeInsets.all(18),
            decoration: HealingDesignSystem.adaptiveCardDecoration(
              context,
              radius: HealingDesignSystem.radiusL,
              shadows: [
                HealingDesignSystem.shadowMedium(
                    color: HealingDesignSystem.primaryBlue)
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: HealingDesignSystem.primaryGradient(),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.summarize_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '讓 AI 幫你整理',
                        style: HealingDesignSystem.titleMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '選取你想跟醫師討論的主題，AI 會根據你的近期紀錄產生回診摘要。',
                        style: TextStyle(
                          color: HealingDesignSystem.adaptiveSecondaryText(context),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 回診日期（可選）
          _SectionCard(
            title: '回診日期（可選）',
            icon: Icons.calendar_today_outlined,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: HealingDesignSystem.adaptiveFill(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: HealingDesignSystem.adaptiveCardBorder(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedDate == null
                            ? '點擊選擇日期（不填也沒關係）'
                            : '${_selectedDate!.year}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: _selectedDate == null
                              ? HealingDesignSystem.adaptiveSecondaryText(context)
                              : HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                    ),
                    if (_selectedDate != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _selectedDate = null),
                      ),
                    Icon(Icons.chevron_right,
                        color: HealingDesignSystem.adaptiveSecondaryText(context)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 想討論的主題
          _SectionCard(
            title: '想跟醫師討論的主題',
            icon: Icons.topic_outlined,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kTopicOptions.map((topic) {
                final selected = _selectedTopics.contains(topic);
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedTopics.remove(topic);
                      } else {
                        _selectedTopics.add(topic);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? HealingDesignSystem.primaryBlue
                              .withValues(alpha: 0.16)
                          : HealingDesignSystem.adaptiveFill(context),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? HealingDesignSystem.primaryBlue
                                .withValues(alpha: 0.35)
                            : HealingDesignSystem.adaptiveCardBorder(context),
                      ),
                    ),
                    child: Text(
                      topic,
                      style: TextStyle(
                        color: selected
                            ? HealingDesignSystem.primaryBlue
                            : HealingDesignSystem.adaptivePrimaryText(context),
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // 自由填寫
          _SectionCard(
            title: '其他想說的話（可選）',
            icon: Icons.notes_outlined,
            child: TextField(
              controller: _noteCtrl,
              minLines: 3,
              maxLines: 6,
              style: TextStyle(
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
              decoration: InputDecoration(
                hintText: '例如：最近藥物的效果、睡眠變化的細節、想問醫師的問題⋯⋯',
                hintStyle: TextStyle(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: HealingDesignSystem.adaptiveFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: HealingDesignSystem.adaptiveCardBorder(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: HealingDesignSystem.adaptiveCardBorder(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: HealingDesignSystem.primaryBlue, width: 1.4),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 產生按鈕
          FilledButton.icon(
            onPressed: _isGenerating ? null : _generateSummary,
            style: FilledButton.styleFrom(
              backgroundColor: HealingDesignSystem.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: _isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _isGenerating ? '正在產生摘要⋯' : '產生回診摘要',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: HealingDesignSystem.adaptiveSurface(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
        side: BorderSide(
            color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: HealingDesignSystem.adaptiveFill(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      size: 16, color: HealingDesignSystem.primaryBlue),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// 標示「AI 回診重點」的提示卡片；目前為準備中狀態。
class FollowUpAiHighlightsCard extends StatelessWidget {
  const FollowUpAiHighlightsCard({super.key, this.onTap});

  /// 準備中狀態的說明文字。
  static const String unavailableMessage = 'AI 回診摘要準備中，將在近期提供';

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: HealingDesignSystem.adaptiveSurface(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
        side: BorderSide(
            color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: HealingDesignSystem.adaptiveFill(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 16, color: HealingDesignSystem.primaryBlue),
                ),
                const SizedBox(width: 8),
                Text('AI 回診重點', style: HealingDesignSystem.titleSmall),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: HealingDesignSystem.adaptiveFill(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('準備中',
                      style: HealingDesignSystem.bodySmall),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              unavailableMessage,
              style: HealingDesignSystem.bodyMedium.copyWith(
                color: HealingDesignSystem.adaptiveSecondaryText(context),
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: const [
                    Expanded(child: Text('開始準備 AI 回診摘要')),
                    Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
