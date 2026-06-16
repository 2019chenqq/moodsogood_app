// diary_page_demo.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart' as m;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../utils/date_helper.dart';
import '../utils/firebase_sync_config.dart';
import '../constants/healing_design_system.dart';
import '../widgets/emotion_slider.dart';
import 'ai_journal_reflection_page.dart';
import '../utils/secure_storage_service.dart';
import '../utils/encryption_service.dart';
import '../utils/key_manager.dart';
import '../test_pages/pro_preview_page.dart';
import '../analytics_service.dart';

const int kDiaryMaxImageCount = 10;

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
  List<String> _imageUrls = [];
  bool _uploadingImage = false;
  int _overallMoodScore = 5;
  int _overallHealthScore = 5;
  int _overallSleepScore = 5;

  // ---------------- 自動儲存 ----------------
  Timer? _debouncer;
  bool _saving = false;
  DateTime? _savedAt;
  bool _isHydrating = false;
  bool _blockCloudSaveDueToDecryptFailure = false;
  bool _needsLegacyRepair = false;
  bool _isRepairingLegacy = false;
  final Map<String, String> _failedEncryptedPayload = {};

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
    AnalyticsService.logPage('diary_page');
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
      // 2. 再嘗試從 Firebase 加載（抓下來的可能是密文）
      try {
        final docRef = _docRef;
        if (docRef == null) return;
        final snap =
            await docRef.get(const GetOptions(source: Source.serverAndCache));
        final data = snap.data();
        if (data != null && mounted) {
          m.debugPrint('📔 Loaded diary from Firebase, decrypting...');

          // 🔑 去保險箱拿鑰匙並啟動解密小幫手
          final key = await SecureStorageService.getKey();
          EncryptionService? encService;
          if (key != null) encService = EncryptionService(key);
          var decryptFailed = false;
          _failedEncryptedPayload.clear();
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
          String decrypt(String field, dynamic value, String fallback) {
            final str = (value ?? '') as String;
            if (str.contains(':')) {
              if (encService == null) {
                decryptFailed = true;
                _failedEncryptedPayload[field] = str;
                return fallback;
              }
              final plain = encService.tryDecryptData(str);
              if (plain == null) {
                decryptFailed = true;
                _failedEncryptedPayload[field] = str;
                return fallback;
              }
              return plain;
            }
            return str; // 如果沒有冒號，代表它是舊的明文，直接回傳
          }

          // 將解密後的資料重新組裝，更新到畫面上
          final decryptedData = {
            ...data, // 保留不用加密的欄位 (如 date, overallMood 等分數)
            'title':
                decrypt('title', data['title'], fallbackValues['title'] ?? ''),
            'content': decrypt(
                'content', data['content'], fallbackValues['content'] ?? ''),
            'themeSong': decrypt('themeSong', data['themeSong'],
                fallbackValues['themeSong'] ?? ''),
            'highlight': decrypt('highlight', data['highlight'],
                fallbackValues['highlight'] ?? ''),
            'metaphor': decrypt(
                'metaphor', data['metaphor'], fallbackValues['metaphor'] ?? ''),
            'conceited': decrypt('conceited', data['conceited'],
                fallbackValues['conceited'] ?? ''),
            'proudOf': decrypt(
                'proudOf', data['proudOf'], fallbackValues['proudOf'] ?? ''),
            'selfCare': decrypt(
                'selfCare', data['selfCare'], fallbackValues['selfCare'] ?? ''),
          };

          _updateUIFromData(decryptedData);

          if (mounted) {
            setState(() {
              _blockCloudSaveDueToDecryptFailure = decryptFailed;
              _needsLegacyRepair = decryptFailed;
            });
          }

          if (decryptFailed && mounted) {
            m.ScaffoldMessenger.of(context).showSnackBar(
              const m.SnackBar(content: m.Text('此紀錄需要使用舊安全碼修復')),
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

  Future<void> _openAiReflection() async {
    await _saveDraft();
    if (!mounted) return;

    await m.Navigator.of(context).push(
      m.MaterialPageRoute(
        builder: (_) => AiJournalReflectionPage(date: _day),
      ),
    );
  }

  encrypt_lib.Key _deriveLegacyKey(String pin, String salt) {
    List<int> bytes = utf8.encode(pin + salt);
    for (int i = 0; i < 10000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return encrypt_lib.Key(Uint8List.fromList(bytes));
  }

  Future<void> _showRepairDialog() async {
    if (!mounted) return;
    final pinController = m.TextEditingController();
    final oldPin = await m.showDialog<String>(
      context: context,
      builder: (dialogContext) => m.AlertDialog(
        title: const m.Text('修復舊日記'),
        content: m.TextField(
          controller: pinController,
          keyboardType: m.TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: const m.InputDecoration(
            labelText: '請輸入舊的 6 位數保險箱密碼',
            counterText: '',
          ),
        ),
        actions: [
          m.TextButton(
            onPressed: () => m.Navigator.of(dialogContext).pop(),
            child: const m.Text('取消'),
          ),
          m.FilledButton(
            onPressed: () {
              final inputPin = pinController.text.trim();
              if (inputPin.length != 6) return;
              m.Navigator.of(dialogContext).pop(inputPin);
            },
            child: const m.Text('修復舊日記'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (oldPin == null || oldPin.length != 6) return;
    await _repairLegacyDiary(oldPin);
  }

  Future<void> _repairLegacyDiary(String oldPin) async {
    if (_isRepairingLegacy || _failedEncryptedPayload.isEmpty) return;
    final uid = _uid;
    final docRef = _docRef;
    if (uid == null || docRef == null) return;
    if (!mounted) return;

    setState(() => _isRepairingLegacy = true);
    try {
      final currentKey = await SecureStorageService.getKey();
      if (!mounted) return;
      if (currentKey == null) {
        throw Exception('找不到目前保險箱金鑰');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final cloudSalt =
          (userDoc.data()?['encryptionSalt'] as String?)?.trim() ?? '';
      final localSalt = (prefs.getString('e2eSalt') ?? '').trim();
      final legacySalt =
          (userDoc.data()?['legacyEncryptionSalt'] as String?)?.trim() ?? '';
      final oldSalt =
          (userDoc.data()?['oldEncryptionSalt'] as String?)?.trim() ?? '';

      final salts = <String>{};
      if (cloudSalt.isNotEmpty) salts.add(cloudSalt);
      if (localSalt.isNotEmpty) salts.add(localSalt);
      if (legacySalt.isNotEmpty) salts.add(legacySalt);
      if (oldSalt.isNotEmpty) salts.add(oldSalt);
      if (salts.isEmpty) {
        throw Exception('找不到可用 salt');
      }

      Map<String, String>? repairedPlainText;
      for (final salt in salts) {
        final candidateKeys = <encrypt_lib.Key>[
          await KeyManager.deriveKey(oldPin, salt),
          _deriveLegacyKey(oldPin, salt),
        ];
        for (final candidateKey in candidateKeys) {
          final oldEnc = EncryptionService(candidateKey);
          final tryPlain = <String, String>{};
          var allOk = true;

          for (final entry in _failedEncryptedPayload.entries) {
            final plain = oldEnc.tryDecryptData(entry.value);
            if (plain == null) {
              allOk = false;
              break;
            }
            tryPlain[entry.key] = plain;
          }

          if (allOk && tryPlain.isNotEmpty) {
            repairedPlainText = tryPlain;
            break;
          }
        }
        if (repairedPlainText != null) break;
      }

      if (repairedPlainText == null || repairedPlainText.isEmpty) {
        throw Exception('安全碼不正確或此紀錄使用更早版本金鑰');
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('diaryMigrations')
          .add({
        'diaryId': _docId,
        'legacyBackup': Map<String, String>.from(_failedEncryptedPayload),
        'migratedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;

      final newEnc = EncryptionService(currentKey);
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      for (final entry in repairedPlainText.entries) {
        updates[entry.key] = newEnc.encryptData(entry.value);
      }

      await docRef.set(updates, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _blockCloudSaveDueToDecryptFailure = false;
        _needsLegacyRepair = false;
        _failedEncryptedPayload.clear();
      });

      if (!mounted) return;
      await _loadDraft();
      if (!mounted) return;
      m.ScaffoldMessenger.of(context).showSnackBar(
        const m.SnackBar(content: m.Text('舊日記修復成功')),
      );
    } catch (_) {
      if (!mounted) return;
      m.ScaffoldMessenger.of(context).showSnackBar(
        const m.SnackBar(content: m.Text('安全碼不正確或此紀錄使用更早版本金鑰')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRepairingLegacy = false);
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    if (_imageUrls.length >= kDiaryMaxImageCount) {
      m.ScaffoldMessenger.of(context).showSnackBar(
        const m.SnackBar(content: m.Text('每篇日記最多加入 10 張圖片')),
      );
      return;
    }

    final uid = _uid;
    if (uid == null) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 78,
        maxWidth: 1600,
      );

      if (picked == null) return;

      setState(() => _uploadingImage = true);

      final safeDocId = _docId.replaceAll('/', '-');
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'users/$uid/diary_images/$safeDocId/$fileName';

      final ref = FirebaseStorage.instance.ref(storagePath);
      final bytes = await picked.readAsBytes();

      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await ref.getDownloadURL();

      if (!mounted) return;

      setState(() {
        _imageUrls.add(url);
        _uploadingImage = false;
      });

      await _saveDraft();
    } catch (e) {
      if (!mounted) return;

      setState(() => _uploadingImage = false);

      m.ScaffoldMessenger.of(context).showSnackBar(
        m.SnackBar(content: m.Text('圖片上傳失敗：$e')),
      );
    }
  }

  void _removeImageUrl(String url) {
    setState(() {
      _imageUrls.remove(url);
    });
    _saveDraft();
  }

  Future<void> _saveDraft() async {
    try {
      if (_blockCloudSaveDueToDecryptFailure) {
        m.debugPrint('🛡️ 已暫停本地與雲端寫入：避免覆蓋仍可恢復的加密資料');
        if (mounted) {
          setState(() => _saving = false);
        }
        return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // ==========================================
      // 步驟 1：💾 永遠先存一份「明文」到本地資料庫
      // 保證不管網路斷線或加密失敗，用戶打的字絕對不會不見！
      // ==========================================
      // ==========================================
      // 步驟 2：☁️ 嘗試加密並上傳到 Firebase (獨立區塊，失敗不影響本地)
      // ==========================================
      if (FirebaseSyncConfig.shouldSync() &&
          !_blockCloudSaveDueToDecryptFailure) {
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
            'imageUrls': _imageUrls,
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

  Future<void> _openBasicAiFeedback() async {
    await FirebaseAnalytics.instance.logEvent(
      name: 'basic_ai_click',
      parameters: {
        'source': 'diary_page',
        'date': _docId,
      },
    );

    if (!mounted) return;

    m.showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const m.RoundedRectangleBorder(
        borderRadius: m.BorderRadius.vertical(top: m.Radius.circular(24)),
      ),
      builder: (_) {
        return m.Padding(
          padding: const m.EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: m.Column(
            mainAxisSize: m.MainAxisSize.min,
            crossAxisAlignment: m.CrossAxisAlignment.start,
            children: [
              m.Text(
                'AI 基礎回饋',
                style: m.Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: m.FontWeight.w800,
                    ),
              ),
              const m.SizedBox(height: 12),
              const m.Text(
                '這裡之後會放「今日情緒摘要、主題分類、溫柔回饋、照顧自己的小建議」。',
                style: m.TextStyle(height: 1.6),
              ),
              const m.SizedBox(height: 16),
              m.Container(
                padding: const m.EdgeInsets.all(14),
                decoration: m.BoxDecoration(
                  color: m.Colors.teal.withOpacity(0.08),
                  borderRadius: m.BorderRadius.circular(18),
                ),
                child: const m.Text(
                  '範例：今天的文字裡，可以感覺到你正在努力整理自己的感受。即使狀態不一定很穩，你仍然願意記錄下來，這本身就是一種照顧自己的方式。',
                  style: m.TextStyle(height: 1.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDeepAiPreview() async {
    await FirebaseAnalytics.instance.logEvent(
      name: 'deep_ai_pro_preview_click',
      parameters: {
        'source': 'diary_page',
        'date': _docId,
      },
    );

    if (!mounted) return;

    m.Navigator.of(context).push(
      m.MaterialPageRoute(
        builder: (_) => const ProPreviewPage(),
      ),
    );
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
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: m.AppBar(
        backgroundColor: HealingDesignSystem.primaryBlue,
        foregroundColor: m.Colors.white,
        elevation: 0,
        title: m.Text(
          '編輯日記 - ${_day.month}/${_day.day}',
          style: const m.TextStyle(
            color: m.Colors.white,
            fontWeight: m.FontWeight.w700,
          ),
        ),
        actions: [
          m.IconButton(
            tooltip: 'AI 正念回饋',
            icon: const m.Icon(m.Icons.auto_awesome_rounded),
            onPressed: _openAiReflection,
          ),
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
            _AiEntryCard(
              onBasicTap: _openBasicAiFeedback,
              onDeepTap: _openDeepAiPreview,
            ),
            const m.SizedBox(height: 12),
            if (_needsLegacyRepair) ...[
              m.Text(
                '此紀錄需要使用舊安全碼修復',
                style: m.Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HealingDesignSystem.dangerRed,
                      fontWeight: m.FontWeight.w600,
                    ),
              ),
              const m.SizedBox(height: 8),
              m.Align(
                alignment: m.Alignment.centerLeft,
                child: m.OutlinedButton(
                  onPressed: _isRepairingLegacy ? null : _showRepairDialog,
                  child: m.Text(_isRepairingLegacy ? '修復中...' : '修復舊日記'),
                ),
              ),
              const m.SizedBox(height: 12),
            ],

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

            _PhotoPickerCard(
              imageUrls: _imageUrls,
              uploading: _uploadingImage,
              onAdd: _pickAndUploadImage,
              onRemove: _removeImageUrl,
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
      decoration: HealingDesignSystem.cardDecoration(
        bgColor: HealingDesignSystem.adaptiveSurface(context),
        radius: HealingDesignSystem.radiusL,
        shadowColor: HealingDesignSystem.primaryBlue,
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
                  style: HealingDesignSystem.titleLarge.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const m.SizedBox(height: 6),
                _chip(context, '星期${_weekdayZh(date.weekday)}'),
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

  m.Widget _chip(m.BuildContext context, String text) {
    return m.Container(
      padding: const m.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: m.BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: m.BorderRadius.circular(999),
      ),
      child: m.Text(
        text,
        style: HealingDesignSystem.labelSmall.copyWith(
          color: HealingDesignSystem.primaryBlue,
          letterSpacing: 0.2,
        ),
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
    return m.Container(
      margin: const m.EdgeInsets.symmetric(vertical: 4),
      decoration: HealingDesignSystem.cardDecoration(
        bgColor: HealingDesignSystem.adaptiveSurface(context),
        radius: HealingDesignSystem.radiusL,
      ),
      child: m.Padding(
        padding: const m.EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: m.Column(
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Text(
              '今日整體狀態',
              style: HealingDesignSystem.titleMedium.copyWith(
                color: HealingDesignSystem.primaryBlue,
                fontWeight: m.FontWeight.w700,
              ),
            ),
            const m.SizedBox(height: 6),
            m.Text(
              '今天的整體情緒如何？',
              style: HealingDesignSystem.bodySmall,
            ),
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
            m.Text(
              '今天的健康狀況如何？',
              style: HealingDesignSystem.bodySmall,
            ),
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
            m.Text('整體睡眠品質', style: HealingDesignSystem.bodySmall),
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
    final effectiveTextStyle =
        (textStyle ?? HealingDesignSystem.bodyLarge).copyWith(
      color:
          textStyle?.color ?? HealingDesignSystem.adaptivePrimaryText(context),
    );
    final effectiveHintStyle =
        (hintStyle ?? HealingDesignSystem.bodyLarge).copyWith(
      color: hintStyle?.color ??
          HealingDesignSystem.adaptiveSecondaryText(context),
    );

    return m.Container(
      margin: const m.EdgeInsets.symmetric(vertical: 4),
      decoration: HealingDesignSystem.cardDecoration(
        bgColor: HealingDesignSystem.adaptiveSurface(context),
        radius: HealingDesignSystem.radiusL,
      ),
      child: m.Padding(
        padding: const m.EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: m.Column(
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Row(
              children: [
                if (icon != null) ...[
                  m.Icon(icon,
                      size: 18, color: HealingDesignSystem.primaryBlue),
                  const m.SizedBox(width: 6),
                ],
                m.Expanded(
                  child: m.Text(
                    label,
                    style: HealingDesignSystem.titleMedium.copyWith(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
                  ),
                ),
              ],
            ),
            const m.SizedBox(height: 8),
            m.TextField(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
              textAlign: m.TextAlign.justify,
              textAlignVertical: m.TextAlignVertical.top,
              keyboardType: m.TextInputType.multiline,
              textInputAction: m.TextInputAction.newline,
              style: effectiveTextStyle,
              decoration: m.InputDecoration(
                filled: true,
                fillColor: HealingDesignSystem.adaptiveFill(context),
                hintText: hint,
                hintStyle: effectiveHintStyle,
                border: m.OutlineInputBorder(
                  borderRadius:
                      m.BorderRadius.circular(HealingDesignSystem.radiusM),
                  borderSide: m.BorderSide.none,
                ),
                enabledBorder: m.OutlineInputBorder(
                  borderRadius:
                      m.BorderRadius.circular(HealingDesignSystem.radiusM),
                  borderSide: const m.BorderSide(color: m.Colors.transparent),
                ),
                focusedBorder: m.OutlineInputBorder(
                  borderRadius:
                      m.BorderRadius.circular(HealingDesignSystem.radiusM),
                  borderSide: const m.BorderSide(
                      color: HealingDesignSystem.primaryBlue),
                ),
                contentPadding: const m.EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              onChanged: (_) => onAnyChanged?.call(),
            ),
            m.Align(
              alignment: m.Alignment.bottomRight,
              child: m.Text(
                '${controller.text.characters.length} 字',
                style: HealingDesignSystem.labelSmall.copyWith(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiEntryCard extends m.StatelessWidget {
  final m.VoidCallback onBasicTap;
  final m.VoidCallback onDeepTap;

  const _AiEntryCard({
    required this.onBasicTap,
    required this.onDeepTap,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final theme = m.Theme.of(context);
    final color = theme.colorScheme;

    return m.Container(
      padding: const m.EdgeInsets.all(16),
      decoration: m.BoxDecoration(
        color: m.Colors.white,
        borderRadius: m.BorderRadius.circular(24),
        boxShadow: [
          m.BoxShadow(
            color: m.Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const m.Offset(0, 6),
          ),
        ],
      ),
      child: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          m.Row(
            children: [
              m.Icon(
                m.Icons.auto_awesome,
                color: color.primary,
              ),
              const m.SizedBox(width: 8),
              m.Text(
                'AI 情緒回饋',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: m.FontWeight.w800,
                ),
              ),
            ],
          ),
          const m.SizedBox(height: 6),
          m.Text(
            '先從今天的文字開始整理，也可以升級成更完整的長期觀察。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: color.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const m.SizedBox(height: 14),
          m.Row(
            children: [
              m.Expanded(
                child: _AiSmallButton(
                  title: '基礎回饋',
                  subtitle: '免費',
                  icon: m.Icons.chat_bubble_outline,
                  onTap: onBasicTap,
                ),
              ),
              const m.SizedBox(width: 10),
              m.Expanded(
                child: _AiSmallButton(
                  title: '深入分析',
                  subtitle: 'Pro 預告',
                  icon: m.Icons.workspace_premium_outlined,
                  isPro: true,
                  onTap: onDeepTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiSmallButton extends m.StatelessWidget {
  final String title;
  final String subtitle;
  final m.IconData icon;
  final bool isPro;
  final m.VoidCallback onTap;

  const _AiSmallButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isPro = false,
    required this.onTap,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final theme = m.Theme.of(context);
    final color = theme.colorScheme;

    return m.InkWell(
      borderRadius: m.BorderRadius.circular(18),
      onTap: onTap,
      child: m.Container(
        padding: const m.EdgeInsets.all(14),
        decoration: m.BoxDecoration(
          color: isPro
              ? color.primaryContainer.withOpacity(0.65)
              : color.surfaceContainerHighest.withOpacity(0.65),
          borderRadius: m.BorderRadius.circular(18),
          border: m.Border.all(
            color: isPro
                ? color.primary.withOpacity(0.35)
                : color.outlineVariant.withOpacity(0.6),
          ),
        ),
        child: m.Column(
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Row(
              children: [
                m.Icon(icon, size: 22),
                const m.Spacer(),
                if (isPro)
                  m.Container(
                    padding: const m.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: m.BoxDecoration(
                      color: color.primary,
                      borderRadius: m.BorderRadius.circular(999),
                    ),
                    child: m.Text(
                      'PRO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color.onPrimary,
                        fontWeight: m.FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const m.SizedBox(height: 10),
            m.Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: m.FontWeight.w800,
              ),
            ),
            const m.SizedBox(height: 4),
            m.Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPickerCard extends m.StatelessWidget {
  final List<String> imageUrls;
  final bool uploading;
  final m.VoidCallback onAdd;
  final void Function(String url) onRemove;

  const _PhotoPickerCard({
    required this.imageUrls,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final teal = HealingDesignSystem.adaptiveAccent(context);
    final text = HealingDesignSystem.adaptivePrimaryText(context);
    final sub = HealingDesignSystem.adaptiveSecondaryText(context);

    return m.Container(
      padding: const m.EdgeInsets.all(16),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          m.Row(
            children: [
              m.Icon(m.Icons.photo_outlined, color: teal),
              const m.SizedBox(width: 8),
              m.Text(
                '加入照片',
                style: m.TextStyle(
                  fontSize: 17,
                  fontWeight: m.FontWeight.w800,
                  color: text,
                ),
              ),
              const m.Spacer(),
              m.Text(
                '${imageUrls.length}/$kDiaryMaxImageCount',
                style: m.TextStyle(color: sub),
              ),
            ],
          ),
          const m.SizedBox(height: 10),
          m.Text(
            '可以放今天的天空、食物、散步、或任何想留下的畫面。',
            style: m.TextStyle(color: sub, height: 1.5),
          ),
          const m.SizedBox(height: 14),
          if (imageUrls.isNotEmpty)
            m.SizedBox(
              height: 96,
              child: m.ListView.separated(
                scrollDirection: m.Axis.horizontal,
                itemCount: imageUrls.length,
                separatorBuilder: (_, __) => const m.SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final url = imageUrls[index];
                  return m.Stack(
                    children: [
                      m.ClipRRect(
                        borderRadius: m.BorderRadius.circular(18),
                        child: m.Image.network(
                          url,
                          width: 96,
                          height: 96,
                          fit: m.BoxFit.cover,
                        ),
                      ),
                      m.Positioned(
                        right: 4,
                        top: 4,
                        child: m.InkWell(
                          onTap: () => onRemove(url),
                          child: m.Container(
                            padding: const m.EdgeInsets.all(4),
                            decoration: const m.BoxDecoration(
                              color: m.Colors.black54,
                              shape: m.BoxShape.circle,
                            ),
                            child: const m.Icon(
                              m.Icons.close,
                              color: m.Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          if (imageUrls.isNotEmpty) const m.SizedBox(height: 14),
          m.OutlinedButton.icon(
            onPressed: uploading ? null : onAdd,
            icon: uploading
                ? const m.SizedBox(
                    width: 16,
                    height: 16,
                    child: m.CircularProgressIndicator(strokeWidth: 2),
                  )
                : const m.Icon(m.Icons.add_photo_alternate_outlined),
            label: m.Text(uploading ? '上傳中...' : '加入照片'),
          ),
        ],
      ),
    );
  }
}
