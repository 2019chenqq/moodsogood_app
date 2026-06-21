import 'package:flutter/material.dart';
import '../../constants/healing_design_system.dart';
import '../daily_record_helpers.dart';

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
  final bool showPeriodCalendar;

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
    this.showPeriodCalendar = true,
  });

  @override
  Widget build(BuildContext context) {
    const presetSymptoms = <String>{
      '心悸', '胸悶', '胸痛', '呼吸困難', '過度換氣',
      '胃食道逆流', '胃痛', '腹痛', '腹瀉', '便秘', '噁心反胃', '嘔吐', '脹氣', '食慾不振',
      '頭暈', '頭痛', '頭脹',
      '眼睛乾澀', '眼睛疲勞', '視力模糊', '不斷流淚', '耳鳴',
      '口乾舌燥', '味覺失調', '口腔苦澀', '咽喉異物感',
      '顫抖', '發麻', '手汗變多', '肌肉緊繃', '肌肉抽蓄', '四肢無力','頭重腳輕', '肌肉不自主抽動',
      '疲倦', '睏倦', '嗜睡',
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (showPeriodCalendar) ...[
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
        ],

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
            '胃食道逆流', '胃痛', '腹痛', '腹瀉', '便秘', '噁心反胃', '嘔吐', '脹氣', '食慾不振'],
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
          symptoms: ['口乾舌燥', '味覺失調', '口腔苦澀', '咽喉異物感'],
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
          symptoms: ['顫抖', '發麻', '手汗變多', '肌肉緊繃', '肌肉抽蓄', '四肢無力', '頭重腳輕', '肌肉不自主抽動'],
          items: items,
          onTogglePreset: onTogglePreset,
        ),

const SizedBox(height: HealingDesignSystem.paddingL),

 // 7. 能量（勾選）
        Text(
          '能量',
          style: HealingDesignSystem.titleSmall.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        const SizedBox(height: HealingDesignSystem.paddingS),
        _buildSymptomChips(
          symptoms: ['疲倦', '睏倦', '嗜睡'],
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
    VoidCallback? onEdit,
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
