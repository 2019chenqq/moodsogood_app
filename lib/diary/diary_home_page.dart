// diary_home_page.dart
import 'dart:convert';
import 'package:flutter/material.dart' as m;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'diary_page_demo.dart';
import '/diary/diary_repository.dart';
import '../utils/date_helper.dart';

// weekday label
const _kWeekLabels = ['日', '一', '二', '三', '四', '五', '六'];

// ──────────────────────────────────────────────
// 天氣資料模型（Open-Meteo，免費、無需 API key）
// ──────────────────────────────────────────────
class _WeatherInfo {
  final double tempC;
  final int code;      // WMO weather code
  final String label;  // 中文天氣描述
  final String emoji;

  const _WeatherInfo({
    required this.tempC,
    required this.code,
    required this.label,
    required this.emoji,
  });
}

String _wmoLabel(int code) {
  if (code == 0) return '晴天';
  if (code <= 2) return '部分多雲';
  if (code == 3) return '多雲';
  if (code <= 49) return '霧';
  if (code <= 57) return '細雨';
  if (code <= 65) return '雨';
  if (code <= 77) return '降雪';
  if (code <= 82) return '陣雨';
  if (code <= 86) return '陣雪';
  return '雷雨';
}

String _wmoEmoji(int code) {
  if (code == 0) return '☀️';
  if (code <= 2) return '⛅';
  if (code == 3) return '☁️';
  if (code <= 49) return '🌫️';
  if (code <= 57) return '🌦️';
  if (code <= 65) return '🌧️';
  if (code <= 77) return '❄️';
  if (code <= 82) return '🌦️';
  if (code <= 86) return '🌨️';
  return '⛈️';
}

/// 取得定位並呼叫 Open-Meteo API，回傳 [_WeatherInfo] 或 null
Future<_WeatherInfo?> _fetchWeather() async {
  try {
    // 1. 確認定位權限
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }

    // 2. 取得座標（低精度即可，節省電量）
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );

    // 3. 呼叫 Open-Meteo（免費、無需 API key）
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=${pos.latitude}&longitude=${pos.longitude}'
      '&current_weather=true&timezone=auto',
    );
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final cw = json['current_weather'] as Map<String, dynamic>;
    final temp = (cw['temperature'] as num).toDouble();
    final code = (cw['weathercode'] as num).toInt();

    return _WeatherInfo(
      tempC: temp,
      code: code,
      label: _wmoLabel(code),
      emoji: _wmoEmoji(code),
    );
  } catch (_) {
    return null;
  }
}

// ──────────────────────────────────────────────
// 輔助：把各種日期字串正規化成 yyyy-MM-dd
// ──────────────────────────────────────────────
String _normDayKey(String raw) {
  if (raw.contains('T')) {
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      return '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }
  }
  final beforeT = raw.split('T').first;
  final digits = beforeT.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 8) {
    return '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}';
  }
  final parts = beforeT.split(RegExp(r'[-/]'));
  if (parts.length >= 3) {
    return '${parts[0].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}';
  }
  return beforeT;
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// ──────────────────────────────────────────────
// Entry-point
// ──────────────────────────────────────────────
class DiaryHomePage extends m.StatefulWidget {
  const DiaryHomePage({m.Key? key}) : super(key: key);

  @override
  m.State<DiaryHomePage> createState() => _DiaryHomePageState();
}

class _DiaryHomePageState extends m.State<DiaryHomePage> {
  String? _uid;
  String _displayName = '';
  bool _loading = true;

  final Set<String> _entryDays = {};
  List<DiaryEntry> _recentEntries = [];
  _WeatherInfo? _weather;
  bool _weatherLoaded = false;

  late DateTime _focusedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid;
    _displayName = user?.displayName ?? '你';
    _loadData();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    final w = await _fetchWeather();
    if (mounted) {
      setState(() {
        _weather = w;
        _weatherLoaded = true;
      });
    }
  }

  Future<void> _loadData() async {
    final days = <String>{};
    List<DiaryEntry> recent = [];

    // 1. 本地 SQLite
    try {
      final entries = await DiaryRepository().list(limit: 5000);
      recent = List.from(entries)
        ..sort((a, b) => b.date.compareTo(a.date));
      for (final e in entries) {
        days.add(_normDayKey(e.date.toIso8601String()));
      }
    } catch (e) {
      m.debugPrint('❌ SQLite load error: $e');
    }

    // 2. Firebase（補充雲端日期，不重複讀內容）
    try {
      final uid = _uid;
      if (uid != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('diary')
            .limit(5000)
            .get();
        for (final doc in snap.docs) {
          days.add(_normDayKey(doc.id));
        }
      }
    } catch (e) {
      m.debugPrint('❌ Firebase load error: $e');
    }

    if (mounted) {
      setState(() {
        _entryDays
          ..clear()
          ..addAll(days);
        _recentEntries = recent.take(10).toList();
        _loading = false;
      });
    }
  }

  void _openDiaryEditor(DateTime d) {
    final clean = DateTime(d.year, d.month, d.day);
    m.Navigator.push(
      context,
      m.MaterialPageRoute(builder: (_) => DiaryPageDemo(date: clean)),
    ).then((_) => _loadData());
  }

  void _openToday() {
    final now = DateTime.now();
    _openDiaryEditor(now);
  }

  int get _streakDays {
    if (_entryDays.isEmpty) return 0;
    var count = 0;
    var cursor = DateTime.now();
    while (_entryDays.contains(_dateKey(cursor))) {
      count += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    if (count > 0) return count;

    cursor = DateTime.now().subtract(const Duration(days: 1));
    while (_entryDays.contains(_dateKey(cursor))) {
      count += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  int get _weeklyPositiveIndex {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final scores = _recentEntries
        .where((e) => e.moodScore != null && e.date.isAfter(weekAgo))
        .map((e) => e.moodScore!)
        .toList();
    if (scores.isEmpty) return 68;

    final avg = scores.reduce((a, b) => a + b) / scores.length;
    final scale = avg <= 5 ? 20.0 : 10.0;
    return (avg * scale).clamp(0, 100).round();
  }

  int get _todayGratitudeCount {
    final todayKey = _dateKey(DateTime.now());
    DiaryEntry? today;
    for (final e in _recentEntries) {
      if (_dateKey(e.date) == todayKey) {
        today = e;
        break;
      }
    }
    if (today == null) return 0;
    final raw = today.selfCare?.trim() ?? '';
    if (raw.isEmpty) return 0;

    return raw
        .split(RegExp(r'[\n,，、;；]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .length;
  }

  // greeting 文字
  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 6) return '深夜好';
    if (h < 12) return '早安';
    if (h < 17) return '午安';
    if (h < 21) return '晚安';
    return '夜深了';
  }

  @override
  m.Widget build(m.BuildContext context) {
    if (_uid == null) {
      return m.Scaffold(
        appBar: m.AppBar(title: const m.Text('日記')),
        body: const m.Center(child: m.Text('請先登入後再查看日記。')),
      );
    }

    final cs = m.Theme.of(context).colorScheme;

    return m.Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: _loading
          ? const m.Center(child: m.CircularProgressIndicator())
          : m.CustomScrollView(
              slivers: [
                // ── SliverAppBar ──
                m.SliverAppBar(
                  pinned: true,
                  elevation: 0,
                  backgroundColor: cs.surface,
                  title: const m.Text('日記'),
                ),

                // ── Hero 卡片（問候 + 天氣）──
                m.SliverToBoxAdapter(
                  child: m.Padding(
                    padding: const m.EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _HeroCard(
                      greeting: _greeting,
                      name: _displayName,
                      weather: _weather,
                      weatherLoaded: _weatherLoaded,
                      totalRecordDays: _entryDays.length,
                      streakDays: _streakDays,
                      weeklyPositiveIndex: _weeklyPositiveIndex,
                      gratitudeCount: _todayGratitudeCount,
                    ),
                  ),
                ),

                // ── 小日曆（全寬）──
                m.SliverToBoxAdapter(
                  child: m.Padding(
                    padding: const m.EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _MiniCalendar(
                      focusedMonth: _focusedMonth,
                      entryDays: _entryDays,
                      onMonthChanged: (month) => setState(() {
                        _focusedMonth = DateTime(month.year, month.month, 1);
                      }),
                      onDayTap: _openDiaryEditor,
                    ),
                  ),
                ),

                const m.SliverToBoxAdapter(child: m.SizedBox(height: 110)),
              ],
            ),
      floatingActionButton: m.FloatingActionButton.extended(
        icon: const m.Icon(m.Icons.edit_calendar),
        label: const m.Text('今天的日記'),
        onPressed: _openToday,
      ),
    );
  }
}
// ──────────────────────────────────────────────
// 小日曆（右側）
// ──────────────────────────────────────────────
// ──────────────────────────────────────────────
// Hero 卡片（問候 + 天氣）
// ──────────────────────────────────────────────
class _HeroCard extends m.StatelessWidget {
  final String greeting;
  final String name;
  final _WeatherInfo? weather;
  final bool weatherLoaded;
  final int totalRecordDays;
  final int streakDays;
  final int weeklyPositiveIndex;
  final int gratitudeCount;

  const _HeroCard({
    required this.greeting,
    required this.name,
    required this.weather,
    required this.weatherLoaded,
    required this.totalRecordDays,
    required this.streakDays,
    required this.weeklyPositiveIndex,
    required this.gratitudeCount,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;
    final isCompact = m.MediaQuery.of(context).size.width < 420;

    return m.Container(
      width: double.infinity,
      padding: const m.EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: m.BoxDecoration(
        gradient: m.LinearGradient(
          colors: const [m.Color(0xFF2581B8), m.Color(0xFF5DAFD2)],
          begin: m.Alignment.topLeft,
          end: m.Alignment.bottomRight,
        ),
        borderRadius: m.BorderRadius.circular(22),
      ),
      child: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          m.Text(
            '今日狀態',
            style: m.TextStyle(
              fontSize: 12,
              fontWeight: m.FontWeight.w700,
              color: m.Colors.white.withOpacity(0.9),
              letterSpacing: 1.2,
            ),
          ),
          const m.SizedBox(height: 12),
          m.Row(
            crossAxisAlignment: m.CrossAxisAlignment.start,
            children: [
              m.Icon(m.Icons.cloud_queue_rounded,
                  color: m.Colors.white, size: 42),
              const m.SizedBox(width: 12),
              m.Expanded(
                child: m.Column(
                  crossAxisAlignment: m.CrossAxisAlignment.start,
                  children: [
                    m.Text(
                      '$name，$greeting',
                      maxLines: 1,
                      overflow: m.TextOverflow.ellipsis,
                      style: m.TextStyle(
                        fontSize: isCompact ? 22 : 28,
                        height: 1.08,
                        fontWeight: m.FontWeight.w800,
                        color: m.Colors.white,
                      ),
                    ),
                    const m.SizedBox(height: 4),
                    if (weather != null)
                      m.Text(
                        '目前${weather!.label} ${weather!.tempC.toStringAsFixed(0)}°C，記得照顧自己。',
                        style: m.TextStyle(
                          fontSize: 13,
                          fontWeight: m.FontWeight.w600,
                          color: m.Colors.white.withOpacity(0.82),
                        ),
                      )
                    else if (!weatherLoaded)
                      m.Text(
                        '正在取得天氣資訊…',
                        style: m.TextStyle(
                          fontSize: 13,
                          fontWeight: m.FontWeight.w600,
                          color: m.Colors.white.withOpacity(0.82),
                        ),
                      )
                    else
                      m.Text(
                        '天氣資料暫時不可用，仍可正常寫日記。',
                        style: m.TextStyle(
                          fontSize: 13,
                          fontWeight: m.FontWeight.w600,
                          color: m.Colors.white.withOpacity(0.82),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const m.SizedBox(height: 16),
          m.LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 560;
              final columns = isNarrow ? 2 : 4;
              final spacing = 10.0;
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * spacing) / columns;

              return m.Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  m.SizedBox(
                    width: cardWidth,
                    child: _StatusMetricCard(
                      value: '$totalRecordDays',
                      label: '總紀錄天數',
                    ),
                  ),
                  m.SizedBox(
                    width: cardWidth,
                    child: _StatusMetricCard(
                      value: '$streakDays',
                      label: '連續記錄天數',
                    ),
                  ),
                  m.SizedBox(
                    width: cardWidth,
                    child: _StatusMetricCard(
                      value: '$weeklyPositiveIndex%',
                      label: '本週正向指數',
                    ),
                  ),
                  m.SizedBox(
                    width: cardWidth,
                    child: _StatusMetricCard(
                      value: '$gratitudeCount',
                      label: '今日感恩事項',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusMetricCard extends m.StatelessWidget {
  final String value;
  final String label;

  const _StatusMetricCard({required this.value, required this.label});

  @override
  m.Widget build(m.BuildContext context) {
    final isCompact = m.MediaQuery.of(context).size.width < 420;
    return m.Container(
      padding: const m.EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: m.BoxDecoration(
        color: m.Colors.white.withOpacity(0.13),
        borderRadius: m.BorderRadius.circular(14),
      ),
      child: m.Column(
        children: [
          m.Text(
            value,
            maxLines: 1,
            overflow: m.TextOverflow.ellipsis,
            style: m.TextStyle(
              fontSize: isCompact ? 20 : 24,
              height: 1,
              color: m.Colors.white,
              fontWeight: m.FontWeight.w800,
            ),
          ),
          const m.SizedBox(height: 5),
          m.Text(
            label,
            maxLines: 1,
            overflow: m.TextOverflow.ellipsis,
            style: m.TextStyle(
              fontSize: isCompact ? 10 : 11,
              color: m.Colors.white.withOpacity(0.82),
              fontWeight: m.FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 小日曆（全寬）
// ──────────────────────────────────────────────
class _MiniCalendar extends m.StatefulWidget {
  final DateTime focusedMonth;
  final Set<String> entryDays;
  final m.ValueChanged<DateTime> onMonthChanged;
  final m.ValueChanged<DateTime> onDayTap;

  const _MiniCalendar({
    required this.focusedMonth,
    required this.entryDays,
    required this.onMonthChanged,
    required this.onDayTap,
  });

  @override
  m.State<_MiniCalendar> createState() => _MiniCalendarState();
}

class _MiniCalendarState extends m.State<_MiniCalendar> {
  static const int _basePage = 1200;
  late final m.PageController _controller;
  DateTime? _anchorMonth;
  int _currentPage = _basePage;

  @override
  void initState() {
    super.initState();
    _anchorMonth = DateTime(widget.focusedMonth.year, widget.focusedMonth.month, 1);
    _controller = m.PageController(initialPage: _basePage);
  }

  @override
  void didUpdateWidget(covariant _MiniCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _anchorMonth ??= DateTime(widget.focusedMonth.year, widget.focusedMonth.month, 1);
  }

  Future<void> _goToPage(int page) async {
    await _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: m.Curves.easeOut,
    );
  }

  DateTime _monthFromPage(int page) {
    final delta = page - _basePage;
    final anchor = _anchorMonth ??
        DateTime(widget.focusedMonth.year, widget.focusedMonth.month, 1);
    return DateTime(
      anchor.year,
      anchor.month + delta,
      1,
    );
  }

  List<DateTime?> _buildMonthCells(DateTime month) {
    final leading = month.weekday % 7;
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    final daysInMonth = nextMonth.subtract(const Duration(days: 1)).day;
    final cells = <DateTime?>[];
    for (var i = 0; i < leading; i++) cells.add(null);
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(month.year, month.month, d));
    }
    return cells;
  }

  @override
  m.Widget build(m.BuildContext context) {
    final theme = m.Theme.of(context);
    final cs = theme.colorScheme;
    final todayKey = _dateKey(DateTime.now());
    final shownMonth = _monthFromPage(_currentPage);

    return m.Container(
      clipBehavior: m.Clip.hardEdge,
      padding: const m.EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: m.BoxDecoration(
        color: cs.surface,
        borderRadius: m.BorderRadius.circular(20),
        boxShadow: [
          m.BoxShadow(
            color: m.Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const m.Offset(0, 4),
          )
        ],
      ),
      child: m.Column(
        mainAxisSize: m.MainAxisSize.min,
        children: [
          m.Row(
            mainAxisAlignment: m.MainAxisAlignment.spaceBetween,
            children: [
              m.IconButton(
                onPressed: () => _goToPage(_currentPage - 1),
                icon: const m.Icon(m.Icons.chevron_left),
                visualDensity: m.VisualDensity.compact,
                splashRadius: 20,
              ),
              m.Text(
                '${shownMonth.year}年 ${shownMonth.month}月',
                style: m.TextStyle(
                  fontSize: 15,
                  fontWeight: m.FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              m.IconButton(
                onPressed: () => _goToPage(_currentPage + 1),
                icon: const m.Icon(m.Icons.chevron_right),
                visualDensity: m.VisualDensity.compact,
                splashRadius: 20,
              ),
            ],
          ),
          const m.SizedBox(height: 6),
          m.SizedBox(
            height: 308,
            child: m.PageView.builder(
              controller: _controller,
              onPageChanged: (page) {
                setState(() => _currentPage = page);
                widget.onMonthChanged(_monthFromPage(page));
              },
              itemBuilder: (context, page) {
                final month = _monthFromPage(page);
                final cells = _buildMonthCells(month);
                return m.Column(
                  children: [
                    m.Row(
                      children: _kWeekLabels
                          .map(
                            (l) => m.Expanded(
                              child: m.Center(
                                child: m.Text(
                                  l,
                                  style: m.TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurface.withOpacity(0.4),
                                    fontWeight: m.FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const m.SizedBox(height: 4),
                    m.GridView.builder(
                      padding: m.EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const m.NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const m.SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 3,
                        childAspectRatio: 1,
                      ),
                      itemCount: cells.length,
                      itemBuilder: (ctx, i) {
                        final date = cells[i];
                        if (date == null) return const m.SizedBox.shrink();
                        final key = _dateKey(date);
                        final hasEntry = widget.entryDays.contains(key);
                        final isToday = key == todayKey;
                        return _MiniDayCell(
                          date: date,
                          hasEntry: hasEntry,
                          isToday: isToday,
                          onTap: () => widget.onDayTap(date),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniDayCell extends m.StatelessWidget {
  final DateTime date;
  final bool hasEntry;
  final bool isToday;
  final m.VoidCallback onTap;

  const _MiniDayCell({
    required this.date,
    required this.hasEntry,
    required this.isToday,
    required this.onTap,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;

    m.Color? bg;
    m.Color fg = cs.onSurface;
    m.Border? border;

    if (hasEntry) {
      bg = cs.primary;
      fg = cs.onPrimary;
    } else if (isToday) {
      border = m.Border.all(color: cs.primary, width: 1.5);
      fg = cs.primary;
    }

    return m.GestureDetector(
      onTap: onTap,
      child: m.Container(
        margin: const m.EdgeInsets.all(1),
        decoration: m.BoxDecoration(
          color: bg,
          shape: m.BoxShape.circle,
          border: border,
        ),
        alignment: m.Alignment.center,
        child: m.Text(
          '${date.day}',
          style: m.TextStyle(
            fontSize: 12,
            fontWeight:
                (hasEntry || isToday) ? m.FontWeight.w700 : m.FontWeight.w400,
            color: fg,
          ),
        ),
      ),
    );
  }
}

