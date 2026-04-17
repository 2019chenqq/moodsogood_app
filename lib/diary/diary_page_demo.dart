// diary_page_demo.dart
import 'dart:async';
import 'package:flutter/material.dart' as m;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/date_helper.dart';
import '../utils/firebase_sync_config.dart';
import '../widgets/emotion_slider.dart';
import 'diary_repository.dart';
import '../utils/secure_storage_service.dart';
import '../utils/encryption_service.dart';

class DiaryPageDemo extends m.StatefulWidget {
  final DateTime date;
  const DiaryPageDemo({super.key, required this.date});

  @override
  m.State<DiaryPageDemo> createState() => _DiaryPageDemoState();
}

class _DiaryPageDemoState extends m.State<DiaryPageDemo> {
  // ---------------- UI 狀態（控制器） ----------------
  final _titleCtrl = m.TextEditingController();
  final _contentCtrl = m.TextEditingController();
  final _songCtrl = m.TextEditingController();
  final _highlightCtrl = m.TextEditingController();
  final _metaphorCtrl = m.TextEditingController();
  final _conceitedCtrl = m.TextEditingController(); // 為自己感到驕傲的是
  final _proudOfCtrl = m.TextEditingController(); // 我做得不錯的地方
  final _selfCareCtrl = m.TextEditingController(); // 我還能多照顧自己一點
  int _overallMoodScore = 5;
  int _overallHealthScore = 5;
  int _overallSleepScore = 5;

  // ---------------- 自動儲存 ----------------
  Timer? _debouncer;
  bool _saving = false;
  DateTime? _savedAt;
  bool _isHydrating = false;
  bool _blockCloudSaveDueToDecryptFailure = false;

  // ---------------- 上一筆 / 下一筆 ----------------
  DateTime? _prevDate;
  DateTime? _nextDate;

  // ---------------- Firestore 便捷存取 ----------------
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // 正規化到當天 00:00:00
  DateTime get _day =>
      DateTime(widget.date.year, widget.date.month, widget.date.day);

  String get _docId => DateHelper.toId(_day);

  // 日記文件：users/{uid}/diary/{yyyy-MM-dd}
  DocumentReference<Map<String, dynamic>>? get _docRef {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('diary')
        .doc(_docId);
  }

  // ---------------- 生命週期 ----------------
  @override
  void initState() {
    super.initState();
    _loadDraft(); // 讀入當日已存的內容（如有）
    _attachAutoSave(); // 綁定每欄位防彈跳自動儲存
    _loadNeighbors(); // 查上一筆/下一筆
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

  // 從控制器值更新 UI 的輔助函數
  void _updateUIFromData(Map<String, dynamic> data) {
    if (!mounted) return;
    _isHydrating = true;
    _titleCtrl.text = (data['title'] ?? '') as String;
    _contentCtrl.text = (data['content'] ?? '') as String;
    _songCtrl.text = (data['themeSong'] ?? '') as String;
    _highlightCtrl.text = (data['highlight'] ?? '') as String;
    _metaphorCtrl.text = (data['metaphor'] ?? '') as String;
    _conceitedCtrl.text = (data['conceited'] ?? '') as String;
    _proudOfCtrl.text = (data['proudOf'] ?? '') as String;
    _selfCareCtrl.text = (data['selfCare'] ?? '') as String;
    _overallMoodScore = (data['overallMood'] as num?)?.toInt() ?? 5;
    _overallHealthScore = (data['overallHealth'] as num?)?.toInt() ?? 5;
    _overallSleepScore = (data['overallSleepQuality'] as num?)?.toInt() ?? 5;
    _isHydrating = false;
    setState(() {}); // 更新字數
  }

  // 從本地 SQLite + Firebase 加載日記
  Future<void> _loadDraft() async {
    try {
      // 1. 先從本地 SQLite 加載 (本地是明文，直接顯示)
      final repo = DiaryRepository();
      final localEntry = await repo.getByDate(_day);
      if (localEntry != null && mounted) {
        m.debugPrint('📔 Loaded diary from local SQLite');
        _updateUIFromData(localEntry.toMap());
      }

      // 2. 再嘗試從 Firebase 加載（抓下來的可能是密文）
      try {
        final docRef = _docRef;
        if (docRef == null) return;
        final snap = await docRef.get(const GetOptions(source: Source.serverAndCache));
        final data = snap.data();
        if (data != null && mounted) {
          m.debugPrint('📔 Loaded diary from Firebase, decrypting...');
          
          // 🔑 去保險箱拿鑰匙並啟動解密小幫手
          final key = await SecureStorageService.getOrRecoverKey();
          EncryptionService? encService;
          if (key != null) encService = EncryptionService(key);
          var decryptFailed = false;
          final fallbackValues = {
            'title': _titleCtrl.text,
            'content': _contentCtrl.text,
            'themeSong': _songCtrl.text,
            'highlight': _highlightCtrl.text,
            'metaphor': _metaphorCtrl.text,
            'conceited': _conceitedCtrl.text,
            'proudOf': _proudOfCtrl.text,
            'selfCare': _selfCareCtrl.text,
          };

          // 🔓 建立一個輔助函數來解密文字
          String decrypt(dynamic value, String fallback) {
            final str = (value ?? '') as String;
            if (encService != null && str.contains(':')) {
              final plain = encService.tryDecryptData(str);
              if (plain == null) {
                decryptFailed = true;
                return fallback.isNotEmpty ? fallback : '（解密失敗）';
              }
              return plain;
            }
            return str; // 如果沒有冒號，代表它是舊的明文，直接回傳
          }

          // 將解密後的資料重新組裝，更新到畫面上
          final decryptedData = {
            ...data, // 保留不用加密的欄位 (如 date, overallMood 等分數)
            'title': decrypt(data['title'], fallbackValues['title'] ?? ''),
            'content': decrypt(data['content'], fallbackValues['content'] ?? ''),
            'themeSong': decrypt(data['themeSong'], fallbackValues['themeSong'] ?? ''),
            'highlight': decrypt(data['highlight'], fallbackValues['highlight'] ?? ''),
            'metaphor': decrypt(data['metaphor'], fallbackValues['metaphor'] ?? ''),
            'conceited': decrypt(data['conceited'], fallbackValues['conceited'] ?? ''),
            'proudOf': decrypt(data['proudOf'], fallbackValues['proudOf'] ?? ''),
            'selfCare': decrypt(data['selfCare'], fallbackValues['selfCare'] ?? ''),
          };

          _updateUIFromData(decryptedData);

          if (decryptFailed && mounted) {
            _blockCloudSaveDueToDecryptFailure = true;
            m.ScaffoldMessenger.of(context).showSnackBar(
              const m.SnackBar(
                content: m.Text('偵測到解密失敗，已暫停雲端覆寫以保護原始資料。'),
              ),
            );
          }
        }
      } catch (e) {
        m.debugPrint('📔 Firebase load skipped or failed: $e');
      }
    } catch (e) {
      m.debugPrint('❌ Load draft error: $e');
    }
  }

  void _attachAutoSave() {
    for (final c in [
      _titleCtrl,
      _contentCtrl,
      _songCtrl,
      _highlightCtrl,
      _metaphorCtrl,
      _conceitedCtrl,
      _proudOfCtrl,
      _selfCareCtrl,
    ]) {
      c.removeListener(_onAnyFieldChanged);
      c.addListener(_onAnyFieldChanged);
    }
  }

  void _onAnyFieldChanged() {
    if (_isHydrating) return;
    setState(() => _saving = true);
    _debouncer?.cancel();
    _debouncer = Timer(const Duration(milliseconds: 700), _saveDraft);
  }

  Uri? _extractSongUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(
      r'(https?:\/\/[^\s]+|www\.[^\s]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (match == null) return null;

    var rawUrl = match.group(0) ?? '';
    if (rawUrl.isEmpty) return null;

    if (rawUrl.startsWith('www.')) {
      rawUrl = 'https://$rawUrl';
    }

    return Uri.tryParse(rawUrl);
  }

  Future<void> _openSongUrl() async {
    final uri = _extractSongUrl(_songCtrl.text);
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      m.ScaffoldMessenger.of(context).showSnackBar(
        const m.SnackBar(content: m.Text('連結打不開，請檢查網址格式')),
      );
    }
  }

 Future<void> _saveDraft() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // ==========================================
      // 步驟 1：💾 永遠先存一份「明文」到本地資料庫
      // 保證不管網路斷線或加密失敗，用戶打的字絕對不會不見！
      // ==========================================
      try {
        final repo = DiaryRepository();
        await repo.upsert(DiaryEntry(
          date: _day,
          title: _titleCtrl.text.trim(),
          content: _contentCtrl.text.trim(),
          themeSong: _songCtrl.text.trim(),
          highlight: _highlightCtrl.text.trim(),
          metaphor: _metaphorCtrl.text.trim(),
          proudOf: _proudOfCtrl.text.trim(),
          selfCare: _selfCareCtrl.text.trim(),
        ));
        m.debugPrint('✅ 本地 SQLite 儲存成功');
      } catch (e) {
        m.debugPrint('❌ 本地儲存失敗: $e');
      }

      // ==========================================
      // 步驟 2：☁️ 嘗試加密並上傳到 Firebase (獨立區塊，失敗不影響本地)
      // ==========================================
      if (FirebaseSyncConfig.shouldSync() && !_blockCloudSaveDueToDecryptFailure) {
        try {
          final docRef = _docRef;
          if (docRef == null) {
            throw Exception('目前未登入，無法同步雲端日記');
          }

          // 🔑 從保險箱拿出金鑰
          final key = await SecureStorageService.getOrRecoverKey();
          if (key == null) {
            throw Exception('找不到保險箱金鑰');
          }

          // 啟動加密小幫手
          final encService = EncryptionService(key);

          // 🔒 將所有文字欄位進行加密
          await docRef.set({
            'date': Timestamp.fromDate(_day),
            'title': encService.encryptData(_titleCtrl.text.trim()),
            'content': encService.encryptData(_contentCtrl.text.trim()),
            'themeSong': encService.encryptData(_songCtrl.text.trim()),
            'highlight': encService.encryptData(_highlightCtrl.text.trim()),
            'metaphor': encService.encryptData(_metaphorCtrl.text.trim()),
            'conceited': encService.encryptData(_conceitedCtrl.text.trim()),
            'proudOf': encService.encryptData(_proudOfCtrl.text.trim()),
            'selfCare': encService.encryptData(_selfCareCtrl.text.trim()),
            'overallMood': _overallMoodScore,
            'overallHealth': _overallHealthScore,
            'overallSleepQuality': _overallSleepScore,
            'updatedAt': FieldValue.serverTimestamp(),
            'isEncrypted': true,
          }, SetOptions(merge: true));
          
          m.debugPrint('✅ 雲端加密儲存成功');
          
        } catch (e) {
          m.debugPrint('⚠️ 雲端加密上傳失敗 (已暫存於本地): $e');
          // 這裡故意拿掉 Snackbar，避免用戶在打字時一直被跳出的紅字打擾
        }
      } else if (_blockCloudSaveDueToDecryptFailure) {
        m.debugPrint('🛡️ 已暫停雲端寫入：避免覆蓋仍可恢復的加密資料');
      }

      // ==========================================
      // 步驟 3：更新 UI 顯示「已儲存」
      // 只要本地有存成功，我們就讓用戶安心
      // ==========================================
      if (!mounted) return;
      setState(() {
        _saving = false;
        _savedAt = DateTime.now();
      });

    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      m.debugPrint('自動儲存發生未預期的錯誤: $e');
    }
  }

  // 查上一筆 / 下一筆（以日記集合的 date 欄位為準）
  Future<void> _loadNeighbors() async {
    try {
      final uid = _uid;
      if (uid == null) return;

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
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

  // 刪除整天日記（雲端 + 本地）
  Future<void> _confirmAndDeleteDay() async {
    final ok = await m.showDialog<bool>(
      context: context,
      builder: (_) => m.AlertDialog(
        title: const m.Text('刪除這一天的日記？'),
        content: const m.Text('這會刪除整天日記資料（不是只清空欄位）。此動作無法復原。'),
        actions: [
          m.TextButton(
              onPressed: () => m.Navigator.pop(context, false),
              child: const m.Text('取消')),
          m.FilledButton(
              onPressed: () => m.Navigator.pop(context, true),
              child: const m.Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (!mounted) return;
        m.ScaffoldMessenger.of(context).showSnackBar(
          const m.SnackBar(content: m.Text('請先登入')),
        );
        return;
      }

      // 先刪除雲端資料（若有）
      if (FirebaseSyncConfig.shouldSync()) {
        final docRef = _docRef;
        if (docRef != null) {
          await docRef.delete();
        }
      }

      // 再刪除本地資料
      final repo = DiaryRepository();
      await repo.deleteByDate(_day);

      if (!mounted) return;
      m.ScaffoldMessenger.of(context).showSnackBar(
        const m.SnackBar(content: m.Text('已刪除當日日記')),
      );

      if (m.Navigator.of(context).canPop()) {
        m.Navigator.of(context).pop(true);
      } else {
        _titleCtrl.clear();
        _contentCtrl.clear();
        _songCtrl.clear();
        _highlightCtrl.clear();
        _metaphorCtrl.clear();
        _conceitedCtrl.clear();
        _proudOfCtrl.clear();
        _selfCareCtrl.clear();
        setState(() {});
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      m.ScaffoldMessenger.of(context).showSnackBar(
        m.SnackBar(content: m.Text('刪除失敗：${e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      m.ScaffoldMessenger.of(context).showSnackBar(
        m.SnackBar(content: m.Text('刪除失敗：$e')),
      );
    }
  }

  // ---------------- UI ----------------
  @override
  m.Widget build(m.BuildContext context) {
    final d = DateTime(widget.date.year, widget.date.month, widget.date.day);

    return m.Scaffold(
      appBar: m.AppBar(
        title: m.Text('編輯日記 - ${_day.month}/${_day.day}'),
        actions: [
          m.IconButton(
            tooltip: '刪除當日日記',
            icon: const m.Icon(m.Icons.delete_outline),
            onPressed: _confirmAndDeleteDay,
          ),
          if (_saving)
            const m.Padding(
              padding: m.EdgeInsets.symmetric(horizontal: 12),
              child: m.Center(
                child: m.SizedBox(
                    width: 16,
                    height: 16,
                    child: m.CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (_savedAt != null)
            m.Padding(
              padding: const m.EdgeInsets.only(right: 12),
              child: m.Center(
                  child: m.Text('已儲存',
                      style: m.Theme.of(context).textTheme.labelMedium)),
            ),
        ],
      ),
      body: m.SafeArea(
        child: m.ListView(
          padding: const m.EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _DateHeaderCard(date: d),
            const m.SizedBox(height: 12),

            _OverallSlidersCard(
              overallMoodScore: _overallMoodScore,
              overallHealthScore: _overallHealthScore,
              overallSleepScore: _overallSleepScore,
              onMoodChanged: (v) {
                setState(() => _overallMoodScore = v);
                _onAnyFieldChanged();
              },
              onHealthChanged: (v) {
                setState(() => _overallHealthScore = v);
                _onAnyFieldChanged();
              },
              onSleepChanged: (v) {
                setState(() => _overallSleepScore = v);
                _onAnyFieldChanged();
              },
            ),
            const m.SizedBox(height: 12),

// 只有當有上一筆或下一筆時才顯示按鈕區
            if (_prevDate != null || _nextDate != null) ...[
              m.Row(
                mainAxisAlignment: m.MainAxisAlignment
                    .spaceBetween, // 改成 spaceBetween 會比較開闊，看你喜好
                children: [
                  // <--- 上一筆按鈕
                  if (_prevDate != null)
                    m.TextButton.icon(
                      icon: const m.Icon(m.Icons.chevron_left),
                      // 使用 Helper 顯示漂亮日期，例如 "11/28"
                      label: m.Text(
                          '上一篇 (${DateHelper.toDisplay(_prevDate!).substring(5)})'),
                      onPressed: () => _openDiary(_prevDate!),
                    )
                  else
                    const m.SizedBox(), // 佔位用

                  // ---> 下一筆按鈕
                  if (_nextDate != null)
                    m.TextButton.icon(
                      // 讓圖示在文字右邊 (利用 Directionality 或自訂 Row，這裡用簡單的 Row)
                      label: m.Text(
                          '下一篇 (${DateHelper.toDisplay(_nextDate!).substring(5)})'),
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
              icon: m.Icons.edit,
              label: '標題（可留白）',
              hint: '幫今天下一個小標題，也可以跳過…',
              minLines: 1,
              maxLines: 1,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _contentCtrl,
              icon: m.Icons.description,
              label: '內容',
              hint: '留下一點點也很好…',
              minLines: 8,
              maxLines: 10,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _metaphorCtrl,
              icon: m.Icons.mood,
              label: '今天的情緒像…',
              hint: '例：潮汐、霧氣、烈陽、厚被…',
              minLines: 1,
              maxLines: 3,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _highlightCtrl,
              icon: m.Icons.auto_awesome,
              label: '今天最想記錄的瞬間',
              hint: '今天最想留住的畫面、對話或感受…',
              minLines: 3,
              maxLines: 10,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _proudOfCtrl,
              icon: m.Icons.wb_sunny,
              label: '我做得不錯的地方',
              hint: '肯定一下今天的自己，哪怕是很小的事情，例如：我有按時吃藥、我有出門散步…',
              minLines: 3,
              maxLines: 10,
              onAnyChanged: _onAnyFieldChanged,
            ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _songCtrl,
              icon: m.Icons.music_note,
              label: '今日的主題曲',
              hint: '歌名／連結／演出者…',
              minLines: 1,
              maxLines: 3,
              onAnyChanged: _onAnyFieldChanged,
            ),
            if (_extractSongUrl(_songCtrl.text) != null)
              m.Align(
                alignment: m.Alignment.centerLeft,
                child: m.InkWell(
                  onTap: _openSongUrl,
                  borderRadius: m.BorderRadius.circular(6),
                  child: m.Padding(
                    padding: const m.EdgeInsets.symmetric(vertical: 4),
                    child: m.Text(
                      _extractSongUrl(_songCtrl.text).toString(),
                      maxLines: 1,
                      overflow: m.TextOverflow.ellipsis,
                      style: const m.TextStyle(
                        color: m.Color(0xFF1976D2),
                        decoration: m.TextDecoration.underline,
                        fontWeight: m.FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            const m.SizedBox(height: 12),

            CountTextField(
              controller: _selfCareCtrl,
              icon: m.Icons.favorite_border,
              label: '我還能多照顧自己一點的地方',
              hint: '睡眠、飲食、邊界、運動或求助…下一步可以怎麼做？',
              minLines: 3,
              maxLines: 10,
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
    final text = DateHelper.toDisplay(date); // yyyy-MM-dd

    return m.Container(
      margin: const m.EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const m.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: m.BoxDecoration(
        color: m.Colors.white,
        borderRadius: m.BorderRadius.circular(20),
        boxShadow: [
          m.BoxShadow(
            color: m.Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const m.Offset(0, 6),
          ),
        ],
        // 淺淺的底：不會干擾整體
        gradient: m.LinearGradient(
          colors: [
            m.Colors.black.withValues(alpha: 0.04),
            m.Colors.black.withValues(alpha: 0.02)
          ],
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

  String _weekdayZh(int wd) =>
      const ['一', '二', '三', '四', '五', '六', '日'][wd - 1];

  m.Widget _chip(String text) {
    return m.Container(
      padding: const m.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: m.BoxDecoration(
        color: m.Colors.black.withValues(alpha: 0.06),
        borderRadius: m.BorderRadius.circular(999),
      ),
      child: m.Text(
        text,
        style: const m.TextStyle(fontSize: 12, height: 1.0, letterSpacing: 0.2),
      ),
    );
  }
}

class _OverallSlidersCard extends m.StatelessWidget {
  final int overallMoodScore;
  final int overallHealthScore;
  final int overallSleepScore;
  final m.ValueChanged<int> onMoodChanged;
  final m.ValueChanged<int> onHealthChanged;
  final m.ValueChanged<int> onSleepChanged;

  const _OverallSlidersCard({
    required this.overallMoodScore,
    required this.overallHealthScore,
    required this.overallSleepScore,
    required this.onMoodChanged,
    required this.onHealthChanged,
    required this.onSleepChanged,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return m.Card(
      elevation: 1.5,
      shape:
          m.RoundedRectangleBorder(borderRadius: m.BorderRadius.circular(20)),
      child: m.Padding(
        padding: const m.EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: m.Column(
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Text(
              '今日整體狀態',
              style: m.Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: m.FontWeight.w700,
                  ),
            ),
            const m.SizedBox(height: 6),
            m.Text('今天的整體情緒如何？',
                style: m.Theme.of(context).textTheme.titleSmall),
            EmotionSlider(
              label: '今天的整體情緒如何？',
              value: overallMoodScore,
              onChanged: onMoodChanged,
              leftIcon: 'assets/emotion/default.png',
              rightIcon: 'assets/emotion/overall.png',
              gradientColors: const [
                m.Color(0xFF9AD0EC),
                m.Color(0xFFFFE08A),
              ],
            ),
            const m.SizedBox(height: 6),
            m.Text('今天的健康狀況如何？',
                style: m.Theme.of(context).textTheme.titleSmall),
            EmotionSlider(
              label: '今天的健康狀況如何？',
              value: overallHealthScore,
              onChanged: onHealthChanged,
              leftIcon: 'assets/emotion/default.png',
              rightIcon: 'assets/emotion/energy.png',
              gradientColors: const [
                m.Color(0xFF9AD0EC),
                m.Color(0xFFFFE08A),
              ],
            ),
            const m.SizedBox(height: 6),
            m.Text('整體睡眠品質', style: m.Theme.of(context).textTheme.titleSmall),
            EmotionSlider(
              label: '整體睡眠品質',
              value: overallSleepScore,
              onChanged: onSleepChanged,
              leftIcon: 'assets/emotion/tired.png',
              rightIcon: 'assets/emotion/happy.png',
              gradientColors: const [
                m.Color(0xFF9AD0EC),
                m.Color(0xFFFFE08A),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================== 小元件：帶字數的 TextField ==================
class CountTextField extends m.StatelessWidget {
  final m.TextEditingController controller;
  final m.IconData? icon;
  final String label;
  final String? hint;
  final m.TextStyle? textStyle;
  final m.TextStyle? hintStyle;
  final m.Color? fillColor;
  final m.Color? borderColor;
  final int minLines;
  final int maxLines;
  final void Function()? onAnyChanged;

  const CountTextField({
    super.key,
    required this.controller,
    this.icon,
    required this.label,
    this.hint,
    required this.minLines,
    required this.maxLines,
    this.onAnyChanged,
    this.textStyle,
    this.hintStyle,
    this.fillColor,
    this.borderColor,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;
    final effectiveTextStyle =
        (textStyle ?? const m.TextStyle(fontSize: 16, height: 1.5)).copyWith(
      color: textStyle?.color ?? cs.onSurface,
    );
    final effectiveHintStyle =
        (hintStyle ?? const m.TextStyle(fontSize: 16, height: 1.5)).copyWith(
      color: hintStyle?.color ?? cs.onSurfaceVariant,
    );
    final effectiveCounterColor = cs.onSurfaceVariant;

    return m.Card(
      elevation: 1.5,
      shadowColor: m.Colors.black12,
      color: m.Theme.of(context).cardColor,
      shape:
          m.RoundedRectangleBorder(borderRadius: m.BorderRadius.circular(20)),
      child: m.Padding(
        padding: const m.EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: m.Column(
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Row(
              children: [
                if (icon != null) ...[
                  m.Icon(icon, size: 18, color: cs.primary),
                  const m.SizedBox(width: 6),
                ],
                m.Expanded(
                  child: m.Text(
                    label,
                    style: m.Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const m.SizedBox(height: 8),
            m.TextField(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
              textAlign: m.TextAlign.justify, // ★ 兩端對齊（保留）
              textAlignVertical: m.TextAlignVertical.top, // ★ 文字從上方開始（保留）
              keyboardType: m.TextInputType.multiline,
              textInputAction: m.TextInputAction.newline,

              // 依主題自動調整文字顏色
              style: effectiveTextStyle,

              decoration: m.InputDecoration(
                hintText: hint,

                // 依主題自動調整提示字顏色
                hintStyle: effectiveHintStyle,

                border: m.InputBorder.none,
              ),
              onChanged: (_) => onAnyChanged?.call(),
            ),
            m.Align(
              alignment: m.Alignment.bottomRight,
              child: m.Text(
                '${controller.text.characters.length} 字',
                style: m.Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: effectiveCounterColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
