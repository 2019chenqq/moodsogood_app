import 'package:flutter/material.dart';
import '../constants/healing_design_system.dart';
import '../widgets/emotion_slider.dart';
import '../utils/date_helper.dart';
import '../models/daily_record.dart';
import 'daily_record_helpers.dart';
import 'daily_record_dialogs.dart';

// ============================================================
// Page Widgets
// ============================================================

const Map<String, String> emotionDisplayTextMap = {
  '整體情緒': '今天整體過得還好嗎？',
  '焦慮程度': '今天有感到緊繃或不安嗎？',
  '憂鬱程度': '今天心情有比較低落嗎？',
  '空虛程度': '有一種空空的感覺嗎？',
  '無聊程度': '今天有提不起勁嗎？',
  '難過程度': '今天有比較想哭或委屈嗎？',
  '開心程度': '今天有感到一點點開心嗎？',
  '無望感': '有覺得看不到出口嗎？',
  '孤獨感': '今天有覺得自己被落下嗎？',
  '動力': '今天做事有力氣嗎？',
  '自殺意念': '有出現讓你感到害怕的念頭嗎？',
  '食慾': '今天吃東西還順利嗎？',
  '能量': '今天身體的能量還夠嗎？',
  '活動量': '今天有稍微動一動嗎？',
  '疲倦程度': '今天是不是很累了？',
};

const Map<String, String> emotionRightIconMap = {
  // 舊有情緒
  '整體情緒': 'assets/emotion/overall.png',
  '焦慮程度': 'assets/emotion/anxious.png',
  '憂鬱程度': 'assets/emotion/depression.png',
  '空虛程度': 'assets/emotion/absence.png',
  '無聊程度': 'assets/emotion/boring.png',
  '難過程度': 'assets/emotion/sad.png',
  '開心程度': 'assets/emotion/happy.png',
  '無望感': 'assets/emotion/despair.png',
  '孤獨感': 'assets/emotion/loneliness.png',
  '動力': 'assets/emotion/power.png',
  '自殺意念': 'assets/emotion/自殺意念.png',
  '食慾': 'assets/emotion/食慾.png',
  '能量': 'assets/emotion/energy.png',
  '活動量': 'assets/emotion/活動量.png',
  '疲倦程度': 'assets/emotion/tired.png',
  // 整體狀態
  '平靜': 'assets/emotion/default.png',
  '開心': 'assets/emotion/happy.png',
  '有力量': 'assets/emotion/power.png',
  '疲憊': 'assets/emotion/tired.png',
  '沒動力': 'assets/emotion/boring.png',
  // 壓力情緒
  '焦慮': 'assets/emotion/anxious.png',
  '緊張': 'assets/emotion/anxious.png',
  '壓力大': 'assets/emotion/anxious.png',
  '煩躁': 'assets/emotion/anxious.png',
  '生氣': 'assets/emotion/anxious.png',
  // 低落警訊
  '難過': 'assets/emotion/sad.png',
  '憂鬱': 'assets/emotion/depression.png',
  '無助': 'assets/emotion/despair.png',
  '崩潰感': 'assets/emotion/despair.png',
};

/// 情緒分頁
class EmotionPage extends StatelessWidget {
  const EmotionPage({
    Key? key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onChangeValue,
  }) : super(key: key);

  final List<EmotionItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  final void Function(int index, int value) onChangeValue;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 🔹 情緒清單（Slider 版）
        ...List.generate(items.length, (i) {
          final item = items[i];
          return Container(
            margin: const EdgeInsets.only(bottom: HealingDesignSystem.paddingM),
            decoration: HealingDesignSystem.adaptiveCardDecoration(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HealingDesignSystem.paddingL,
                vertical: HealingDesignSystem.paddingM,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 情緒名稱 + 編輯 / 刪除
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🔹 左邊：情緒題目（主文）
                      Expanded(
                        child: Text(
                          emotionDisplayTextMap[item.name] ?? item.name,
                          style: HealingDesignSystem.titleSmall.copyWith(
                            color: HealingDesignSystem.adaptivePrimaryText(
                                context),
                          ),
                        ),
                      ),

                      // 🔹 右邊：引導 / 編輯 / 刪除
                      IconButton(
                        icon: const Icon(
                          Icons.info_outline,
                          color: HealingDesignSystem.primaryBlue,
                        ),
                        tooltip: '評分說明',
                        onPressed: () =>
                            showEmotionScaleGuideDialog(context, item.name),
                      ),

                      if (i != 0)
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: HealingDesignSystem.mutedText,
                          ),
                          onPressed: () => onRename(i),
                        ),

                      if (i != 0)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: HealingDesignSystem.mutedText,
                          ),
                          onPressed: () => onDelete(i),
                        ),
                    ],
                  ),

                  const SizedBox(height: HealingDesignSystem.paddingM),

                  // 🎚️ 情緒 Slider
                  EmotionSlider(
                    label: item.name,
                    value: item.value ?? 1,
                    onChanged: (v) => onChangeValue(i, v),
                    leftIcon: 'assets/emotion/default.png',
                    rightIcon: emotionRightIconMap[item.name] ??
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
        }),

        const SizedBox(height: HealingDesignSystem.paddingM),

        // ➕ 新增情緒
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: HealingDesignSystem.lineColor,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HealingDesignSystem.paddingL,
                  vertical: HealingDesignSystem.paddingM,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add,
                      color: HealingDesignSystem.primaryBlue,
                    ),
                    const SizedBox(width: HealingDesignSystem.paddingM),
                    Text(
                      '新增情緒項目',
                      style: HealingDesignSystem.labelMedium.copyWith(
                        color: HealingDesignSystem.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 症狀分頁
class SymptomPage extends StatelessWidget {
  final List<SymptomItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  final void Function(String name, bool selected) onTogglePreset;

  // 舊欄位保留：相容既有呼叫
  final bool isPeriod;
  final ValueChanged<bool> onTogglePeriod;

  // 新增：生理期月曆模式
  final Set<DateTime> periodMarkedDays;
  final DateTime periodFocusedMonth;
  final ValueChanged<DateTime> onTapPeriodDate;
  final ValueChanged<DateTime> onChangePeriodMonth;
  final int periodCycleLength;
  final DateTime? nextExpectedStart;
  final int? arrivalDeltaDays;
  final bool periodBusy;

  const SymptomPage({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.isPeriod,
    required this.onTogglePeriod,
    required this.onTogglePreset,
    required this.periodMarkedDays,
    required this.periodFocusedMonth,
    required this.onTapPeriodDate,
    required this.onChangePeriodMonth,
    required this.periodCycleLength,
    required this.nextExpectedStart,
    required this.arrivalDeltaDays,
    this.periodBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    const presetSymptoms = <String>{
      '心悸',
      '胸悶',
      '胸痛',
      '呼吸困難',
      '過度換氣',
      '胃食道逆流',
      '胃痛',
      '腹痛',
      '腹瀉',
      '便秘',
      '噁心反胃',
      '嘔吐',
      '脹氣',
      '食慾不振',
      '頭暈',
      '頭痛',
      '頭脹',
      '眼睛乾澀',
      '眼睛疲勞',
      '視力模糊',
      '不斷流淚',
      '耳鳴',
      '口乾舌燥',
      '失去味覺',
      '口腔苦澀',
      '咽喉異物感',
      '顫抖',
      '發麻',
      '手汗變多',
      '肌肉緊繃',
      '肌肉抽蓄',
      '四肢無力',
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PeriodCalendarCard(
          markedDays: periodMarkedDays,
          focusedMonth: periodFocusedMonth,
          isTodayPeriod: isPeriod,
          onTapDate: onTapPeriodDate,
          onChangeMonth: onChangePeriodMonth,
          cycleLength: periodCycleLength,
          nextExpectedStart: nextExpectedStart,
          arrivalDeltaDays: arrivalDeltaDays,
          busy: periodBusy,
        ),

        const SizedBox(height: 16),

        // 2. 症狀列表
        Container(
          padding: const EdgeInsets.all(HealingDesignSystem.paddingM),
          decoration: BoxDecoration(
            color: HealingDesignSystem.adaptiveFill(context),
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
            border: Border.all(
              color: HealingDesignSystem.lineColor,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: HealingDesignSystem.primaryBlue,
                size: 20,
              ),
              const SizedBox(width: HealingDesignSystem.paddingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '溫柔提醒',
                      style: HealingDesignSystem.titleSmall.copyWith(
                        color: HealingDesignSystem.adaptivePrimaryText(context),
                      ),
                    ),
                    const SizedBox(height: HealingDesignSystem.paddingS),
                    Text(
                      '不用很完整，想到什麼寫什麼就好。\n'
                      '也可以先寫一個最明顯的感覺：例如「心悸」「胸悶」「頭痛」。',
                      style: HealingDesignSystem.bodySmall.copyWith(
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: HealingDesignSystem.paddingL),

        // 2. 心血管症狀（勾選）
        Text(
          '心血管與呼吸',
          style: HealingDesignSystem.titleSmall.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        const SizedBox(height: HealingDesignSystem.paddingS),
        _buildSymptomChips(
          symptoms: ['心悸', '胸悶', '胸痛', '呼吸不順', '過度換氣'],
          items: items,
          onTogglePreset: onTogglePreset,
        ),

        const SizedBox(height: HealingDesignSystem.paddingL),

        // 3. 消化系統（勾選）
        Text(
          '消化系統',
          style: HealingDesignSystem.titleSmall.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        const SizedBox(height: HealingDesignSystem.paddingS),
        _buildSymptomChips(
          symptoms: [
            '胃食道逆流',
            '胃痛',
            '腹痛',
            '腹瀉',
            '便秘',
            '噁心反胃',
            '嘔吐',
            '脹氣',
            '食慾不振',
          ],
          items: items,
          onTogglePreset: onTogglePreset,
        ),

        const SizedBox(height: HealingDesignSystem.paddingL),

        // 4. 頭部（勾選）
        Text(
          '頭部',
          style: HealingDesignSystem.titleSmall.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        const SizedBox(height: HealingDesignSystem.paddingS),
        _buildSymptomChips(
          symptoms: ['頭暈', '頭痛', '頭脹'],
          items: items,
          onTogglePreset: onTogglePreset,
        ),

        const SizedBox(height: HealingDesignSystem.paddingL),

        // 5. 眼睛與耳朵（勾選）
        Text(
          '眼睛與耳朵',
          style: HealingDesignSystem.titleSmall.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        const SizedBox(height: HealingDesignSystem.paddingS),
        _buildSymptomChips(
          symptoms: ['眼睛乾澀', '眼睛疲勞', '視力模糊', '不斷流淚', '耳鳴'],
          items: items,
          onTogglePreset: onTogglePreset,
        ),

        const SizedBox(height: HealingDesignSystem.paddingL),

        // 6. 口腔與咽喉（勾選）
        Text(
          '口腔與咽喉',
          style: HealingDesignSystem.titleSmall.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        const SizedBox(height: HealingDesignSystem.paddingS),
        _buildSymptomChips(
          symptoms: ['口乾舌燥', '失去味覺', '口腔苦澀', '咽喉異物感'],
          items: items,
          onTogglePreset: onTogglePreset,
        ),

        const SizedBox(height: HealingDesignSystem.paddingL),

        // 7. 四肢與肌肉（勾選）
        Text(
          '四肢與肌肉',
          style: HealingDesignSystem.titleSmall.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        const SizedBox(height: HealingDesignSystem.paddingS),
        _buildSymptomChips(
          symptoms: ['顫抖', '發麻', '手汗變多', '肌肉緊繃', '肌肉抽蓄', '四肢無力'],
          items: items,
          onTogglePreset: onTogglePreset,
        ),

        const SizedBox(height: 12),

        // 8. 自訂症狀清單
        if (items.asMap().entries.any((e) =>
            e.value.name.trim().isNotEmpty &&
            !presetSymptoms.contains(e.value.name)))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: HealingDesignSystem.paddingL),
              Text(
                '自訂症狀清單',
                style: HealingDesignSystem.titleSmall.copyWith(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                ),
              ),
              const SizedBox(height: HealingDesignSystem.paddingS),
              Wrap(
                spacing: HealingDesignSystem.paddingL,
                runSpacing: HealingDesignSystem.paddingL,
                children: items
                    .asMap()
                    .entries
                    .where((e) =>
                        e.value.name.trim().isNotEmpty &&
                        !presetSymptoms.contains(e.value.name))
                    .map((e) => _buildCustomSymptomTag(
                          symptomName: e.value.name,
                          onEdit: () => onRename(e.key),
                          onDelete: () => onDelete(e.key),
                        ))
                    .toList(),
              ),
            ],
          ),

        const SizedBox(height: HealingDesignSystem.paddingL),

        // 3. 新增按鈕
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: HealingDesignSystem.lineColor,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HealingDesignSystem.paddingL,
                  vertical: HealingDesignSystem.paddingM,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add,
                      color: HealingDesignSystem.primaryBlue,
                    ),
                    const SizedBox(width: HealingDesignSystem.paddingM),
                    Text(
                      '新增症狀',
                      style: HealingDesignSystem.labelMedium.copyWith(
                        color: HealingDesignSystem.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 建立療癒風格的症狀卡片群組
  static Widget _buildSymptomChips({
    required List<String> symptoms,
    required List<SymptomItem> items,
    required void Function(String, bool) onTogglePreset,
  }) {
    return Wrap(
      spacing: HealingDesignSystem.paddingL,
      runSpacing: HealingDesignSystem.paddingL,
      children: symptoms.map((name) {
        final isSelected = items.any((s) => s.name == name);
        return _buildSymptomCard(
          name: name,
          isSelected: isSelected,
          onTap: () => onTogglePreset(name, !isSelected),
        );
      }).toList(),
    );
  }

  /// 單個療癒症狀卡片
  static Widget _buildSymptomCard({
    required String name,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Builder(
      builder: (context) => Material(
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
                        color:
                            HealingDesignSystem.primaryBlue.withOpacity(0.05),
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
                  name,
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
      ),
    );
  }

  /// 自訂症狀標籤
  static Widget _buildCustomSymptomTag({
    required String symptomName,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: HealingDesignSystem.paddingM,
          vertical: HealingDesignSystem.paddingS,
        ),
        decoration: BoxDecoration(
          color: HealingDesignSystem.adaptiveFill(context),
          border: Border.all(
            color: HealingDesignSystem.adaptiveCardBorder(context),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              symptomName,
              style: HealingDesignSystem.bodySmall,
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                icon: const Icon(Icons.edit, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onEdit,
              ),
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                icon: const Icon(Icons.close, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodCalendarCard extends StatefulWidget {
  final Set<DateTime> markedDays;
  final DateTime focusedMonth;
  final bool isTodayPeriod;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<DateTime> onChangeMonth;
  final int cycleLength;
  final DateTime? nextExpectedStart;
  final int? arrivalDeltaDays;
  final bool busy;

  const _PeriodCalendarCard({
    required this.markedDays,
    required this.focusedMonth,
    required this.isTodayPeriod,
    required this.onTapDate,
    required this.onChangeMonth,
    required this.cycleLength,
    required this.nextExpectedStart,
    required this.arrivalDeltaDays,
    required this.busy,
  });

  @override
  State<_PeriodCalendarCard> createState() => _PeriodCalendarCardState();
}

class _PeriodCalendarCardState extends State<_PeriodCalendarCard> {
  bool _collapsed = true;

  DateTime _d(DateTime date) => DateTime(date.year, date.month, date.day);

  String _monthText(DateTime month) => '${month.year}年${month.month}月';

  String _dateText(DateTime date) => '${date.month}/${date.day}';

  List<DateTime> _buildMonthCells(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final firstWeekdayOffset = (first.weekday - DateTime.monday + 7) % 7;
    final start = first.subtract(Duration(days: firstWeekdayOffset));
    return List.generate(42, (i) => _d(start.add(Duration(days: i))));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final month =
        DateTime(widget.focusedMonth.year, widget.focusedMonth.month, 1);
    final days = _buildMonthCells(month);
    final today = _d(DateTime.now());

    String etaText = '請點日期輸入月經第一天，系統會自動點亮後 6 天（共 7 天）';
    if (widget.nextExpectedStart != null) {
      etaText = '預估下次經期：${_dateText(widget.nextExpectedStart!)}';
    }

    String deltaText = '目前尚無提早/延遲資料';
    if (widget.arrivalDeltaDays != null) {
      if (widget.arrivalDeltaDays! > 0) {
        deltaText = '最近一次：延遲 ${widget.arrivalDeltaDays!} 天';
      } else if (widget.arrivalDeltaDays! < 0) {
        deltaText = '最近一次：提早 ${widget.arrivalDeltaDays!.abs()} 天';
      } else {
        deltaText = '最近一次：準時來';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A1C20) : HealingDesignSystem.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isTodayPeriod
              ? Colors.pinkAccent
              : (isDark ? Colors.pink.shade200 : Colors.pink.shade100),
          width: 1.3,
        ),
        boxShadow: isDark
            ? const []
            : [HealingDesignSystem.shadowLight(color: Colors.pinkAccent)],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.pink.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset(
                    'assets/icons/粉色水滴.png',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.isTodayPeriod ? '今天在生理期中 🩸' : '生理期月曆',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: widget.isTodayPeriod
                          ? Colors.pink
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (widget.busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  tooltip: _collapsed ? '展開月曆' : '縮合月曆',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _collapsed = !_collapsed),
                  icon: Icon(
                    _collapsed
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              firstCurve: Curves.easeOut,
              secondCurve: Curves.easeIn,
              crossFadeState: _collapsed
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Column(
                children: [
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.busy
                            ? null
                            : () => widget.onChangeMonth(
                                  DateTime(month.year, month.month - 1, 1),
                                ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            _monthText(month),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.busy
                            ? null
                            : () => widget.onChangeMonth(
                                  DateTime(month.year, month.month + 1, 1),
                                ),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Expanded(child: Center(child: Text('一'))),
                      Expanded(child: Center(child: Text('二'))),
                      Expanded(child: Center(child: Text('三'))),
                      Expanded(child: Center(child: Text('四'))),
                      Expanded(child: Center(child: Text('五'))),
                      Expanded(child: Center(child: Text('六'))),
                      Expanded(child: Center(child: Text('日'))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: days.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemBuilder: (_, i) {
                      final day = days[i];
                      final inMonth = day.month == month.month;
                      final selected = widget.markedDays.contains(day);
                      final isToday = _d(day) == today;

                      Color fg = inMonth
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withValues(alpha: 0.35);
                      Color bg = Colors.transparent;
                      BorderSide border = BorderSide.none;

                      if (selected) {
                        fg = Colors.white;
                        bg = Colors.pink;
                      } else if (isToday) {
                        border = BorderSide(
                          color: Colors.pink.withValues(alpha: 0.75),
                          width: 1.2,
                        );
                      }

                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: widget.busy ? null : () => widget.onTapDate(day),
                        child: Container(
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.fromBorderSide(border),
                          ),
                          child: Center(
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                color: fg,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '月曆已縮合，點右上角可展開。',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.66),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '系統自動計算平均週期：約 ${widget.cycleLength} 天',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.78),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              etaText,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.78),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              deltaText,
              style: TextStyle(
                color: widget.arrivalDeltaDays == null
                    ? colorScheme.onSurface.withValues(alpha: 0.72)
                    : (widget.arrivalDeltaDays == 0
                        ? Colors.green.shade600
                        : (widget.arrivalDeltaDays! > 0
                            ? Colors.orange.shade700
                            : Colors.blue.shade700)),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '點已亮的日期可取消。',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.66),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 睡眠分頁
class SleepPage extends StatelessWidget {
  SleepPage({
    super.key,
    required this.sleepTime,
    required this.wakeTime,
    required this.onPickSleepTime,
    required this.onPickWakeTime,
    required this.finalWakeTime,
    required this.onPickFinalWakeTime,
    required this.midWakeCtrl,
    required this.onChangeMidWake,
    required this.flags,
    required this.onToggleFlag,
    required this.sleepNote,
    required this.onChangeNote,
    required this.sleepQuality,
    required this.onPickValue,
    required this.naps,
    required this.onAddNap,
    required this.onEditNap,
    required this.onDeleteNap,
    required this.tookHypnotic,
    required this.onToggleHypnotic,
    required this.hypnoticName,
    required this.onChangeHypnoticName,
    required this.hypnoticDose,
    required this.onChangeHypnoticDose,
    required this.hypnoticNameCtrl,
    required this.hypnoticDoseCtrl,
  });

  final TimeOfDay? sleepTime;
  final TimeOfDay? wakeTime;
  final Future<void> Function() onPickSleepTime;
  final Future<void> Function() onPickWakeTime;
  final TimeOfDay? finalWakeTime;
  final Future<void> Function() onPickFinalWakeTime;
  final TextEditingController midWakeCtrl;
  final ValueChanged<String> onChangeMidWake;

  final Set<SleepFlag> flags;
  final void Function(SleepFlag) onToggleFlag;

  final String sleepNote;
  final void Function(String) onChangeNote;

  final int? sleepQuality;
  final Future<void> Function() onPickValue;

  final List<NapItem> naps;
  final Future<void> Function() onAddNap;
  final Future<void> Function(int) onEditNap;
  final void Function(int) onDeleteNap;

  final bool tookHypnotic;
  final ValueChanged<bool> onToggleHypnotic;
  final String hypnoticName;
  final ValueChanged<String> onChangeHypnoticName;
  final String hypnoticDose;
  final ValueChanged<String> onChangeHypnoticDose;
  final TextEditingController hypnoticNameCtrl;
  final TextEditingController hypnoticDoseCtrl;

  Widget _sleepCard({required Widget child, EdgeInsetsGeometry? margin}) {
    return Builder(
      builder: (context) => Container(
        margin: margin ?? const EdgeInsets.only(bottom: 10),
        decoration: HealingDesignSystem.adaptiveCardDecoration(context),
        child: child,
      ),
    );
  }

  InputDecoration _sleepInputDecoration({
    required BuildContext context,
    required String hintText,
    String? labelText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: HealingDesignSystem.adaptiveFill(context),
      hintStyle: TextStyle(
        color: HealingDesignSystem.adaptiveSecondaryText(context),
      ),
      labelStyle: TextStyle(
        color: HealingDesignSystem.adaptiveSecondaryText(context),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        borderSide: BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        borderSide: BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        borderSide: const BorderSide(
          color: HealingDesignSystem.primaryBlue,
          width: 1.4,
        ),
      ),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sleepCard(
          child: SwitchListTile(
            secondary: const Icon(
              Icons.medication_outlined,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('前一晚是否有吃安眠藥？'),
            value: tookHypnotic,
            activeColor: HealingDesignSystem.primaryBlue,
            onChanged: onToggleHypnotic,
          ),
        ),
        if (tookHypnotic) ...[
          _sleepCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 20,
                        color: HealingDesignSystem.mutedText,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '安眠藥名稱與劑量',
                        style: HealingDesignSystem.titleSmall.copyWith(
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hypnoticNameCtrl,
                    style: TextStyle(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
                    decoration: _sleepInputDecoration(
                      context: context,
                      hintText: '例如：Clonazepam（克癇平）',
                      prefixIcon: const Icon(Icons.local_pharmacy_outlined),
                    ),
                    onChanged: onChangeHypnoticName,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hypnoticDoseCtrl,
                    style: TextStyle(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
                    decoration: _sleepInputDecoration(
                      context: context,
                      hintText: '例如：0.5 mg',
                      prefixIcon: const Icon(Icons.numbers),
                    ),
                    onChanged: onChangeHypnoticDose,
                  ),
                ],
              ),
            ),
          ),
        ],
        _sleepCard(
          child: ListTile(
            leading: const Icon(
              Icons.bed_outlined,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('前一日準備睡覺時間'),
            subtitle: Text(
                sleepTime == null ? '—' : DateHelper.formatTime(sleepTime!)),
            onTap: onPickSleepTime,
          ),
        ),
        _sleepCard(
          child: ExpansionTile(
            leading: const Icon(
              Icons.nightlight_outlined,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('夜間睡眠狀況',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              flags.isEmpty ? '未選擇' : '已選 ${flags.length} 項',
              style: const TextStyle(
                color: HealingDesignSystem.mutedText,
                fontSize: 13,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('可多選',
                        style: TextStyle(
                          fontSize: 12,
                          color: HealingDesignSystem.mutedText,
                        )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (() {
                        const desired = [
                          '優',
                          '良好',
                          '早醒',
                          '多夢',
                          '淺眠',
                          '夜尿',
                          '睡睡醒醒',
                          '睡眠不足',
                          '入睡困難 (躺超過 30 分鐘才入睡)',
                          '睡眠中斷 (醒來後超過 30 分鐘才又入睡)',
                        ];

                        final list = SleepFlag.values.toList()
                          ..sort((a, b) {
                            int ia = desired.indexOf(sleepFlagLabel(a));
                            int ib = desired.indexOf(sleepFlagLabel(b));
                            if (ia < 0) ia = 999;
                            if (ib < 0) ib = 999;
                            return ia.compareTo(ib);
                          });

                        return list.map((f) {
                          final selected = flags.contains(f);
                          return ChoiceChip(
                            label: Text(sleepFlagLabel(f)),
                            selected: selected,
                            onSelected: (_) => onToggleFlag(f),
                            selectedColor: HealingDesignSystem.primaryBlue
                                .withOpacity(0.16),
                            side: BorderSide(
                              color: selected
                                  ? HealingDesignSystem.primaryBlue
                                  : HealingDesignSystem.lineColor,
                            ),
                            labelStyle: TextStyle(
                              color: selected
                                  ? HealingDesignSystem.primaryBlue
                                  : HealingDesignSystem.adaptivePrimaryText(
                                      context),
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  HealingDesignSystem.radiusM),
                            ),
                          );
                        }).toList();
                      })(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _sleepCard(
          child: ListTile(
            leading: const Icon(
              Icons.star_border_rounded,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('自覺睡眠品質'),
            subtitle: Text(sleepQuality == null ? '—' : '$sleepQuality'),
            onTap: onPickValue,
          ),
        ),
        _sleepCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '睡眠註記',
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  minLines: 1,
                  maxLines: 3,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                  decoration: _sleepInputDecoration(
                    context: context,
                    hintText: '例如：一直做夢，感覺好像沒睡覺，起床精神很差',
                    prefixIcon: const Icon(Icons.edit_note),
                  ),
                  onChanged: onChangeNote,
                ),
              ],
            ),
          ),
        ),
        _sleepCard(
          margin: const EdgeInsets.fromLTRB(0, 2, 0, 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HealingDesignSystem.adaptiveFill(context),
              borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
              border: Border.all(color: HealingDesignSystem.lineColor),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  color: HealingDesignSystem.primaryBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '紀錄小撇步',
                        style: HealingDesignSystem.titleSmall.copyWith(
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '半夜醒來或剛睡醒時不想開 App？\n試試「手機截圖」！起床後再看相簿時間回填即可，減少看螢幕的焦慮。',
                        style: HealingDesignSystem.bodySmall.copyWith(
                          color: HealingDesignSystem.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _sleepCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '中途與甦醒',
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: midWakeCtrl,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                  decoration: _sleepInputDecoration(
                    context: context,
                    labelText: '半夜醒來時間 (可留白)',
                    hintText: '例：03:15, 05:40 (看截圖時間)',
                    prefixIcon: const Icon(Icons.access_time_outlined),
                  ),
                  onChanged: onChangeMidWake,
                ),
              ],
            ),
          ),
        ),
        _sleepCard(
          child: ListTile(
            leading: const Icon(
              Icons.wb_twilight,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('甦醒時刻 (睜開眼)'),
            subtitle: Text(
              finalWakeTime == null
                  ? '尚未設定'
                  : DateHelper.formatTime(finalWakeTime),
              style: TextStyle(
                color: finalWakeTime == null
                    ? colorScheme.onSurfaceVariant
                    : onSurface,
              ),
            ),
            onTap: onPickFinalWakeTime,
          ),
        ),
        _sleepCard(
          child: ListTile(
            leading: const Icon(
              Icons.directions_run,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('離床活動時間'),
            subtitle: Text(
              wakeTime == null ? '—' : DateHelper.formatTime(wakeTime),
            ),
            onTap: onPickWakeTime,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '小睡（可新增多筆)',
          style: HealingDesignSystem.titleSmall.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(naps.length, (i) {
          final n = naps[i];
          return _sleepCard(
            child: ListTile(
              leading: const Icon(
                Icons.timer_outlined,
                color: HealingDesignSystem.primaryBlue,
              ),
              title: Text(
                  '${DateHelper.formatTime(n.start)} – ${DateHelper.formatTime(n.end)}'),
              subtitle: Text(
                  '時長：${DateHelper.formatDurationText(n.durationMinutes)}'),
              onTap: () => onEditNap(i),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDeleteNap(i),
              ),
            ),
          );
        }),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: HealingDesignSystem.lineColor,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAddNap,
              borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: HealingDesignSystem.paddingL,
                  vertical: HealingDesignSystem.paddingM,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: HealingDesignSystem.primaryBlue),
                    SizedBox(width: HealingDesignSystem.paddingM),
                    Text(
                      '新增小睡',
                      style: TextStyle(
                        color: HealingDesignSystem.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
