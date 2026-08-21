import 'package:flutter/material.dart';

import '../models/calendar_day_summary.dart';

enum UnifiedCalendarMode {
  diary,
  record,
  period,
  overview,
}

class UnifiedCalendarWidget extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final DateTime focusedMonth;
  final ValueChanged<DateTime>? onMonthChanged;
  final UnifiedCalendarMode mode;
  final Map<String, CalendarDaySummary> summariesByDate;
  final bool showInternalPeriodLegend;

  const UnifiedCalendarWidget({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    required this.focusedMonth,
    required this.mode,
    required this.summariesByDate,
    this.showInternalPeriodLegend = true,
    this.onMonthChanged,
  });

  @override
  State<UnifiedCalendarWidget> createState() => _UnifiedCalendarWidgetState();
}

class _UnifiedCalendarWidgetState extends State<UnifiedCalendarWidget> {
  static const int _basePage = 1200;
  static const double _cellExtent = 48;
  static const double _gridMainSpacing = 6;
  static const double _gridCrossSpacing = 4;
  static const double _dotSize = 4.5;
  static const double _dotGap = 3;

  late final PageController _pageController;
  late DateTime _anchorMonth;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _anchorMonth =
        DateTime(widget.focusedMonth.year, widget.focusedMonth.month, 1);
    _currentPage = _basePage;
    _pageController = PageController(initialPage: _basePage);
  }

  @override
  void didUpdateWidget(covariant UnifiedCalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFocused =
        DateTime(oldWidget.focusedMonth.year, oldWidget.focusedMonth.month, 1);
    final newFocused =
        DateTime(widget.focusedMonth.year, widget.focusedMonth.month, 1);
    if (!_isSameMonth(oldFocused, newFocused)) {
      _anchorMonth = newFocused;
      _currentPage = _basePage;
      _pageController.jumpToPage(_basePage);
    }
  }

  Future<void> _goToPage(int page) async {
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  DateTime _monthFromPage(int page) {
    final delta = page - _basePage;
    return DateTime(_anchorMonth.year, _anchorMonth.month + delta, 1);
  }

  List<DateTime> _buildMonthGrid(DateTime month) {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final firstWeekdayIndex = firstDayOfMonth.weekday % 7;
    final gridStart =
        firstDayOfMonth.subtract(Duration(days: firstWeekdayIndex));
    return List.generate(42, (index) {
      final day = gridStart.add(Duration(days: index));
      return DateTime(day.year, day.month, day.day);
    });
  }

  CalendarDaySummary? _summaryOf(DateTime date) {
    return widget.summariesByDate[_dateKey(date)];
  }

  List<Color> _buildDotColors(
      CalendarDaySummary? summary, UnifiedCalendarMode mode) {
    if (summary == null) return const [];

    const dailyDot = Color(0xFF4A90E2);
    const diaryDot = Color(0xFFC9B6FF);
    const quickRecordDot = Color(0xFF58B8C0);
    const symptomDot = Color(0xFFF4B183);
    const sleepDot = Color(0xFF9AB3F5);
    const periodAssistDot = Color(0x664A90E2);

    switch (mode) {
      case UnifiedCalendarMode.diary:
        return summary.hasDiary ? const [diaryDot] : const [];
      case UnifiedCalendarMode.record:
        return <Color>[
          if (summary.hasDailyRecord || summary.hasQuickRecord) dailyDot,
          if (summary.hasEmotionData) quickRecordDot,
          if (summary.hasSymptomData) symptomDot,
          if (summary.hasSleepData) sleepDot,
        ].take(3).toList();
      case UnifiedCalendarMode.period:
        return summary.hasDailyRecord ? const [periodAssistDot] : const [];
      case UnifiedCalendarMode.overview:
        return <Color>[
          if (summary.hasDiary) diaryDot,
          if (summary.hasQuickRecord) quickRecordDot,
          if (summary.hasDailyCheckIn) dailyDot,
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final shownMonth = _monthFromPage(_currentPage);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3FBFA), Color(0xFFF8FDFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDEFF1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CalendarHeader(
              month: shownMonth,
              onPrev: () => _goToPage(_currentPage - 1),
              onNext: () => _goToPage(_currentPage + 1),
            ),
            const SizedBox(height: 10),
            Row(
              children: _weekLabels
                  .map(
                    (label) => Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF7EA4A9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: (_cellExtent * 6) + (_gridMainSpacing * 5),
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (page) {
                  final month = _monthFromPage(page);
                  setState(() {
                    _currentPage = page;
                  });
                  widget.onMonthChanged?.call(month);
                },
                itemBuilder: (context, page) {
                  final month = _monthFromPage(page);
                  final cells = _buildMonthGrid(month);
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: _gridMainSpacing,
                      crossAxisSpacing: _gridCrossSpacing,
                      mainAxisExtent: _cellExtent,
                    ),
                    itemCount: cells.length,
                    itemBuilder: (_, index) {
                      final date = cells[index];
                      final summary = _summaryOf(date);
                      final isInMonth = date.month == month.month;
                      final isSelected = _isSameDay(date, widget.selectedDate);
                      final isToday = _isSameDay(date, DateTime.now());
                      final dots = _buildDotColors(summary, widget.mode);

                      return _CalendarDayCell(
                        date: date,
                        isInMonth: isInMonth,
                        isSelected: isSelected,
                        isToday: isToday,
                        isPeriodDay: summary?.isPeriodDay ?? false,
                        isPredictedPeriodDay:
                            summary?.isPredictedPeriodDay ?? false,
                        dotColors: dots,
                        dotSize: _dotSize,
                        dotGap: _dotGap,
                        onTap: () => widget.onDateSelected(date),
                      );
                    },
                  );
                },
              ),
            ),
            if (widget.showInternalPeriodLegend) ...[
              const SizedBox(height: 10),
              const _PeriodLegend(),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeriodLegend extends StatelessWidget {
  const _PeriodLegend();

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF6F8F95),
          fontWeight: FontWeight.w600,
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('●',
            style: TextStyle(color: Color(0xFFF2A8C3), fontSize: 12)),
        const SizedBox(width: 4),
        Text('生理期', style: textStyle),
        const SizedBox(width: 12),
        const Text('○',
            style: TextStyle(color: Color(0xFFE6A6C0), fontSize: 12)),
        const SizedBox(width: 4),
        Text('預測生理期', style: textStyle),
      ],
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _CalendarHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _SoftIconButton(icon: Icons.chevron_left, onTap: onPrev),
        Text(
          '${month.year} 年 ${month.month} 月',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF2C6E7B),
                fontWeight: FontWeight.w700,
              ),
        ),
        _SoftIconButton(icon: Icons.chevron_right, onTap: onNext),
      ],
    );
  }
}

class _SoftIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SoftIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF7F8),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, color: const Color(0xFF4C8C97)),
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime date;
  final bool isInMonth;
  final bool isSelected;
  final bool isToday;
  final bool isPeriodDay;
  final bool isPredictedPeriodDay;
  final List<Color> dotColors;
  final double dotSize;
  final double dotGap;
  final VoidCallback onTap;

  const _CalendarDayCell({
    required this.date,
    required this.isInMonth,
    required this.isSelected,
    required this.isToday,
    required this.isPeriodDay,
    required this.isPredictedPeriodDay,
    required this.dotColors,
    required this.dotSize,
    required this.dotGap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const selectedBg = Color(0xFF2E6FC2);
    const selectedFg = Colors.white;
    const todayBorder = Color(0xFF61A8B5);
    const periodBg = Color(0x99F7A9C4);
    const predictedPeriodBg = Color(0x00FFFFFF);
    const predictedBorder = Color(0x66E7A7C1);

    final foregroundColor = isSelected
        ? selectedFg
        : isInMonth
            ? const Color(0xFF2F4A52)
            : const Color(0xFFAABDC2);

    Color dayBg = Colors.transparent;
    Border? dayBorder;
    List<Color> displayDots = dotColors.take(3).toList();

    // Visual priority: selected > today > period > predicted > normal.
    if (isSelected) {
      dayBg = selectedBg;
      displayDots = displayDots.map((_) => const Color(0xFFEFF6FF)).toList();
    } else if (isToday) {
      dayBorder = Border.all(color: todayBorder, width: 1.7);
      if (isPeriodDay) {
        dayBg = periodBg;
      } else if (isPredictedPeriodDay) {
        dayBg = predictedPeriodBg;
        dayBorder = Border.all(color: predictedBorder, width: 1.2);
      }
    } else if (isPeriodDay) {
      dayBg = periodBg;
    } else if (isPredictedPeriodDay) {
      dayBg = predictedPeriodBg;
      dayBorder = Border.all(color: predictedBorder, width: 1.1);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox.expand(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dayBg,
                  shape: BoxShape.circle,
                  border: dayBorder,
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (displayDots.isNotEmpty)
                Positioned(
                  bottom: 4,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: dotSize,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < displayDots.length; i++)
                          Container(
                            width: dotSize,
                            height: dotSize,
                            margin: EdgeInsets.only(
                              right: i == displayDots.length - 1 ? 0 : dotGap,
                            ),
                            decoration: BoxDecoration(
                              color: displayDots[i],
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<String> _weekLabels = ['日', '一', '二', '三', '四', '五', '六'];

String _dateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isSameMonth(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month;
}
