// diary_page_demo.dart
import 'dart:async';
import 'package:flutter/material.dart' as m;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/date_helper.dart';

class DiaryPageDemo extends m.StatefulWidget {
  final DateTime date;
  const DiaryPageDemo({super.key, required this.date});

  @override
  m.State<DiaryPageDemo> createState() => _DiaryPageDemoState();
}

String get _uid => FirebaseAuth.instance.currentUser!.uid;

DocumentReference<Map<String, dynamic>> _refForDay(DateTime d) {
  return FirebaseFirestore.instance
      .collection('users').doc(_uid)
      .collection('diary').doc(DateHelper.toId(d));
}

class _DiaryPageDemoState extends m.State<DiaryPageDemo> {
 
  CollectionReference<Map<String,dynamic>> get _dailyCol => FirebaseFirestore
      .instance.collection('users').doc(_uid).collection('diary');

  // 若你有「上一筆/下一筆」切換日期，切完要再讀一次
  void _goTo(DateTime d) {
    // ... 你原本的切換邏輯 ... 
  }
  // ---------------- UI 狀態（控制器） ----------------
  final _titleCtrl     = m.TextEditingController();
  final _contentCtrl   = m.TextEditingController();
  final _songCtrl      = m.TextEditingController();
  final _highlightCtrl = m.TextEditingController();
  final _metaphorCtrl  = m.TextEditingController();
  final _conceitedCtrl = m.TextEditingController(); // 為自己感到驕傲的是
  final _proudOfCtrl   = m.TextEditingController(); // 我做得不錯的地方
  final _selfCareCtrl  = m.TextEditingController(); // 我還能多照顧自己一點

  // ---------------- 自動儲存 ----------------
  Timer? _debouncer;
  bool _saving = false;
  DateTime? _savedAt;

  // ---------------- 上一筆 / 下一筆 ----------------
  DateTime? _prevDate;
  DateTime? _nextDate;

  // ---------------- Firestore 便捷存取 ----------------
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // 正規化到當天 00:00:00
  DateTime get _day => DateTime(widget.date.year, widget.date.month, widget.date.day);

 String get _docId => DateHelper.toId(_day);

  // 日記文件：users/{uid}/diary/{yyyy-MM-dd}
  DocumentReference<Map<String, dynamic>> get _docRef => FirebaseFirestore.instance
      .collection('users').doc(_uid)
      .collection('diary') // TODO: 若你的日記集合名不同（例如 diaries），改這裡
      .doc(_docId);

  // ---------------- 生命週期 ----------------
  @override
  void initState() {
    super.initState();
    _loadDraft();          // 讀入當日已存的內容（如有）
    _attachAutoSave();     // 綁定每欄位防彈跳自動儲存
    _loadNeighbors();      // 查上一筆/下一筆
  }

  @override
  void dispose() {
    _debouncer?.cancel();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _songCtrl.dispose();
    _highlightCtrl.dispose();
    _metaphorCtrl.dispose();
    _conceitedCtrl.dispose();
    _proudOfCtrl.dispose();
    _selfCareCtrl.dispose();
    super.dispose();
  }

  // ---------------- 載入與儲存 ----------------
  Future<void> _loadDraft() async {
    try {
      final snap = await _docRef.get(const GetOptions(source: Source.serverAndCache));
      final data = snap.data();
      if (data != null && mounted) {
        _titleCtrl.text     = (data['title']     ?? '') as String;
        _contentCtrl.text   = (data['content']   ?? '') as String;
        _songCtrl.text      = (data['themeSong'] ?? '') as String;
        _highlightCtrl.text = (data['highlight'] ?? '') as String;
        _metaphorCtrl.text  = (data['metaphor']  ?? '') as String;
        _conceitedCtrl.text = (data['conceited'] ?? '') as String;
        _proudOfCtrl.text   = (data['proudOf']   ?? '') as String;
        _selfCareCtrl.text  = (data['selfCare']  ?? '') as String;
        setState(() {}); // 更新字數
      }
    } catch (e) {
      m.debugPrint('load draft error: $e');
    }
  }

  void _attachAutoSave() {
    for (final c in [
      _titleCtrl, _contentCtrl, _songCtrl, _highlightCtrl,
      _metaphorCtrl, _conceitedCtrl, _proudOfCtrl, _selfCareCtrl,
    ]) {
      c.removeListener(_onAnyFieldChanged);
      c.addListener(_onAnyFieldChanged);
    }
  }

  void _onAnyFieldChanged() {
    setState(() => _saving = true);
    _debouncer?.cancel();
    _debouncer = Timer(const Duration(milliseconds: 700), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      await _docRef.set({
        'date'     : Timestamp.fromDate(_day),
        'title'    : _titleCtrl.text.trim(),
        'content'  : _contentCtrl.text.trim(),
        'themeSong': _songCtrl.text.trim(),
        'highlight': _highlightCtrl.text.trim(),
        'metaphor' : _metaphorCtrl.text.trim(),
        'conceited': _conceitedCtrl.text.trim(),
        'proudOf'  : _proudOfCtrl.text.trim(),
        'selfCare' : _selfCareCtrl.text.trim(),

        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() { _saving = false; _savedAt = DateTime.now(); });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      m.ScaffoldMessenger.of(context).showSnackBar(
        m.SnackBar(content: m.Text('儲存失敗：${e.code}')),
      );
    }
  }

  // 查上一筆 / 下一筆（以日記集合的 date 欄位為準）
  Future<void> _loadNeighbors() async {
    try {
      final col = FirebaseFirestore.instance
          .collection('users').doc(_uid)
          .collection('diary'); // ⚠️ 確認這裡的集合名稱跟你的日記一樣 (diary 或 dailyRecords)

      // 確保用當日 00:00:00 的 Timestamp 進行比較
      final currentTs = Timestamp.fromDate(_day);

      // 1. 找上一筆：日期 < 今天，倒序排 (desc)，取第 1 筆
      final prevSnap = await col
          .where('date', isLessThan: currentTs)
          .orderBy('date', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));

      // 2. 找下一筆：日期 > 今天，正序排 (asc)，取第 1 筆
      final nextSnap = await col
          .where('date', isGreaterThan: currentTs)
          .orderBy('date', descending: false)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!mounted) return;
      setState(() {
        // 如果有找到文件，把 Timestamp 轉回 DateTime
        _prevDate = prevSnap.docs.isNotEmpty
            ? (prevSnap.docs.first.data()['date'] as Timestamp).toDate()
            : null;
            
        _nextDate = nextSnap.docs.isNotEmpty
            ? (nextSnap.docs.first.data()['date'] as Timestamp).toDate()
            : null;
      });
      
      // debugPrint('Prev: $_prevDate, Next: $_nextDate');
    } catch (e) {
      m.debugPrint('neighbors error: $e');
    }
  }
// 切換到指定日期
  void _openDiary(DateTime d) {
    // 1. 確保拿到的是純淨的日期物件 (00:00:00)
    final targetDate = DateTime(d.year, d.month, d.day);
    
    // 2. 使用 pushReplacement 切換頁面，避免堆疊過多層
    m.Navigator.of(context).pushReplacement(
      m.MaterialPageRoute(
        builder: (_) => DiaryPageDemo(date: targetDate),
      ),
    );
  }

  // 清空欄位
  Future<void> _confirmAndClear() async {
    final ok = await m.showDialog<bool>(
      context: context,
      builder: (_) => m.AlertDialog(
        title: const m.Text('清空當日內容？'),
        content: const m.Text('這會把所有欄位清成空白（仍會保留這一天的文件）。'),
        actions: [
          m.TextButton(onPressed: () => m.Navigator.pop(context, false), child: const m.Text('取消')),
          m.FilledButton(onPressed: () => m.Navigator.pop(context, true), child: const m.Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    _titleCtrl.clear();
    _contentCtrl.clear();
    _songCtrl.clear();
    _highlightCtrl.clear();
    _metaphorCtrl.clear();
    _conceitedCtrl.clear();
    _proudOfCtrl.clear();
    _selfCareCtrl.clear();
    _onAnyFieldChanged(); // 觸發儲存
  }

  // ---------------- UI ----------------
  void _goPrevDay() {
  if (_prevDate != null) _openDiary(_prevDate!);
}

void _goNextDay() {
  if (_nextDate != null) _openDiary(_nextDate!);
}
  @override
  m.Widget build(m.BuildContext context) {
    final dateText =
        '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';
    final color = m.Theme.of(context).colorScheme.secondaryContainer;
final d = DateTime(widget.date.year, widget.date.month, widget.date.day);

    return m.Scaffold(
      appBar: m.AppBar(
        title: m.Text('編輯日記 - ${_day.month}/${_day.day}'),
        actions: [
          m.IconButton(
            tooltip: '清空內容',
            icon: const m.Icon(m.Icons.clear_all_outlined),
            onPressed: _confirmAndClear,
          ),
          if (_saving)
            const m.Padding(
              padding: m.EdgeInsets.symmetric(horizontal: 12),
              child: m.Center(
                child: m.SizedBox(width: 16, height: 16,
                  child: m.CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (_savedAt != null)
            m.Padding(
              padding: const m.EdgeInsets.only(right: 12),
              child: m.Center(child: m.Text('已儲存', style: m.Theme.of(context).textTheme.labelMedium)),
            ),
        ],
      ),
      body: m.SafeArea(
        child: m.ListView(
          padding: const m.EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
          _DateHeaderCard(date: d),
const m.SizedBox(height: 12),

// 只有當有上一筆或下一筆時才顯示按鈕區
if (_prevDate != null || _nextDate != null) ...[
  m.Row(
    mainAxisAlignment: m.MainAxisAlignment.spaceBetween, // 改成 spaceBetween 會比較開闊，看你喜好
    children: [
      // <--- 上一筆按鈕
      if (_prevDate != null)
        m.TextButton.icon(
          icon: const m.Icon(m.Icons.chevron_left),
          // 使用 Helper 顯示漂亮日期，例如 "11/28"
          label: m.Text('上一篇 (${DateHelper.toDisplay(_prevDate!).substring(5)})'), 
          onPressed: () => _openDiary(_prevDate!),
        )
      else
        const m.SizedBox(), // 佔位用

      // ---> 下一筆按鈕
      if (_nextDate != null)
        m.TextButton.icon(
          // 讓圖示在文字右邊 (利用 Directionality 或自訂 Row，這裡用簡單的 Row)
          label: m.Text('下一篇 (${DateHelper.toDisplay(_nextDate!).substring(5)})'),
          icon: const m.Icon(m.Icons.chevron_right),
          // 調整 icon 方向讓它在右邊
          iconAlignment: m.IconAlignment.end, 
          onPressed: () => _openDiary(_nextDate!),
        )
      else
        const m.SizedBox(),
    ],
  ),
  const m.SizedBox(height: 8),
],

            // --------- 各欄位（右下角字數、自動儲存） ---------
            CountTextField(
              controller: _titleCtrl,
              label: '🖊️ 標題（可留白）',
              hint: '幫今天下一個小標題，也可以跳過…',
              minLines: 1, maxLines: 1,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _contentCtrl,
              label: '📜 內容',
              hint: '留下一點點也很好…',
              minLines: 8, maxLines: 10,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _songCtrl,
              label: '🎧 今日的主題曲',
              hint: '歌名／連結／演出者…',
              minLines: 1, maxLines: 3,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _highlightCtrl,
              label: '✨ 今天最想記錄的瞬間',
              hint: '今天最想留住的畫面、對話或感受…',
              minLines: 3, maxLines: 10,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _metaphorCtrl,
              label: '🌚 今天的情緒像…',
              hint: '例：潮汐、霧氣、烈陽、厚被…',
              minLines: 1, maxLines: 3,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _conceitedCtrl,
              label: '🥇 為自己感到驕傲的是',
              hint: '完成了什麼、撐住了什麼、或小小突破…',
              minLines: 2, maxLines: 10,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _proudOfCtrl,
              label: '🌤️ 我做得不錯的地方',
              hint: '肯定一下今天的自己，哪怕是很小的事情…',
              minLines: 3, maxLines: 10,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _selfCareCtrl,
              label: '❤️‍🩹 我還能多照顧自己一點的地方',
              hint: '睡眠、飲食、邊界、運動或求助…下一步可以怎麼做？',
              minLines: 3, maxLines: 10,
              onAnyChanged: _onAnyFieldChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// ======= Compact Date Header Card (date only) =======
class _DateHeaderCard extends m.StatelessWidget {
  final DateTime date;
  const _DateHeaderCard({required this.date});

  @override
  m.Widget build(m.BuildContext context) {
    final text = DateHelper.toDisplay(date);     // yyyy-MM-dd
    final wd   = _weekdayZh(date.weekday);

    return m.Container(
      margin: const m.EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const m.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: m.BoxDecoration(
        color: m.Colors.white,
        borderRadius: m.BorderRadius.circular(20),
        boxShadow: [
          m.BoxShadow(
            color: m.Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const m.Offset(0, 6),
          ),
        ],
        // 淺淺的底：不會干擾整體
        gradient: m.LinearGradient(
          colors: [m.Colors.black.withOpacity(0.04), m.Colors.black.withOpacity(0.02)],
          begin: m.Alignment.topLeft,
          end: m.Alignment.bottomRight,
        ),
      ),
      child: m.Row(
        children: [
          // 日期
          m.Expanded(
            child: m.Column(
              crossAxisAlignment: m.CrossAxisAlignment.start,
              children: [
                m.Text(
                  text, // yyyy-MM-dd
                  style: m.Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: m.FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
                const m.SizedBox(height: 6),
                _chip('星期${_weekdayZh(date.weekday)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- helpers ----------

  String _weekdayZh(int wd) => const ['一','二','三','四','五','六','日'][wd - 1];

  m.Widget _chip(String text) {
    return m.Container(
      padding: const m.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: m.BoxDecoration(
        color: m.Colors.black.withOpacity(0.06),
        borderRadius: m.BorderRadius.circular(999),
      ),
      child: m.Text(
        text,
        style: const m.TextStyle(fontSize: 12, height: 1.0, letterSpacing: 0.2),
      ),
    );
  }
}

// ================== 小元件：帶字數的 TextField ==================
class CountTextField extends m.StatelessWidget {
  final m.TextEditingController controller;
  final String label;
  final String? hint;
  final int minLines;
  final int maxLines;
  final void Function()? onAnyChanged;

  const CountTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    required this.minLines,
    required this.maxLines,
    this.onAnyChanged,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return m.Card(
      elevation: 1.5,
      shadowColor: m.Colors.black12,
      color: m.Theme.of(context).cardColor,
      shape: m.RoundedRectangleBorder(borderRadius: m.BorderRadius.circular(20)),
      child: m.Padding(
        padding: const m.EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: m.Column(
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Text(label, style: m.Theme.of(context).textTheme.titleMedium),
            const m.SizedBox(height: 8),
            m.TextField(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
              textAlign: m.TextAlign.justify,              // ★ 兩端對齊
              textAlignVertical: m.TextAlignVertical.top,  // 文字從上方開始
              keyboardType: m.TextInputType.multiline,
              textInputAction: m.TextInputAction.newline,
              decoration: m.InputDecoration(
                hintText: hint,
                border: m.InputBorder.none,
              ),
              onChanged: (_) => onAnyChanged?.call(),
            ),
            m.Align(
              alignment: m.Alignment.bottomRight,
              child: m.Text(
                '${controller.text.characters.length} 字',
                style: m.Theme.of(context).textTheme.labelSmall?.copyWith(color: m.Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
