// lib/diary/diary_page.dart
import 'package:flutter/material.dart' as m;
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../diary/diary_repository.dart' as repo; // 資料層用別名避免撞名
import '../daily/edit_record_page.dart';
import 'diary_history_page.dart';

class Foo extends m.StatelessWidget {
  @override
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;
    return m.Card(
      color: cs.surface,
      shape: m.RoundedRectangleBorder(
        borderRadius: m.BorderRadius.circular(16),
      ),
      child: m.Padding(
        padding: const m.EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: m.Text('Hello', style: m.Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

// ===== 傳入的摘要（從每日紀錄而來） =====
class DailyMeta {
  final DateTime date;
  final double moodScore;
  final String? moodKeyword;
  const DailyMeta({required this.date, required this.moodScore, this.moodKeyword});
}

// ===== 寫日記 / 編輯日記（單檔版）=====
class DiaryPage extends m.StatefulWidget {
  final DailyMeta meta;
  final repo.DiaryEntry? initial;    // 有值＝編輯；null＝新增
  final m.ValueChanged<repo.DiaryEntry>? onChanged;
  final m.VoidCallback? onSave;

  const DiaryPage({
    m.Key? key,
    required this.meta,
    this.initial,
    this.onChanged,
    this.onSave,
  }) : super(key: key);

  @override
  m.State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends m.State<DiaryPage> {
  late DailyMeta _meta; // ★ 新增

  Future<void> openDailyRecordEditor(DateTime date) async {
  final d = DateTime(date.year, date.month, date.day); // 只留年月日

  // ① 取 uid
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    if (!mounted) return;
    m.ScaffoldMessenger.of(context).showSnackBar(const m.SnackBar(content: Text('請先登入')));
    return;
    await _refreshMoodFromDaily(d);
  }
  final uid = user.uid;

  // ② 產生當日 docId（yyyymmdd）
  final docId =
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  await Navigator.of(context).push(
    m.MaterialPageRoute(
      builder: (_) => EditRecordPage(
        uid: uid,          // ★ 必填
        docId: docId,      // ★ 必填
        // 你原本就有的參數，保留即可
        initData: {'date': d}, // 若你的頁面不需要 initData，可以刪掉這行
        // 若頁面有 date/targetDate/initialDate 其一，改用對應名稱傳 d
      ),
    ),
  );
}
Future<void> _refreshMoodFromDaily(DateTime date) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final docId = _idForDate(date); // 下面第 3 段的工具函式
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('daily')          // ← ★ 你的每日紀錄集合名稱
      .doc(docId)
      .get();

  if (!snap.exists) return;
  final data = snap.data()!;
  final double? score   = (data['moodScore'] as num?)?.toDouble();
  final String? keyword = data['moodKeyword'] as String?;

  if (score != null) {
    setState(() {
      // 如果 DailyMeta 有 copyWith 用這個：
      // _meta = _meta.copyWith(moodScore: score, moodKeyword: keyword);

      // 若沒有 copyWith，就這樣重建：
      _meta = DailyMeta(
        date: _meta.date,
        moodScore: score,
        moodKeyword: keyword ?? _meta.moodKeyword,
      );
    });
  }
  if (!mounted) return;

}
  // ---- Controllers ----
  final _song = m.TextEditingController();
  final _highlight = m.TextEditingController();
  final _metaphor = m.TextEditingController();
  final _proud = m.TextEditingController();
  final _selfCare = m.TextEditingController();
  final _titleCtrl = m.TextEditingController();
  final _contentCtrl = m.TextEditingController();
  final _conceited = m.TextEditingController();

  Timer? _debounce;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      final e = widget.initial!; // repo.DiaryEntry
      _titleCtrl.text = e.title;
      _contentCtrl.text = e.content;
      _song.text      = e.themeSong ?? '';
      _highlight.text = e.highlight ?? '';
      _metaphor.text  = e.metaphor ?? '';
      _proud.text     = e.proudOf ?? '';
      _selfCare.text  = e.selfCare ?? '';
    }
    _attachListeners();
  }

  void _attachListeners() {
    for (final c in [_song, _highlight, _metaphor, _proud, _selfCare]) {
      c.addListener(_onChangedDebounced);
    }
  }

  void _onChangedDebounced() {
    if (widget.onChanged == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      widget.onChanged!.call(_gather());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_song, _highlight, _metaphor, _proud, _conceited,_selfCare, _titleCtrl, _contentCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- UI ----
  @override
  m.Widget build(m.BuildContext context) {
    final meta = widget.meta;
    final dateStr = meta.date.toIso8601String().split('T').first;

    return m.Scaffold(
      appBar: m.AppBar(
        title: m.Text(widget.initial == null ? '心晴日記' : '編輯日記'),
        actions: [
          m.IconButton(
            tooltip: '儲存',
            icon: const m.Icon(m.Icons.save_rounded),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: m.SafeArea(
        child: m.ListView(
          padding: const m.EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _HeaderCard(
  date: meta.date,
  dateText: dateStr,
  moodScore: meta.moodScore,
  moodKeyword: meta.moodKeyword,
  color: m.Theme.of(context).colorScheme.primaryContainer,
  onPeek: () => _showQuickPeek(context, meta),
  // onOpenDailyRecord: null, // 不寫就等於關閉
),
            const m.SizedBox(height: 12),

            _InputCard(
              label: '標題（可留白）',
              hintText: '幫今天下一個小標題，也可以跳過…',
              controller: _titleCtrl, // 你原本的 controller
              maxLines: 3,
            ),
            const m.SizedBox(height: 12),

            _InputCard(
  label: '內容',
  hintText: '留下一點點也很好…',
  controller: _contentCtrl, // 你原本的 controller
  minLines: 3,
  maxLines: 20,
),
const m.SizedBox(height: 12),

            const m.SizedBox(height: 12),
            // 🎵 主題曲
            _InputCard(
  label: '🎧 今日的主題曲',
  hintText: '歌名／連結／演出者…',
  controller: _song, // 你原本的 controller
  minLines: 3,
  maxLines: 20,
),
const m.SizedBox(height: 12),
            
            // ✨ 今天最想記錄的瞬間
              _InputCard(
  label: '✨ 今天最想記錄的瞬間',
  hintText: '寫下今天讓你有感的一幕、對話或感受…',
  controller:_highlight, // 你原本的 controller
  minLines: 3,
  maxLines: 20,
),
const m.SizedBox(height: 12),
            // 🎭 今天的情緒像…
            _InputCard(
  label: '🎭 今天的情緒像…',
  hintText: '例：潮汐、霧氣、烈陽、颳風…',
  controller: _metaphor, // 你原本的 controller
  minLines: 3,
  maxLines: 20,
),
            const m.SizedBox(height: 12),

            // 🏅 為自己感到驕傲的是
             _InputCard(
  label: '🏅 為自己感到驕傲的是',
  hintText: '完成了什麼、撐住了什麼、或小小突破…',
  controller: _conceited, // 你原本的 controller
  minLines: 3,
  maxLines: 20,
),
            const m.SizedBox(height: 12),

            _InputCard(
  label: '🌤️ 我做得不錯的地方',
  hintText: '肯定一下今天的自己，那怕是很小的事情…',
  controller: _proud, // 你原本的 controller
  minLines: 3,
  maxLines: 20,
),
            const m.SizedBox(height: 12),

            // 🫶 自我照顧
             _InputCard(
  label: '🫶 我還能多照顧自己一點的地方',
  hintText: '下一步可以怎麼做？睡眠、飲食、人際邊界、運動或求助…',
  controller: _selfCare, // 你原本的 controller
  minLines: 3,
  maxLines: 20,
),

            const m.SizedBox(height: 20),
            m.Row(
              children: [
                m.Icon(m.Icons.info_outline, size: 16, color: _moodColor(widget.meta.moodScore, context)),
                const m.SizedBox(width: 6),
                m.Expanded(
                  child: m.Text(
                    '小提醒：內容儲存後仍可在日記回顧中編輯。',
                    style: m.Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  // ========== 動作區 ==========
  // 以 yyyymmdd 當 docId（避免一天重複新增）
  String _idForDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}';

Future<void> _save() async {
  if (_saving) return;
  setState(() => _saving = true);
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      m.ScaffoldMessenger.of(context)
          .showSnackBar(const m.SnackBar(content: Text('請先登入')));
      return;
    }

    final meta = widget.meta;
    final dateOnly = DateTime(meta.date.year, meta.date.month, meta.date.day);
    String _idForDate(DateTime dt) =>
        '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';
    final docId = _idForDate(dateOnly);

    final payload = <String, dynamic>{
      'date': Timestamp.fromDate(dateOnly),
      'title': _titleCtrl.text.trim(),
      'content': _contentCtrl.text.trim(),
      'moodScore': meta.moodScore,
      'moodKeyword': meta.moodKeyword,
      'themeSong': _song.text.trim().isEmpty ? null : _song.text.trim(),
      'highlight': _highlight.text.trim().isEmpty ? null : _highlight.text.trim(),
      'metaphor': _metaphor.text.trim().isEmpty ? null : _metaphor.text.trim(),
      'proudOf': _proud.text.trim().isEmpty ? null : _proud.text.trim(),
      'selfCare': _selfCare.text.trim().isEmpty ? null : _selfCare.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    final ref = FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('diary').doc(docId);

    await ref.set(payload, SetOptions(merge: true));

    // 🔎 重要：印出實際寫到哪裡
    // ignore: avoid_print
    print('[SAVE] path=${ref.path}  uid=${user.uid}  docId=$docId');

    if (!mounted) return;
    m.ScaffoldMessenger.of(context)
        .showSnackBar(const m.SnackBar(content: Text('已儲存日記。')));
    Navigator.of(context).maybePop(true);
  } catch (e) {
    if (!mounted) return;
    m.ScaffoldMessenger.of(context)
        .showSnackBar(m.SnackBar(content: Text('儲存失敗：$e')));
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}

  void _showQuickPeek(m.BuildContext context, DailyMeta meta) {
  m.showModalBottomSheet(
    context: context,
    showDragHandle: true,
    backgroundColor: m.Theme.of(context).colorScheme.surface,
    shape: const m.RoundedRectangleBorder(
      borderRadius: m.BorderRadius.vertical(top: m.Radius.circular(20)),
    ),
    builder: (sheetContext) {
      // TODO: 之後改為真實資料來源
      final weekMoods = <double>[6, 5, 7, 4, 8, 7, meta.moodScore];
      final sleepHours = 7.2;
      final symptoms = <String, int>{'無力': 2, '腹脹': 1};

      return m.Padding(
        padding: const m.EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: m.Column(
          mainAxisSize: m.MainAxisSize.min,
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Text('當日快速回顧', style: m.Theme.of(context).textTheme.titleLarge),
            const m.SizedBox(height: 8),
            MiniSparkline(values: weekMoods),
            const m.SizedBox(height: 12),

            m.Row(
              children: [
                const m.Icon(m.Icons.nightlight_round, size: 18),
                const m.SizedBox(width: 6),
                m.Text('睡眠：約 ${sleepHours.toStringAsFixed(1)} 小時'),
              ],
            ),
            const m.SizedBox(height: 8),

            m.Row(
              crossAxisAlignment: m.CrossAxisAlignment.start,
              children: [
                const m.Icon(m.Icons.healing_rounded, size: 18),
                const m.SizedBox(width: 6),
                m.Expanded(
                  child: m.Text(
                    symptoms.isEmpty
                        ? '身體症狀：無'
                        : '身體症狀：' +
                            symptoms.entries
                                .map((e) => '${e.key}×${e.value}')
                                .join('、'),
                  ),
                ),
              ],
            ),
            const m.SizedBox(height: 12),
          ],
        ),
      );
    },
  );
  }


  // 收集欄位 → repo.DiaryEntry（供 onChanged 使用）
  repo.DiaryEntry _gather() => repo.DiaryEntry(
        date: DateTime.now(),
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        moodScore: widget.meta.moodScore,
        moodKeyword: widget.meta.moodKeyword,
        themeSong: _song.text.trim().isEmpty ? null : _song.text.trim(),
        highlight: _stripMultiLine(_highlight.text),
        metaphor: _metaphor.text.trim(),
        proudOf: _stripMultiLine(_proud.text),
        selfCare: _stripMultiLine(_selfCare.text),
      );

  static String _stripMultiLine(String s) =>
      s.split('\n').map((e) => e.trim()).join('\n').trim();

  m.Color _moodColor(double score, m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;
    if (score >= 7) return cs.secondaryContainer;
    if (score >= 4) return cs.primaryContainer;
    return cs.tertiaryContainer;
  }
}

// ================== 以下是同檔內的輔助元件（務必在 _DiaryPageState 的 `}` 之後） ==================

class _HeaderCard extends m.StatelessWidget {
  final DateTime date;
  final String dateText;
  final double moodScore;
  final String? moodKeyword;
  final m.Color color;
  final VoidCallback? onPeek;
  final VoidCallback? onOpenDailyRecord;            // 點左側色塊

  const _HeaderCard({
    required this.date,
    required this.dateText,
    required this.moodScore,
    required this.moodKeyword,
    required this.color,
    this.onPeek,
    this.onOpenDailyRecord, // ← 允許為空
  });
  @override
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;

    return m.Card(
      elevation: 0,
      color: cs.surface,
      shape: m.RoundedRectangleBorder(
        borderRadius: m.BorderRadius.circular(16),
      ),
      child: m.Padding(
        padding: const m.EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: m.Row(
          children: [
            // 左：分數色塊
            m.GestureDetector(
              onTap: onPeek,
              child: m.Container(
                width: 56,
                height: 56,
                decoration: m.BoxDecoration(
                  color: color,
                  borderRadius: m.BorderRadius.circular(14),
                ),
                alignment: m.Alignment.center,
                child: m.Text(
                  moodScore.toStringAsFixed(0),
                  style: m.Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: m.FontWeight.w800,
                        color: m.Colors.black.withOpacity(.72),
                      ),
                ),
              ),
            ),
            const m.SizedBox(width: 12),

            // 中：日期與關鍵字
            m.Expanded(
              child: m.Column(
                crossAxisAlignment: m.CrossAxisAlignment.start,
                children: [
                  m.Text(
                    dateText,
                    style: m.Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: m.FontWeight.w700),
                  ),
                  const m.SizedBox(height: 6),
                  m.Row(
                    children: [
                      const m.Icon(m.Icons.label_rounded, size: 16),
                      const m.SizedBox(width: 6),
                      m.Flexible(
                        child: m.Text(
                          (moodKeyword ?? '').isEmpty
                              ? '今日心情'
                              : moodKeyword!,
                          overflow: m.TextOverflow.ellipsis,
                          style: m.Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const m.SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class MiniSparkline extends m.StatelessWidget {
  const MiniSparkline({
    super.key,
    required this.values,
    this.height = 28,
    this.strokeWidth = 2,
    this.padding = const m.EdgeInsets.symmetric(horizontal: 8),
  });

  final List<double> values;
  final double height;
  final double strokeWidth;
  final m.EdgeInsets padding;

  @override
  m.Widget build(m.BuildContext context) {
    if (values.isEmpty) return m.SizedBox(height: height);
    return m.SizedBox(
      height: height,
      width: double.infinity,
      child: m.Padding(
        padding: padding,
        child: m.CustomPaint(
          painter: _SparkPainter(
            values: values,
            color: m.Theme.of(context).colorScheme.primary,
            strokeWidth: strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends m.CustomPainter {
  const _SparkPainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> values;
  final m.Color color;
  final double strokeWidth;

  @override
  void paint(m.Canvas canvas, m.Size size) {
    if (values.isEmpty) return;

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    final paint = m.Paint()
      ..style = m.PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;

    final path = m.Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * (i / (values.length - 1));
      final norm = (values[i] - minV) / range; // 0..1
      final y = size.height - norm * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.values.length != values.length ||
      !_listEq(old.values, values);

  bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _InputCard extends m.StatelessWidget {
  final String label;
  final String hintText;
  final m.TextEditingController controller;
  final int minLines;
  final int maxLines;
  final bool showCounter;

  const _InputCard({
    required this.label,
    required this.hintText,
    required this.controller,
    this.minLines = 3,
    this.maxLines = 20,
    this.showCounter = false,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;

    return m.Card(
      elevation: 0,
      color: cs.surface,
      shape: m.RoundedRectangleBorder(
        borderRadius: m.BorderRadius.circular(16),
      ),
      child: m.Padding(
        padding: const m.EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: m.Column(
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Text(
              label,
              style: m.Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: m.FontWeight.w700),
            ),
            const m.SizedBox(height: 10),
            m.TextField(
              controller: controller,
              minLines: 3,
              maxLines: maxLines,
              decoration: m.InputDecoration(
                hintText: hintText,
                filled: true,
                fillColor: cs.surfaceVariant.withOpacity(.5),
                contentPadding: const m.EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                enabledBorder: m.OutlineInputBorder(
                  borderRadius: m.BorderRadius.circular(12),
                  borderSide: m.BorderSide(color: cs.outline),
                ),
                focusedBorder: m.OutlineInputBorder(
                  borderRadius: m.BorderRadius.circular(12),
                  borderSide: m.BorderSide(color: cs.primary, width: 1.4),
                ),
                counterText: showCounter ? null : '',
              ),
            ),
            if (showCounter) ...[
              const m.SizedBox(height: 6),
              m.Align(
                alignment: m.Alignment.centerRight,
                child: m.Text(
                  '${controller.text.characters.length} 字',
                  style: m.Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
m.InputDecoration tfDecoration(m.BuildContext context, {String? hint}) {
  final cs = m.Theme.of(context).colorScheme;
  return m.InputDecoration(
    hintText: hint,
    border: m.OutlineInputBorder(borderRadius: m.BorderRadius.circular(20)),
    enabledBorder: m.OutlineInputBorder(
      borderRadius: m.BorderRadius.circular(20),
      borderSide: m.BorderSide(color: m.Colors.black.withOpacity(.15)),
    ),
    focusedBorder: m.OutlineInputBorder(
      borderRadius: m.BorderRadius.circular(20),
      borderSide: m.BorderSide(color: cs.primary, width: 2),
    ),
    contentPadding: const m.EdgeInsets.fromLTRB(16, 14, 16, 14),
    isDense: true,
  );
}

class _CharCounter extends m.StatelessWidget {
  const _CharCounter({required this.controller});
  final m.TextEditingController controller;
  
  @override
  m.Widget build(m.BuildContext context) {
    return m.ValueListenableBuilder<m.TextEditingValue>(
      valueListenable: controller,
      builder: (_, v, __) => m.Align(
        alignment: m.Alignment.centerRight,
        child: m.Text(
          '${v.text.characters.length} 字',
          style: m.Theme.of(context).textTheme.bodySmall?.copyWith(color: m.Colors.black54),
        ),
      ),
    );
  }
}
