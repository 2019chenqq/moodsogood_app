import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../models/daily_record.dart';
import '../widgets/trend_range_selector.dart';
import 'body_measurement_input.dart';
import 'unified_body_measurement_repository.dart';

enum _BodyMetric {
  weight('體重', 'kg', Icons.monitor_weight_outlined),
  bodyFat('體脂率', '%', Icons.percent_rounded),
  waist('腰圍', 'cm', Icons.straighten_rounded);

  const _BodyMetric(this.label, this.unit, this.icon);

  final String label;
  final String unit;
  final IconData icon;
}

class BodyMeasurementTrendPage extends StatefulWidget {
  const BodyMeasurementTrendPage({super.key});

  @override
  State<BodyMeasurementTrendPage> createState() =>
      _BodyMeasurementTrendPageState();
}

class _BodyMeasurementTrendPageState extends State<BodyMeasurementTrendPage> {
  int? _selectedDays = 30;
  _BodyMetric _selectedMetric = _BodyMetric.weight;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('未登入')));
    }

    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        title: const Text('身體測量趨勢'),
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: FutureBuilder<_BodyTrendResult>(
        future: _load(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('發生錯誤：${snapshot.error}'));
          }

          final result = snapshot.data ?? _BodyTrendResult.empty();
          final chartMetric = result.availableMetrics.contains(_selectedMetric)
              ? _selectedMetric
              : result.firstAvailableMetric ?? _selectedMetric;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _Card(
                child: TrendRangeSelector(
                  selectedDays: _selectedDays,
                  onChanged: (value) => setState(() => _selectedDays = value),
                ),
              ),
              const SizedBox(height: 12),
              _SummaryHeader(result: result, selectedDays: _selectedDays),
              const SizedBox(height: 12),
              _MetricSelector(
                selected: chartMetric,
                available: result.availableMetrics,
                onChanged: (metric) => setState(() => _selectedMetric = metric),
              ),
              const SizedBox(height: 12),
              _Card(
                child: SizedBox(
                  height: 260,
                  child: _BodyTrendChart(
                    metric: chartMetric,
                    points: result.series[chartMetric] ?? const [],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 1,
                childAspectRatio: 3.1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                children: [
                  for (final metric in _BodyMetric.values)
                    _MetricSummaryTile(
                      metric: metric,
                      summary: result.summaries[metric],
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<_BodyTrendResult> _load(String uid) async {
    final today = _day(DateTime.now());
    final start = _selectedDays == null
        ? DateTime(2020)
        : today.subtract(Duration(days: _selectedDays! - 1));
    final records = await UnifiedBodyMeasurementRepository().getByDateRange(
      userId: uid,
      start: start,
      end: today,
    );
    return _BodyTrendResult.fromRecords(records);
  }
}

class _BodyTrendResult {
  const _BodyTrendResult({
    required this.dailyRecords,
    required this.series,
    required this.summaries,
  });

  final List<UnifiedBodyMeasurement> dailyRecords;
  final Map<_BodyMetric, List<_MetricPoint>> series;
  final Map<_BodyMetric, _MetricSummary> summaries;

  factory _BodyTrendResult.empty() => const _BodyTrendResult(
        dailyRecords: [],
        series: {},
        summaries: {},
      );

  factory _BodyTrendResult.fromRecords(List<UnifiedBodyMeasurement> records) {
    final daily = UnifiedBodyMeasurementRepository.selectDailyTrend(records);
    final series = <_BodyMetric, List<_MetricPoint>>{};
    final summaries = <_BodyMetric, _MetricSummary>{};

    for (final metric in _BodyMetric.values) {
      final points = <_MetricPoint>[];
      for (final item in daily) {
        final value = _valueOf(item.measurement, metric);
        if (value != null) {
          points.add(_MetricPoint(date: _day(item.date), value: value));
        }
      }
      series[metric] = points;
      summaries[metric] = _MetricSummary.fromPoints(points);
    }

    return _BodyTrendResult(
      dailyRecords: daily,
      series: series,
      summaries: summaries,
    );
  }

  Set<_BodyMetric> get availableMetrics => {
        for (final entry in series.entries)
          if (entry.value.isNotEmpty) entry.key,
      };

  _BodyMetric? get firstAvailableMetric =>
      availableMetrics.isEmpty ? null : availableMetrics.first;
}

class _MetricPoint {
  const _MetricPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

class _MetricSummary {
  const _MetricSummary({
    required this.count,
    this.first,
    this.latest,
    this.average,
    this.delta,
    this.firstDate,
    this.latestDate,
  });

  final int count;
  final double? first;
  final double? latest;
  final double? average;
  final double? delta;
  final DateTime? firstDate;
  final DateTime? latestDate;

  factory _MetricSummary.fromPoints(List<_MetricPoint> points) {
    if (points.isEmpty) return const _MetricSummary(count: 0);
    final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));
    final first = sorted.first;
    final latest = sorted.last;
    final total = sorted.fold<double>(0, (sum, point) => sum + point.value);
    return _MetricSummary(
      count: sorted.length,
      first: first.value,
      latest: latest.value,
      average: total / sorted.length,
      delta: latest.value - first.value,
      firstDate: first.date,
      latestDate: latest.date,
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.result, required this.selectedDays});

  final _BodyTrendResult result;
  final int? selectedDays;

  @override
  Widget build(BuildContext context) {
    final totalDays = selectedDays == null ? '全部' : '$selectedDays 天';
    final sourceDays = result.dailyRecords.length;
    return _Card(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: HealingDesignSystem.primaryBlue.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.monitor_weight_outlined,
              color: HealingDesignSystem.primaryBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '身體測量趨勢',
                  style: HealingDesignSystem.titleMedium.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                Text(
                  '目前區間：$totalDays，$sourceDays 天有身體測量資料',
                  style: HealingDesignSystem.bodySmall.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSelector extends StatelessWidget {
  const _MetricSelector({
    required this.selected,
    required this.available,
    required this.onChanged,
  });

  final _BodyMetric selected;
  final Set<_BodyMetric> available;
  final ValueChanged<_BodyMetric> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final metric in _BodyMetric.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  metric.icon,
                  size: 18,
                  color: selected == metric
                      ? Colors.white
                      : HealingDesignSystem.primaryBlue,
                ),
                label: Text(metric.label),
                selected: selected == metric,
                onSelected: available.contains(metric)
                    ? (_) => onChanged(metric)
                    : null,
                selectedColor: HealingDesignSystem.primaryBlue,
                labelStyle: TextStyle(
                  color: selected == metric
                      ? Colors.white
                      : HealingDesignSystem.adaptivePrimaryText(context),
                  fontWeight:
                      selected == metric ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BodyTrendChart extends StatelessWidget {
  const _BodyTrendChart({required this.metric, required this.points});

  final _BodyMetric metric;
  final List<_MetricPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text(
          '這個區間還沒有${metric.label}資料',
          style: HealingDesignSystem.bodyMedium.copyWith(
            color: HealingDesignSystem.adaptiveSecondaryText(context),
          ),
        ),
      );
    }

    final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));
    final start = sorted.first.date;
    final spots = [
      for (final point in sorted)
        FlSpot(point.date.difference(start).inDays.toDouble(), point.value),
    ];
    final minX = spots.first.x;
    final maxX = max(spots.last.x, minX + 1);
    final minValue = spots.map((spot) => spot.y).reduce(min);
    final maxValue = spots.map((spot) => spot.y).reduce(max);
    final padding = max((maxValue - minValue).abs() * 0.12, 1.0);

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minValue - padding,
        maxY: maxValue + padding,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: HealingDesignSystem.lineColor.withValues(alpha: 0.7),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => Text(
                _compactNumber(value),
                style: HealingDesignSystem.labelSmall.copyWith(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: max(1, ((maxX - minX) / 4).ceilToDouble()),
              getTitlesWidget: (value, meta) {
                final dayOffset = value.round();
                if ((value - dayOffset).abs() > 0.01) {
                  return const SizedBox.shrink();
                }
                final date = start.add(Duration(days: dayOffset));
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${date.month}/${date.day}',
                    style: HealingDesignSystem.labelSmall.copyWith(
                      color: HealingDesignSystem.adaptiveSecondaryText(context),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => [
              for (final spot in touchedSpots)
                LineTooltipItem(
                  '${_dateLabel(start.add(Duration(days: spot.x.round())))}\n'
                  '${formatBodyMeasurementNumber(spot.y)} ${metric.unit}',
                  const TextStyle(color: Colors.white),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: HealingDesignSystem.primaryBlue,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: HealingDesignSystem.primaryBlue.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSummaryTile extends StatelessWidget {
  const _MetricSummaryTile({required this.metric, required this.summary});

  final _BodyMetric metric;
  final _MetricSummary? summary;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    final latest = data?.latest;
    final delta = data?.delta;
    return _Card(
      child: Row(
        children: [
          Icon(metric.icon, color: HealingDesignSystem.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  metric.label,
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                Text(
                  data == null || data.count == 0
                      ? '尚無資料'
                      : '${data.count} 筆有效日資料，平均 ${formatBodyMeasurementNumber(data.average)} ${metric.unit}',
                  style: HealingDesignSystem.bodySmall.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                  ),
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                latest == null
                    ? '-'
                    : '${formatBodyMeasurementNumber(latest)} ${metric.unit}',
                style: HealingDesignSystem.titleSmall.copyWith(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                ),
              ),
              Text(
                delta == null ? '' : _deltaText(delta, metric.unit),
                style: HealingDesignSystem.bodySmall.copyWith(
                  color: delta == null || delta == 0
                      ? HealingDesignSystem.adaptiveSecondaryText(context)
                      : delta > 0
                          ? HealingDesignSystem.warningOrange
                          : HealingDesignSystem.primaryBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
      decoration: HealingDesignSystem.adaptiveCardDecoration(
        context,
        radius: HealingDesignSystem.radiusM,
      ),
      child: child,
    );
  }
}

double? _valueOf(BodyMeasurement measurement, _BodyMetric metric) =>
    switch (metric) {
      _BodyMetric.weight => measurement.weightKg,
      _BodyMetric.bodyFat => measurement.bodyFatPercent,
      _BodyMetric.waist => measurement.waistCm,
    };

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateLabel(DateTime date) => '${date.month}/${date.day}';

String _compactNumber(double value) {
  if (value.abs() >= 100) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _deltaText(double value, String unit) {
  if (value == 0) return '無變化';
  final sign = value > 0 ? '+' : '';
  return '$sign${formatBodyMeasurementNumber(value)} $unit';
}
