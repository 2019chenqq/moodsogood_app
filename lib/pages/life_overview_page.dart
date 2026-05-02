import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../daily/daily_record_screen.dart';
import '../daily/record_detail_screen.dart';
import '../diary/diary_page_demo.dart';
import '../models/calendar_day_summary.dart';
import '../services/ai_feedback_service.dart';
import '../services/calendar_summary_service.dart';
import '../widgets/unified_calendar_widget.dart';

class LifeOverviewPage extends StatefulWidget {
  const LifeOverviewPage({super.key});

  @override
  State<LifeOverviewPage> createState() => _LifeOverviewPageState();
}

class _LifeOverviewPageState extends State<LifeOverviewPage> {
  final CalendarSummaryService _summaryService = CalendarSummaryService();
  final AIFeedbackService _aiFeedbackService = AIFeedbackService();

  late DateTime _selectedDate;
  late DateTime _focusedMonth;

  Map<String, CalendarDaySummary> _summaries = <String, CalendarDaySummary>{};
  bool _isLoading = true;
  String? _errorMessage;
  int _loadToken = 0;

  bool _isGeneratingFeedback = false;
  String? _aiErrorMessage;

  UnifiedCalendarMode _mode = UnifiedCalendarMode.overview;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _focusedMonth = DateTime(now.year, now.month, 1);
    _loadMonthSummary(_focusedMonth, showLoading: true);
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(fn);
    });
  }

  bool _hasMeaningfulDiaryInput(CalendarDaySummary summary) {
    final title = (summary.diaryTitle ?? '').trim();
    final content = (summary.diaryContent ?? '').trim();
    final digest = (summary.diarySummary ?? '').trim();
    return title.isNotEmpty || content.isNotEmpty || digest.isNotEmpty;
  }

  Future<void> _loadMonthSummary(
    DateTime month, {
    bool showLoading = true,
  }) async {
    final token = ++_loadToken;

    if (showLoading) {
      _safeSetState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _summaryService.loadMonthSummary(visibleMonth: month);
      if (!mounted || token != _loadToken) return;

      _safeSetState(() {
        _summaries = data;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      _safeSetState(() {
        _isLoading = false;
        _errorMessage = '資料載入失敗，請稍後再試';
      });
      debugPrint('[LifeOverviewPage] load failed: $e');
    }
  }

  Future<void> _generateIntegratedFeedback(CalendarDaySummary summary) async {
    if (_isGeneratingFeedback) return;

    if (!_hasMeaningfulDiaryInput(summary)) {
      _safeSetState(() {
        _aiErrorMessage = '請先填寫日記內容，再產生溫柔回饋。';
      });
      return;
    }

    _safeSetState(() {
      _isGeneratingFeedback = true;
      _aiErrorMessage = null;
    });

    try {
      final feedback = await _aiFeedbackService.generateDiaryFeedback(
        mode: AIFeedbackMode.dailyIntegrated,
        daySummary: summary,
      );

      final key = summary.dateKey;
      final current = _summaries[key] ?? summary;

      _safeSetState(() {
        _summaries[key] = current.copyWith(aiFeedback: feedback);
        _isGeneratingFeedback = false;
      });
    } catch (e) {
      _safeSetState(() {
        _isGeneratingFeedback = false;
        _aiErrorMessage = '暫時無法產生溫柔回饋，請稍後再試。';
      });
      debugPrint('[LifeOverviewPage] AI feedback error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final selectedKey = _dateKey(_selectedDate);
    final summary = _summaries[selectedKey] ?? CalendarDaySummary.empty(_selectedDate);
    final canGenerateAiFeedback = _hasMeaningfulDiaryInput(summary);

    return Scaffold(
      appBar: AppBar(
        title: const Text('生活總覽'),
      ),
      backgroundColor: const Color(0xFFF6FBFC),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            _buildModeTabs(),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD8EAED)),
              ),
              child: Text(
                '在這裡，你可以用日期回顧日記、情緒、症狀、睡眠與生理週期，看看不同狀態是否在同一天或同一段時間出現。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E8189),
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            const SizedBox(height: 14),
            if (user == null)
              const _AuthEmptyCard()
            else if (_isLoading)
              const _CalendarLoadingCard()
            else if (_errorMessage != null)
              _CalendarErrorCard(
                message: _errorMessage!,
                onRetry: () => _loadMonthSummary(_focusedMonth, showLoading: true),
              )
            else
              UnifiedCalendarWidget(
                selectedDate: _selectedDate,
                focusedMonth: _focusedMonth,
                mode: _mode,
                summariesByDate: _summaries,
                showInternalPeriodLegend: false,
                onMonthChanged: (month) {
                  final normalized = DateTime(month.year, month.month, 1);
                  if (_isSameMonth(normalized, _focusedMonth)) return;

                  _safeSetState(() {
                    _focusedMonth = normalized;
                  });
                  _loadMonthSummary(normalized, showLoading: true);
                },
                onDateSelected: (date) {
                  final normalized = DateTime(date.year, date.month, date.day);
                  _safeSetState(() {
                    _selectedDate = normalized;
                    _aiErrorMessage = null;
                  });
                },
              ),
            if (user != null && !_isLoading && _errorMessage == null) ...[
              const SizedBox(height: 10),
              const _LifeOverviewLegend(),
            ],
            const SizedBox(height: 16),
            _DailyMindBodySummaryCard(
              summary: summary,
              mode: _mode,
              canGenerateFeedback: canGenerateAiFeedback,
              isGeneratingFeedback: _isGeneratingFeedback,
              aiErrorMessage: _aiErrorMessage,
              onGenerateFeedback: () => _generateIntegratedFeedback(summary),
              onOpenDailyRecord: () => _openDailyRecordPage(summary),
              onOpenDiary: _openDiaryPage,
              onOpenPeriodPage: _openPeriodPage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9EAEE)),
      ),
      padding: const EdgeInsets.all(6),
      child: SegmentedButton<UnifiedCalendarMode>(
        showSelectedIcon: false,
        emptySelectionAllowed: false,
        multiSelectionEnabled: false,
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF7AB7C2).withValues(alpha: 0.2);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF2A6774);
            }
            return const Color(0xFF7F9AA0);
          }),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
          visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: const [
          ButtonSegment(value: UnifiedCalendarMode.overview, label: Text('總覽')),
          ButtonSegment(value: UnifiedCalendarMode.record, label: Text('紀錄')),
        ],
        selected: {_mode},
        onSelectionChanged: (selection) {
          final next = selection.first;
          if (next == UnifiedCalendarMode.diary || next == UnifiedCalendarMode.period) return;
          if (next != _mode) {
            _safeSetState(() => _mode = next);
          }
        },
      ),
    );
  }

  Future<void> _openDailyRecordPage(CalendarDaySummary summary) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docId = (summary.dailyRecordDocId ?? '').trim();

    if (summary.hasDailyRecord && uid != null && docId.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordDetailScreen(
            uid: uid,
            docId: docId,
            autoOpenEditor: false,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DailyRecordScreen()),
    );
  }

  Future<void> _openDiaryPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DiaryPageDemo(date: _selectedDate)),
    );
  }

  Future<void> _openPeriodPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DailyRecordScreen(initialTab: 1)),
    );
  }
}

class _AuthEmptyCard extends StatelessWidget {
  const _AuthEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 356,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDEFF1)),
      ),
      padding: const EdgeInsets.all(18),
      child: Center(
        child: Text(
          '目前尚未登入，請先登入後查看生活總覽。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B8D94),
                fontWeight: FontWeight.w600,
              ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _CalendarLoadingCard extends StatelessWidget {
  const _CalendarLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 356,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDEFF1)),
      ),
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: Color(0xFF63AAB6),
          ),
        ),
      ),
    );
  }
}

class _CalendarErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CalendarErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 356,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDEFF1)),
      ),
      padding: const EdgeInsets.all(18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Color(0xFF82A8AF), size: 26),
            const SizedBox(height: 10),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5A7B82),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                foregroundColor: const Color(0xFF2A6774),
              ),
              child: const Text('重新載入'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LifeOverviewLegend extends StatelessWidget {
  const _LifeOverviewLegend();

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF6F8F95),
          fontWeight: FontWeight.w600,
        );

    Widget item(Widget marker, String text) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          marker,
          const SizedBox(width: 4),
          Text(text, style: labelStyle),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        item(const Text('●', style: TextStyle(color: Color(0xFFF2A8C3), fontSize: 12)), '生理期'),
        item(const Text('○', style: TextStyle(color: Color(0xFFE6A6C0), fontSize: 12)), '預測生理期'),
        item(const _LegendDot(color: Color(0xFF4A90E2)), '每日紀錄'),
        item(const _LegendDot(color: Color(0xFFC9B6FF)), '日記'),
        item(const _LegendDot(color: Color(0xFF58B8C0)), '情緒'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _DailyMindBodySummaryCard extends StatelessWidget {
  final CalendarDaySummary summary;
  final UnifiedCalendarMode mode;
  final bool canGenerateFeedback;
  final bool isGeneratingFeedback;
  final String? aiErrorMessage;
  final VoidCallback onGenerateFeedback;
  final VoidCallback onOpenDailyRecord;
  final VoidCallback onOpenDiary;
  final VoidCallback onOpenPeriodPage;

  const _DailyMindBodySummaryCard({
    required this.summary,
    required this.mode,
    required this.canGenerateFeedback,
    required this.isGeneratingFeedback,
    required this.aiErrorMessage,
    required this.onGenerateFeedback,
    required this.onOpenDailyRecord,
    required this.onOpenDiary,
    required this.onOpenPeriodPage,
  });

  @override
  Widget build(BuildContext context) {
    final isEmptyDay = !_hasAnyData(summary);
    final emotions = summary.emotionNames.take(3).toList();
    final symptoms = summary.symptomNames.take(3).toList();
    final observations = _buildObservations(summary);

    String sleepText;
    if (summary.sleepHours == null &&
        (summary.sleepQuality == null || summary.sleepQuality!.isEmpty)) {
      sleepText = '睡眠：尚無資料';
    } else {
      final parts = <String>[];
      if (summary.sleepHours != null) {
        parts.add('${summary.sleepHours!.toStringAsFixed(1)} 小時');
      }
      if (summary.sleepQuality != null && summary.sleepQuality!.isNotEmpty) {
        parts.add('品質：${summary.sleepQuality}');
      }
      sleepText = '睡眠：${parts.join('，')}';
    }

    final periodText = summary.isPeriodDay
        ? '生理週期：生理期'
        : summary.isPredictedPeriodDay
            ? '生理週期：預測生理期'
            : '生理週期：尚無標記';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCEEF1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '日期：${summary.date.year}/${summary.date.month.toString().padLeft(2, '0')}/${summary.date.day.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF7D969C),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            mode == UnifiedCalendarMode.record ? '當日紀錄回顧' : '當日身心狀態回顧',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF2C6774),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(label: '每日紀錄', active: summary.hasDailyRecord, activeColor: const Color(0xFF4A90E2)),
              _StatusChip(label: '日記', active: summary.hasDiary, activeColor: const Color(0xFFC9B6FF)),
              _StatusChip(label: '情緒', active: summary.hasEmotionData, activeColor: const Color(0xFF58B8C0)),
              _StatusChip(label: '症狀', active: summary.hasSymptomData, activeColor: const Color(0xFFF4B183)),
              _StatusChip(label: '睡眠', active: summary.hasSleepData, activeColor: const Color(0xFF9AB3F5)),
              _StatusChip(label: '生理期', active: summary.isPeriodDay, activeColor: const Color(0xFFFFBFD4)),
              _StatusChip(
                label: '預測生理期',
                active: summary.isPredictedPeriodDay,
                activeColor: const Color(0xFFFFDDEA),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionLine(
            label: '平均心情',
            value: summary.averageMood != null
                ? '${summary.averageMood!.toStringAsFixed(1)} / 10'
                : '尚無資料',
          ),
          const SizedBox(height: 8),
          _SectionLine(
            label: '主要情緒',
            value: emotions.isNotEmpty ? emotions.join('、') : '尚無資料',
          ),
          const SizedBox(height: 8),
          _SectionLine(
            label: '主要症狀',
            value: symptoms.isNotEmpty ? symptoms.join('、') : '尚無資料',
          ),
          const SizedBox(height: 8),
          Text(
            sleepText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF4D7880),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            periodText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF4D7880),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 14),
          Text(
            '日記狀態',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF2F6975),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          if (summary.hasDiary) ...[
            Text(
              '這一天有留下日記',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4D7880),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '日記內容已加密，請進入日記頁查看。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E7F86),
                    height: 1.45,
                  ),
            ),
          ] else
            Text(
              '這一天尚未留下日記。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6F8F95),
                  ),
            ),
          const SizedBox(height: 14),
          Text(
            '系統觀察',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF2F6975),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          ...observations.map(
            (insight) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: _LegendDot(color: Color(0xFF7BBAC4)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      insight,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF5E7F86),
                            height: 1.45,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '溫柔回饋',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF2F6975),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (isGeneratingFeedback)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else
            FilledButton.tonal(
              onPressed: canGenerateFeedback ? onGenerateFeedback : null,
              child: Text(canGenerateFeedback ? '產生溫柔回饋' : '請先填寫日記內容'),
            ),
          if (aiErrorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              aiErrorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6F8F95),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          if (summary.aiFeedback != null && summary.aiFeedback!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD8EAED)),
              ),
              child: Text(
                summary.aiFeedback!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF567C83),
                      height: 1.45,
                    ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            isEmptyDay ? '這一天還沒有留下紀錄' : '這一天已留下部分身心狀態，可以作為回顧參考。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6F8F95),
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onOpenDailyRecord,
                child: Text(summary.hasDailyRecord ? '查看每日紀錄' : '新增每日紀錄'),
              ),
              OutlinedButton(
                onPressed: onOpenDiary,
                child: Text(summary.hasDiary ? '查看日記' : '補寫日記'),
              ),
              OutlinedButton(
                onPressed: onOpenPeriodPage,
                child: const Text('查看生理期'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _buildObservations(CalendarDaySummary s) {
    final observations = <String>[];

    final mood = s.averageMood;
    if (mood != null) {
      if (mood <= 4) {
        observations.add('今天整體情緒偏低，可以回顧是否有壓力事件或耗能情境影響到你。');
      } else if (mood < 7) {
        observations.add('今天整體情緒落在中等區間，建議一起觀察睡眠與症狀是否有連動。');
      } else {
        observations.add('今天整體情緒表現不錯，這是你照顧自己的一個正向訊號。');
      }
    }

    if (s.hasSymptomData) {
      observations.add('今天有身體症狀紀錄，可以留意症狀出現時段與情緒變化是否重疊。');
    }

    if (s.hasSleepData) {
      observations.add('今天有睡眠資料，建議對照睡眠品質與白天情緒起伏。');
    }

    if (s.isPeriodDay) {
      observations.add('今天位於生理期中，身心感受可能受到週期影響，請先溫柔看待自己。');
    }

    if (s.isPredictedPeriodDay) {
      observations.add('目前接近預測生理期，這段時間可多觀察情緒與身體訊號的變化。');
    }

    if (s.hasDiary) {
      observations.add('這一天有日記紀錄，建議回到日記內容理解當天情緒脈絡。');
    }

    if (observations.isEmpty) {
      observations.add('今天資料還不多，先維持簡單記錄也很好，之後會更容易看見自己的節奏。');
    }

    return observations.take(3).toList();
  }
}

class _SectionLine extends StatelessWidget {
  final String label;
  final String value;

  const _SectionLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label：$value',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF4D7880),
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;

  const _StatusChip({
    required this.label,
    required this.active,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.22) : const Color(0xFFF4F8F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? activeColor.withValues(alpha: 0.55) : const Color(0xFFDDE8EA),
        ),
      ),
      child: Text(
        active ? '$label：有' : '$label：無',
        style: TextStyle(
          color: active ? const Color(0xFF35545B) : const Color(0xFF839CA2),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

String _dateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

bool _isSameMonth(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month;
}

bool _hasAnyData(CalendarDaySummary s) {
  return s.hasDailyRecord ||
      s.hasDiary ||
      s.hasEmotionData ||
      s.hasSymptomData ||
      s.hasSleepData ||
      s.isPeriodDay ||
      s.isPredictedPeriodDay ||
      s.averageMood != null;
}
