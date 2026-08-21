import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../../utils/date_helper.dart';
import '../models/sleep_insight_models.dart';

class SleepInsightsView extends StatelessWidget {
  const SleepInsightsView({
    super.key,
    required this.result,
    required this.onOpenDate,
  });

  final SleepInsightResult result;
  final ValueChanged<DateTime> onOpenDate;

  @override
  Widget build(BuildContext context) {
    final summary = result.summary;
    final comparisonDays =
        result.endDate.difference(result.startDate).inDays + 1;
    final comparisonTitle = result.comparison.previous == null
        ? '區間比較'
        : '與前一個 $comparisonDays 天比較';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsightCard(lines: result.narrative),
        const SizedBox(height: 12),
        _SectionCard(
          title: '睡眠摘要',
          icon: Icons.nightlight_round,
          initiallyExpanded: true,
          child: Column(
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.35,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  _MetricTile(
                    label: '平均夜眠',
                    value: _duration(summary.averageNightMinutes),
                    caption: '${summary.validNightDays} 天有效時間',
                  ),
                  _MetricTile(
                    label: '平均全日睡眠',
                    value: _duration(summary.averageTotalMinutes),
                    caption: '夜眠＋小睡',
                  ),
                  _MetricTile(
                    label: '平均睡眠品質',
                    value: summary.averageQuality?.toStringAsFixed(1) ?? '資料不足',
                    caption: '${summary.qualityDays} 天有填寫',
                  ),
                  _MetricTile(
                    label: '睡眠紀錄天數',
                    value: '${summary.recordDays} 天',
                    caption: '完成率 ${(summary.completionRate * 100).round()}%',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SmallMetric(
                      '最短夜眠',
                      _duration(summary.shortestNightMinutes),
                    ),
                    _SmallMetric(
                      '最長夜眠',
                      _duration(summary.longestNightMinutes),
                    ),
                    _SmallMetric(
                      '小睡',
                      '${summary.napCount} 次／${summary.napDays} 天，'
                          '平均 ${_duration(summary.averageNapMinutes)}',
                    ),
                    _SmallMetric('安眠藥紀錄', '${summary.hypnoticDays} 天'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '睡眠狀況：${_topFlags(result.points)}',
                  style: const TextStyle(height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '睡眠趨勢',
          icon: Icons.show_chart_rounded,
          initiallyExpanded: true,
          child: SleepTrendChart(points: result.points, summary: summary),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: comparisonTitle,
          icon: Icons.compare_arrows_rounded,
          child: _ComparisonContent(
            comparison: result.comparison,
            currentStart: result.startDate,
            currentEnd: result.endDate,
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '睡眠規律度',
          icon: Icons.timeline_rounded,
          child: _RegularityContent(result: result.regularity),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '連續變化',
          icon: Icons.multiline_chart_rounded,
          child: _EpisodesContent(episodes: result.episodes),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '睡眠與每日狀態',
          icon: Icons.bubble_chart_outlined,
          child: _AssociationContent(
            association: result.association,
            periodDays: result.points.where((point) => point.isPeriod).length,
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '值得回顧的日期',
          icon: Icons.bookmark_outline_rounded,
          child: _HighlightsContent(
            highlights: result.highlights,
            onOpenDate: onOpenDate,
          ),
        ),
      ],
    );
  }
}

class SleepTrendChart extends StatefulWidget {
  const SleepTrendChart({
    super.key,
    required this.points,
    required this.summary,
    this.showTotalSeries = true,
  });

  /// 是否顯示「全日睡眠」與切換開關；回診趨勢卡片通常關閉（只顯示夜間）。
  final bool showTotalSeries;
  final List<SleepTrendPoint> points;
  final SleepPeriodSummary summary;

  @override
  State<SleepTrendChart> createState() => _SleepTrendChartState();
}

class _SleepTrendChartState extends State<SleepTrendChart> {
  bool _showTotal = true;
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final showTotal = widget.showTotalSeries && _showTotal;
    final valid = points.where((point) => point.nightMinutes != null).toList();
    if (valid.isEmpty) {
      return const _EmptyMessage('目前沒有可繪製趨勢的有效夜眠時間。');
    }
    final maxMinutes = points
        .expand((point) => [
              point.nightMinutes,
              if (point.napMinutes > 0) point.napMinutes,
              if (showTotal) point.totalMinutes,
            ])
        .whereType<int>()
        .fold<int>(0, math.max);
    final maxY = math.max(12.0, (maxMinutes / 60).ceilToDouble() + 1);
    final nightSpots = <FlSpot>[];
    final totalSpots = <FlSpot>[];
    final napSpots = <FlSpot>[];
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      if (point.nightMinutes != null) {
        nightSpots.add(FlSpot(index.toDouble(), point.nightMinutes! / 60));
      }
      if (showTotal && point.totalMinutes != null) {
        totalSpots.add(FlSpot(index.toDouble(), point.totalMinutes! / 60));
      }
      if (point.napMinutes > 0) {
        napSpots.add(FlSpot(index.toDouble(), point.napMinutes / 60));
      }
    }
    final step =
        math.max(1, (points.length / (points.length <= 30 ? 5 : 7)).ceil());
    final periodRanges = _periodRanges(points);
    final selected = _selectedIndex == null || _selectedIndex! >= points.length
        ? null
        : points[_selectedIndex!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '每日夜間睡眠與全日睡眠',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (widget.showTotalSeries) ...[
              Switch.adaptive(
                value: _showTotal,
                onChanged: (value) => setState(() => _showTotal = value),
              ),
              const Text('全日'),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 250,
          child: Semantics(
            label: '睡眠趨勢圖，共 ${valid.length} 天有效夜眠紀錄',
            child: LineChart(
              LineChartData(
                minX: -0.4,
                maxX: math.max(1, points.length - 1).toDouble() + 0.4,
                minY: 0,
                maxY: maxY,
                rangeAnnotations: RangeAnnotations(
                  verticalRangeAnnotations: periodRanges,
                  horizontalRangeAnnotations:
                      widget.summary.averageNightMinutes == null
                          ? const []
                          : [
                              HorizontalRangeAnnotation(
                                y1: widget.summary.averageNightMinutes! / 60 -
                                    0.025,
                                y2: widget.summary.averageNightMinutes! / 60 +
                                    0.025,
                                color: HealingDesignSystem.mutedText
                                    .withValues(alpha: 0.65),
                              ),
                            ],
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map((spot) => LineTooltipItem(
                              '${points[spot.x.round()].date.month}/${points[spot.x.round()].date.day}',
                              const TextStyle(fontWeight: FontWeight.w700),
                            ))
                        .toList(),
                  ),
                  touchCallback: (event, response) {
                    final spots = response?.lineBarSpots;
                    if (!event.isInterestedForInteractions ||
                        spots == null ||
                        spots.isEmpty) {
                      return;
                    }
                    setState(() => _selectedIndex = spots.first.x.round());
                  },
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: 2,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color:
                        HealingDesignSystem.lineColor.withValues(alpha: 0.45),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: 2,
                      getTitlesWidget: (value, _) => Text('${value.toInt()}h'),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 34,
                      getTitlesWidget: (value, _) {
                        final index = value.round();
                        if ((value - index).abs() > 0.01 ||
                            index < 0 ||
                            index >= points.length) {
                          return const SizedBox.shrink();
                        }
                        if (index % step != 0 && index != points.length - 1) {
                          return const SizedBox.shrink();
                        }
                        final date = points[index].date;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${date.month}/${date.day}',
                              style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: nightSpots,
                    isCurved: false,
                    color: HealingDesignSystem.primaryBlue,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                  ),
                  if (showTotal)
                    LineChartBarData(
                      spots: totalSpots,
                      isCurved: false,
                      color: const Color(0xFF5E8E78),
                      barWidth: 2,
                      dashArray: [6, 4],
                      dotData: const FlDotData(show: false),
                    ),
                  if (napSpots.isNotEmpty)
                    LineChartBarData(
                      spots: napSpots,
                      color: Colors.transparent,
                      barWidth: 0,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                          radius: 4.5,
                          color: const Color(0xFFE5A45F),
                          strokeColor: Theme.of(context).colorScheme.surface,
                          strokeWidth: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 250),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _Legend(label: '夜間睡眠', color: HealingDesignSystem.primaryBlue),
            _Legend(label: '全日睡眠（虛線）', color: Color(0xFF5E8E78)),
            _Legend(label: '小睡總時長', color: Color(0xFFE5A45F)),
            _Legend(label: '生理期區間', color: Color(0x55F19AB5)),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: selected == null
              ? const Text('點選圖表資料點可查看當日紀錄。')
              : _PointDetails(key: ValueKey(selected.date), point: selected),
        ),
      ],
    );
  }

  List<VerticalRangeAnnotation> _periodRanges(List<SleepTrendPoint> points) {
    final ranges = <VerticalRangeAnnotation>[];
    int? start;
    for (var index = 0; index <= points.length; index++) {
      final isPeriod = index < points.length && points[index].isPeriod;
      if (isPeriod) {
        start ??= index;
      } else if (start != null) {
        ranges.add(VerticalRangeAnnotation(
          x1: start - 0.5,
          x2: index - 0.5,
          color: const Color(0x55F19AB5),
        ));
        start = null;
      }
    }
    return ranges;
  }
}

class _PointDetails extends StatelessWidget {
  const _PointDetails({super.key, required this.point});
  final SleepTrendPoint point;

  @override
  Widget build(BuildContext context) {
    final flag = point.flags.isEmpty
        ? '未記錄'
        : (_sleepFlagLabels[point.flags.first] ?? point.flags.first);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${point.date.month}/${point.date.day}${point.isPeriod ? '｜生理期' : ''}\n'
        '夜間睡眠：${_duration(point.nightMinutes)}${point.usedEstimatedSleepTime ? '（使用推估入睡時間）' : '（依準備睡覺時間估算）'}\n'
        '${point.nightAwakeMinutes > 0 ? '睡眠區間：${_duration(point.sleepWindowMinutes)}，扣除夜間清醒 ${_duration(point.nightAwakeMinutes)}\n' : ''}'
        '小睡：${_duration(point.napMinutes)}｜全日：${_duration(point.totalMinutes)}\n'
        '自覺品質：${point.quality ?? '未填寫'}｜主要狀況：$flag',
        style: const TextStyle(height: 1.5),
      ),
    );
  }
}

class _ComparisonContent extends StatelessWidget {
  const _ComparisonContent({
    required this.comparison,
    required this.currentStart,
    required this.currentEnd,
  });
  final SleepComparisonResult comparison;
  final DateTime currentStart;
  final DateTime currentEnd;

  @override
  Widget build(BuildContext context) {
    final comparisonDays = currentEnd.difference(currentStart).inDays + 1;
    final previousEnd = currentStart.subtract(const Duration(days: 1));
    final previousStart = previousEnd.subtract(
      Duration(days: comparisonDays - 1),
    );
    final ranges = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('目前區間：${_dateRange(currentStart, currentEnd)}'),
          if (comparison.previous != null) ...[
            const SizedBox(height: 4),
            Text('比較區間：${_dateRange(previousStart, previousEnd)}'),
          ],
        ],
      ),
    );
    if (!comparison.isAvailable || comparison.previous == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ranges,
          const SizedBox(height: 8),
          _EmptyMessage(comparison.reason ?? '資料不足'),
        ],
      );
    }
    final current = comparison.current;
    final previous = comparison.previous!;
    final rows = <String>[
      _deltaDuration(
          '平均夜眠', current.averageNightMinutes, previous.averageNightMinutes),
      _deltaDuration(
          '平均全日睡眠', current.averageTotalMinutes, previous.averageTotalMinutes),
      _qualityDelta(current.averageQuality, previous.averageQuality),
      _clockDelta('記錄的睡覺時間', current.averageBedtimeMinutes,
          previous.averageBedtimeMinutes),
      _clockDelta(
          '醒來時間', current.averageWakeMinutes, previous.averageWakeMinutes),
      '目前區間有 ${current.napDays} 天記錄小睡，上一個區間為 ${previous.napDays} 天。',
      '睡眠紀錄完成率由 ${(previous.completionRate * 100).round()}% '
          '變為 ${(current.completionRate * 100).round()}%。',
    ];
    return Column(
      children: [
        ranges,
        const SizedBox(height: 8),
        ...rows.map((row) => _TextRow(text: row)),
      ],
    );
  }
}

class _RegularityContent extends StatelessWidget {
  const _RegularityContent({required this.result});
  final SleepRegularityResult result;

  @override
  Widget build(BuildContext context) {
    if (!result.isAvailable) return const _EmptyMessage('目前紀錄不足以計算規律度。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(result.label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _TextRow(
            text: '夜眠時長波動：約 ${_duration(result.durationVariationMinutes)}'),
        _TextRow(
            text: '記錄的睡覺時間波動：約 ${_duration(result.bedtimeVariationMinutes)}'),
        _TextRow(text: '醒來時間波動：約 ${_duration(result.wakeVariationMinutes)}'),
        const SizedBox(height: 8),
        const Text('規律度僅根據你的紀錄計算，不代表醫療評估結果。'),
      ],
    );
  }
}

class _EpisodesContent extends StatelessWidget {
  const _EpisodesContent({required this.episodes});
  final List<SleepChangeEpisode> episodes;

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) return const _EmptyMessage('本期未找到符合規則的連續變化。');
    return Column(
      children: episodes.take(6).map((episode) {
        final date = '${episode.startDate.month}/${episode.startDate.day} 至 '
            '${episode.endDate.month}/${episode.endDate.day}';
        final text = switch (episode.kind) {
          SleepChangeKind.decreasing =>
            '$date 的夜間睡眠連續縮短，共減少 ${_duration(episode.changeMinutes.abs())}。',
          SleepChangeKind.increasing =>
            '$date 的夜間睡眠連續增加，共增加 ${_duration(episode.changeMinutes.abs())}。',
          SleepChangeKind.belowBaseline => '$date 連續低於個人近期平均一定幅度。',
          SleepChangeKind.largeChange =>
            '$date 的相鄰紀錄差異為 ${_duration(episode.changeMinutes.abs())}。',
        };
        return _TextRow(text: '$text 這項結果只反映你的紀錄。');
      }).toList(),
    );
  }
}

class _AssociationContent extends StatelessWidget {
  const _AssociationContent(
      {required this.association, required this.periodDays});
  final SleepStateAssociation association;
  final int periodDays;

  @override
  Widget build(BuildContext context) {
    if (association.lowSleepDays == 0 || association.sameDayPairedDays == 0) {
      return const _EmptyMessage('目前同時具有睡眠與情緒／症狀資料的日期不足。');
    }
    String counts(Map<String, int> values) => values.entries
        .take(5)
        .map((entry) => '${entry.key} ${entry.value} 次')
        .join('、');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '在 ${association.lowSleepDays} 個夜眠低於本期平均的日期中，'
          '有 ${association.sameDayPairedDays} 天同時具有情緒或症狀紀錄。',
        ),
        if (association.sameDayCounts.isNotEmpty)
          _TextRow(text: '同日較常記錄：${counts(association.sameDayCounts)}。'),
        if (association.nextDayCounts.isNotEmpty)
          _TextRow(text: '隔日較常記錄：${counts(association.nextDayCounts)}。'),
        if (association.pairedDates.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...association.pairedDates.take(8).map(
                (pair) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: HealingDesignSystem.adaptiveFill(context),
                    borderRadius: BorderRadius.circular(10),
                    border: pair.isPeriod
                        ? Border.all(color: const Color(0xFFF19AB5))
                        : null,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${pair.date.month}/${pair.date.day}｜${_duration(pair.nightMinutes)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (pair.isPeriod)
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(Icons.water_drop_outlined, size: 15),
                          label: Text('生理期'),
                        ),
                      if (pair.overallMood != null)
                        Text('整體情緒 ${pair.overallMood!.toStringAsFixed(1)}'),
                      if (pair.sameDayLabels.isNotEmpty)
                        Text('同日：${pair.sameDayLabels.join('、')}'),
                      if (pair.nextDayLabels.isNotEmpty)
                        Text('隔日：${pair.nextDayLabels.join('、')}'),
                    ],
                  ),
                ),
              ),
        ],
        if (periodDays > 0)
          _TextRow(text: '所選期間共有 $periodDays 天標示為生理期，可與同期記錄一起回顧。'),
        const SizedBox(height: 8),
        const Text('共同出現不代表因果關係。'),
      ],
    );
  }
}

class _HighlightsContent extends StatelessWidget {
  const _HighlightsContent(
      {required this.highlights, required this.onOpenDate});
  final List<SleepHighlightDate> highlights;
  final ValueChanged<DateTime> onOpenDate;

  @override
  Widget build(BuildContext context) {
    if (highlights.isEmpty) return const _EmptyMessage('目前沒有可列入的回顧日期。');
    return Column(
      children: highlights.map((item) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
              '${item.date.month}/${item.date.day}${item.isPeriod ? ' · 生理期' : ''}'),
          subtitle: Text(
              '${_duration(item.nightMinutes)}\n${item.reasons.join('、')}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => onOpenDate(item.date),
        );
      }).toList(),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined,
                  color: HealingDesignSystem.primaryBlue),
              const SizedBox(width: 8),
              Text('本期睡眠洞察',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Text(lines.join(''), style: const TextStyle(height: 1.55)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title,
      required this.icon,
      required this.child,
      this.initiallyExpanded = false});
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon, color: HealingDesignSystem.primaryBlue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [child],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(
      {required this.label, required this.value, required this.caption});
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700))),
          const SizedBox(height: 3),
          Text(caption,
              style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
        ],
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label：$value'));
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

class _TextRow extends StatelessWidget {
  const _TextRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
                padding: EdgeInsets.only(top: 7),
                child: Icon(Icons.circle, size: 5)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
          ],
        ),
      );
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text,
            style: TextStyle(
                color: HealingDesignSystem.adaptiveSecondaryText(context),
                height: 1.45)),
      );
}

String _duration(num? minutes) =>
    minutes == null ? '資料不足' : DateHelper.formatDurationText(minutes.round());

String _topFlags(List<SleepTrendPoint> points) {
  final counts = <String, int>{};
  for (final flag in points.expand((point) => point.flags)) {
    counts[flag] = (counts[flag] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (entries.isEmpty) return '尚無紀錄';
  return entries
      .take(5)
      .map((entry) =>
          '${_sleepFlagLabels[entry.key] ?? entry.key} ${entry.value} 天')
      .join('、');
}

const _sleepFlagLabels = <String, String>{
  'good': '優',
  'ok': '良好',
  'earlyWake': '早醒',
  'dreams': '多夢',
  'lightSleep': '淺眠',
  'nocturia': '夜尿',
  'fragmented': '睡睡醒醒',
  'insufficient': '睡眠不足',
  'initInsomnia': '入睡困難',
  'interrupted': '睡眠中斷',
};

String _deltaDuration(String label, double? current, double? previous) {
  if (current == null || previous == null) return '$label：資料不足。';
  final delta = current - previous;
  if (delta.abs() < 10) return '$label與上一個區間相近。';
  return '$label較上一個區間${delta > 0 ? '增加' : '減少'} ${_duration(delta.abs())}。';
}

String _qualityDelta(double? current, double? previous) {
  if (current == null || previous == null) return '平均睡眠品質：資料不足。';
  if ((current - previous).abs() < 0.05) return '平均睡眠品質與上一個區間相近。';
  return '平均睡眠品質由 ${previous.toStringAsFixed(1)} '
      '${current > previous ? '上升' : '下降'}至 ${current.toStringAsFixed(1)}。';
}

String _clockDelta(String label, double? current, double? previous) {
  if (current == null || previous == null) return '$label：資料不足。';
  var delta = current - previous;
  while (delta > 720) {
    delta -= 1440;
  }
  while (delta < -720) {
    delta += 1440;
  }
  if (delta.abs() < 10) return '$label與上一個區間相近。';
  return '$label較上一個區間${delta > 0 ? '晚' : '早'} ${_duration(delta.abs())}。';
}

String _dateRange(DateTime start, DateTime end) =>
    '${start.year}/${start.month}/${start.day}～'
    '${end.year}/${end.month}/${end.day}';
