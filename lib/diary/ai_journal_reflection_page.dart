// ai_journal_reflection_page.dart
//
// 心域 App ── AI 正念／感恩日記回饋頁面
//
// Firestore 讀取：
//   users/{uid}/diary/{yyyy-MM-dd}
//   users/{uid}/dailyRecords/{yyyy-MM-dd}
//
// Firestore 寫入：
//   users/{uid}/aiJournalReflections/{yyyy-MM-dd}
//
// ⚠️  OpenAI 串接尚未實作，目前使用 generateMockAIReflection()
//     之後只需替換該函數內容即可，其餘程式碼無需更動。

import 'dart:math';

import 'package:flutter/material.dart' as m;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/secure_storage_service.dart';
import '../utils/encryption_service.dart';

// ──────────────────────────────────────────────
// 主 Widget
// ──────────────────────────────────────────────
class AiJournalReflectionPage extends m.StatefulWidget {
  final DateTime date;
  const AiJournalReflectionPage({super.key, required this.date});

  @override
  m.State<AiJournalReflectionPage> createState() =>
      _AiJournalReflectionPageState();
}

class _AiJournalReflectionPageState
    extends m.State<AiJournalReflectionPage> {
  // ── 顏色主題（藍綠色系）──
  static const _teal = m.Color(0xFF4DB6AC);
  static const _tealLight = m.Color(0xFFB2DFDB);
  static const _tealSurface = m.Color(0xFFF0FAFA);
  static const _tealDark = m.Color(0xFF00897B);
  static const _amber = m.Color(0xFFFFB74D);

  // ── 狀態 ──
  bool _loading = false;           // 正在生成 AI 回饋
  bool _hasSavedResult = false;    // 是否已有儲存的 AI 結果
  String? _error;

  // 從 Firestore 抓到的原始資料
  Map<String, dynamic>? _diaryData;
  Map<String, dynamic>? _dailyRecordData;

  // AI 回饋結果
  Map<String, dynamic>? _aiResult;

  // 危機關鍵字偵測結果
  bool _crisisDetected = false;

  // ── 危機關鍵字 ──
  static const _crisisKeywords = [
    '想死', '不想活', '自殺', '傷害自己', '結束生命',
    '活不下去', '去死', '消失掉', '了結',
  ];

  // ── 便捷 getter ──
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  DateTime get _day =>
      DateTime(widget.date.year, widget.date.month, widget.date.day);
  String get _docId =>
      '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ── 生命週期 ──
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadFirestoreData();
    await _loadExistingAiResult();
  }

  // ──────────────────────────────────────────────
  // Firestore 讀取
  // ──────────────────────────────────────────────

  Future<void> _loadFirestoreData() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final diarySnap = await _db
          .collection('users')
          .doc(uid)
          .collection('diary')
          .doc(_docId)
          .get();

      final recordSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .doc(_docId)
          .get();

      if (!mounted) return;

      // 解密日記文字欄位（若有加密）
      Map<String, dynamic>? diaryData = diarySnap.data();
      if (diaryData != null) {
        try {
          final key = await SecureStorageService.getOrRecoverKey();
          if (key != null) {
            final enc = EncryptionService(key);
            String dec(dynamic v) {
              final s = (v ?? '') as String;
              if (s.contains(':')) {
                return enc.tryDecryptData(s) ?? s;
              }
              return s;
            }

            diaryData = {
              ...diaryData,
              'title': dec(diaryData['title']),
              'content': dec(diaryData['content']),
              'themeSong': dec(diaryData['themeSong']),
              'highlight': dec(diaryData['highlight']),
              'metaphor': dec(diaryData['metaphor']),
              'conceited': dec(diaryData['conceited']),
              'proudOf': dec(diaryData['proudOf']),
              'selfCare': dec(diaryData['selfCare']),
            };
          }
        } catch (decErr) {
          m.debugPrint('⚠️ AiJournalReflectionPage: decrypt error: $decErr');
        }
      }

      setState(() {
        _diaryData = diaryData;
        _dailyRecordData = recordSnap.data();
      });
    } catch (e) {
      m.debugPrint('❌ AiJournalReflectionPage: Firestore read error: $e');
    }
  }

  /// 載入已存的 AI 結果（避免重複生成）
  Future<void> _loadExistingAiResult() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('aiJournalReflections')
          .doc(_docId)
          .get();

      if (snap.exists && mounted) {
        setState(() {
          _aiResult = snap.data();
          _hasSavedResult = true;
          _crisisDetected = snap.data()?['crisisDetected'] == true;
        });
      }
    } catch (e) {
      m.debugPrint('❌ AiJournalReflectionPage: load existing AI result error: $e');
    }
  }

  // ──────────────────────────────────────────────
  // 危機關鍵字偵測
  // ──────────────────────────────────────────────

  bool _detectCrisis(String text) {
    final lower = text;
    return _crisisKeywords.any((kw) => lower.contains(kw));
  }

  // ──────────────────────────────────────────────
  // Mock AI 函數（日後替換為真實 API 呼叫）
  // ──────────────────────────────────────────────

  /// 生成 mock AI 回饋。
  ///
  /// 參數：
  ///   [diaryContent]   日記全文
  ///   [dailyRecord]    情緒、睡眠、症狀等當日紀錄
  ///
  /// 回傳 Map 鍵值：
  ///   summary, emotionObservation, topics (List<String>),
  ///   positiveFeedback, gratitudeQuestions (List<String>),
  ///   tomorrowAction, crisisDetected
  Future<Map<String, dynamic>> generateMockAIReflection({
    required String diaryContent,
    required Map<String, dynamic> dailyRecord,
  }) async {
    // 模擬網路延遲
    await Future.delayed(const Duration(milliseconds: 1200));

    final mood = dailyRecord['overallMood'] ?? dailyRecord['mood'] ?? 5;
    final sleep =
        dailyRecord['overallSleepQuality'] ?? dailyRecord['sleep'] ?? 5;

    // ── Mock 資料庫（隨機挑選增加真實感）──
    final rng = Random();

    final summaries = [
      '今天你記錄了許多生活細節，文字中透著一份細膩與用心。無論今天的感受如何起伏，你願意把它寫下來，本身就是對自己的溫柔。',
      '這篇日記裡藏著你對生活的觀察。你注意到了周遭細微的變化，也誠實地面對自己的感受，這需要很大的勇氣。',
      '今天的文字帶有一種安靜的力量。你沒有迴避自己的情緒，而是選擇與它同在，這正是正念練習最珍貴的地方。',
    ];

    final emotionObservations = [
      '從文字的節奏與用詞來看，今天你可能帶著${mood >= 6 ? "輕盈愉快" : mood >= 4 ? "平靜沉著" : "些許疲憊"}的心情度過這一天。睡眠狀態（${sleep}/10）也在情緒的底色中留下了痕跡。',
      '你的情緒分數（${mood}/10）反映了今天的內在狀態。文字中可以感受到你正在認真整理自己的感受，這種自我覺察本身就很有意義。',
      '今天你的整體情緒${mood >= 7 ? "相當穩定，字裡行間流露著溫暖" : mood >= 5 ? "有些起伏，但你依然選擇好好記錄" : "可能有些低落，但你仍願意提筆，這份堅持值得被看見"}。',
    ];

    final topicSets = [
      ['自我反思', '日常生活', '情緒覺察'],
      ['人際關係', '自我成長', '當下感受'],
      ['工作學習', '自我照顧', '心境轉換'],
      ['日常生活', '自我反思', '感恩'],
    ];

    final positiveFeedbacks = [
      '你今天願意停下來，把心裡的事寫出來，這本身就是照顧自己的一種方式。不論今天發生了什麼，你都走過來了。明天的你，值得被溫柔地期待。🌿',
      '每一篇日記都是你給自己的一份小禮物。你記錄了真實的自己，不加修飾、不評判，這種誠實需要很大的勇氣。繼續這樣對自己溫柔吧。✨',
      '你今天的文字讓我看到一個認真生活的人。生活不一定每天都閃光，但你選擇用文字把它留住，這種珍視當下的態度，正是正念的核心。🌸',
    ];

    final gratitudeSets = [
      [
        '今天有哪一個小瞬間，讓你感到一絲溫暖或安慰？（即使很微小也沒關係）',
        '今天你的身體為你做了什麼？有哪個感官帶給你一點愉悅？',
        '今天有哪件事情，其實比你預想的要順利一些？',
      ],
      [
        '今天你周遭有哪個人，讓你感到被看見或被支持？',
        '如果今天這一天是一種天氣，你覺得它像什麼？這個天氣有沒有什麼你還喜歡的地方？',
        '今天你做了哪件事，讓你覺得「還不錯，我做到了」？',
      ],
      [
        '今天有沒有什麼小事，讓你微微笑了一下，或是心頭一暖？',
        '如果給今天的自己一句話，你想說什麼？',
        '今天有哪個習慣或選擇，是你為自己所做的小小照顧？',
      ],
    ];

    final tomorrowActions = [
      '明天早晨醒來，給自己一分鐘做三次深呼吸，再開始一天。🌬️',
      '明天選擇一個你一直想做但還沒做的「小事」，就算只是泡一杯喜歡的茶。☕',
      '明天試著在某個無聊的等待時刻，留意自己的五感：看到什麼、聽到什麼、聞到什麼。',
      '明天找一個人說一句「謝謝你」，或是在心裡默默感謝某件事。',
      '明天給自己設定一個「15分鐘只屬於自己」的時間，做任何讓你放鬆的事。🎵',
    ];

    final topics = (topicSets..shuffle(rng)).first;
    final gratitudeQs = (gratitudeSets..shuffle(rng)).first;

    return {
      'summary': summaries[rng.nextInt(summaries.length)],
      'emotionObservation': emotionObservations[rng.nextInt(emotionObservations.length)],
      'topics': topics,
      'positiveFeedback': positiveFeedbacks[rng.nextInt(positiveFeedbacks.length)],
      'gratitudeQuestions': gratitudeQs,
      'tomorrowAction': tomorrowActions[rng.nextInt(tomorrowActions.length)],
      'crisisDetected': false, // mock 不觸發，由前端關鍵字偵測處理
      'generatedAt': FieldValue.serverTimestamp(),
      'isMock': true, // 方便日後辨別是 mock 還是真實 API 結果
    };
  }

  Map<String, dynamic> _normalizeAiResult(Map<String, dynamic> raw) {
    return {
      'summary': (raw['summary'] ?? '').toString(),
      'emotionObservation': (raw['emotionObservation'] ?? '').toString(),
      'topics': List<String>.from(raw['topics'] ?? const <String>[]),
      'positiveFeedback': (raw['positiveFeedback'] ?? '').toString(),
      'gratitudeQuestions':
          List<String>.from(raw['gratitudeQuestions'] ?? const <String>[]),
      'tomorrowAction': (raw['tomorrowAction'] ?? '').toString(),
      'crisisDetected': raw['crisisDetected'] == true,
      'isMock': raw['isMock'] == true,
      if (raw['model'] != null) 'model': raw['model'].toString(),
    };
  }

  Future<Map<String, dynamic>> generateAIReflection({
    required String diaryContent,
    required Map<String, dynamic> dailyRecord,
  }) async {
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('generateAiJournalReflection');
      final response = await callable.call({
        'date': _docId,
        'diaryContent': diaryContent,
        'dailyRecord': dailyRecord,
      });

      final data = response.data;
      if (data is! Map) {
        throw const FormatException('AI 回傳格式錯誤');
      }

      return _normalizeAiResult(Map<String, dynamic>.from(data));
    } catch (e) {
      m.debugPrint('⚠️ generateAIReflection fallback to mock: $e');
      return generateMockAIReflection(
        diaryContent: diaryContent,
        dailyRecord: dailyRecord,
      );
    }
  }

  // ──────────────────────────────────────────────
  // 生成並儲存 AI 回饋
  // ──────────────────────────────────────────────

  Future<void> _generateAndSave() async {
    final uid = _uid;
    if (uid == null) {
      _showSnack('請先登入後再使用此功能');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 組裝日記文字（合併所有文字欄位）
      final diaryContent = [
        _diaryData?['title'] ?? '',
        _diaryData?['content'] ?? '',
        _diaryData?['highlight'] ?? '',
        _diaryData?['metaphor'] ?? '',
        _diaryData?['proudOf'] ?? '',
        _diaryData?['selfCare'] ?? '',
      ].where((s) => s.toString().isNotEmpty).join('\n');

      // 危機關鍵字偵測（在呼叫 AI 之前先做，保護使用者）
      final crisis = _detectCrisis(diaryContent);

      // 優先呼叫 Firebase Functions 上的 AI；失敗時回退到 mock
      // dailyRecord 優先用日記頁整體情緒滑桿值覆蓋平均值
      final dailyRecordForAi = {
        if (_dailyRecordData != null) ..._dailyRecordData!,
        if (_diaryData?['overallMood'] != null)
          'overallMood': _diaryData!['overallMood'],
      };
      final result = await generateAIReflection(
        diaryContent: diaryContent,
        dailyRecord: dailyRecordForAi,
      );

      // 把前端偵測到的 crisis 寫回結果
      result['crisisDetected'] = crisis || result['crisisDetected'] == true;
      result['generatedAt'] = FieldValue.serverTimestamp();

      // 儲存到 Firestore
      await _db
          .collection('users')
          .doc(uid)
          .collection('aiJournalReflections')
          .doc(_docId)
          .set(result, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _aiResult = result;
        _hasSavedResult = true;
        _crisisDetected = crisis;
      });
    } catch (e) {
      m.debugPrint('❌ generateAndSave error: $e');
      if (!mounted) return;
      setState(() => _error = '生成時發生錯誤，請稍後再試。\n$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    m.ScaffoldMessenger.of(context).showSnackBar(
      m.SnackBar(content: m.Text(msg)),
    );
  }

  // ──────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────

  @override
  m.Widget build(m.BuildContext context) {
    return m.Scaffold(
      backgroundColor: _tealSurface,
      appBar: _buildAppBar(context),
      body: m.ListView(
        padding: const m.EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ① 今日日記內容
          _DiaryContentCard(
            diaryData: _diaryData,
            teal: _teal,
            tealLight: _tealLight,
          ),
          const m.SizedBox(height: 12),

          // ② 今日情緒與症狀摘要
          _DailyRecordCard(
            recordData: {
              if (_dailyRecordData != null) ..._dailyRecordData!,
              // 優先用日記頁最上方的整體情緒滑桿值
              if (_diaryData?['overallMood'] != null)
                'overallMood': _diaryData!['overallMood'],
            },
            teal: _teal,
            tealLight: _tealLight,
          ),
          const m.SizedBox(height: 16),

          // 生成按鈕 / 載入中指示
          _buildGenerateButton(),
          const m.SizedBox(height: 16),

          // 錯誤訊息
          if (_error != null) _buildErrorCard(),

          // ── AI 結果區塊（有結果才顯示）──
          if (_aiResult != null) ...[
            // 危機警示卡片（優先顯示）
            if (_crisisDetected) ...[
              _CrisisAlertCard(teal: _teal),
              const m.SizedBox(height: 12),
            ],

            // ③ AI 今日摘要
            _AiSectionCard(
              icon: m.Icons.auto_awesome_rounded,
              iconColor: _tealDark,
              title: 'AI 今日摘要',
              tealLight: _tealLight,
              child: _BodyText(_aiResult!['summary'] ?? ''),
            ),
            const m.SizedBox(height: 12),

            // ④ AI 情緒觀察
            _AiSectionCard(
              icon: m.Icons.favorite_border_rounded,
              iconColor: m.Colors.pinkAccent.shade100,
              title: 'AI 情緒觀察',
              tealLight: _tealLight,
              child: _BodyText(_aiResult!['emotionObservation'] ?? ''),
            ),
            const m.SizedBox(height: 12),

            // ⑤ AI 主題分類
            _AiSectionCard(
              icon: m.Icons.label_outline_rounded,
              iconColor: _amber,
              title: 'AI 主題分類',
              tealLight: _tealLight,
              child: _TopicChips(
                topics: List<String>.from(_aiResult!['topics'] ?? []),
                teal: _teal,
              ),
            ),
            const m.SizedBox(height: 12),

            // ⑥ AI 正向回饋
            _AiSectionCard(
              icon: m.Icons.star_border_rounded,
              iconColor: _amber,
              title: 'AI 正向回饋',
              tealLight: _tealLight,
              child: _BodyText(_aiResult!['positiveFeedback'] ?? ''),
            ),
            const m.SizedBox(height: 12),

            // ⑦ 感恩日記引導問題
            _AiSectionCard(
              icon: m.Icons.spa_outlined,
              iconColor: m.Colors.green.shade400,
              title: '感恩日記引導問題',
              tealLight: _tealLight,
              child: _GratitudeQuestions(
                questions:
                    List<String>.from(_aiResult!['gratitudeQuestions'] ?? []),
                teal: _teal,
              ),
            ),
            const m.SizedBox(height: 12),

            // ⑧ 明日小行動
            _AiSectionCard(
              icon: m.Icons.wb_sunny_outlined,
              iconColor: _amber,
              title: '明日小行動',
              tealLight: _tealLight,
              child: _BodyText(_aiResult!['tomorrowAction'] ?? ''),
            ),
            const m.SizedBox(height: 12),

            // 儲存時間標記
            _buildSavedBadge(),
          ],
        ],
      ),
    );
  }

  // ── AppBar ──
  m.AppBar _buildAppBar(m.BuildContext context) {
    return m.AppBar(
      backgroundColor: _teal,
      foregroundColor: m.Colors.white,
      elevation: 0,
      centerTitle: false,
      title: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          const m.Text(
            'AI 正念回饋',
            style: m.TextStyle(
              fontSize: 17,
              fontWeight: m.FontWeight.w700,
              color: m.Colors.white,
            ),
          ),
          m.Text(
            '${ _day.year }年${ _day.month }月${ _day.day }日',
            style: const m.TextStyle(
              fontSize: 12,
              color: m.Colors.white70,
            ),
          ),
        ],
      ),
      actions: [
        if (_hasSavedResult)
          m.Padding(
            padding: const m.EdgeInsets.only(right: 12),
            child: m.Chip(
              label: const m.Text('已儲存',
                  style: m.TextStyle(fontSize: 11, color: m.Colors.white)),
              backgroundColor: m.Colors.white24,
              side: m.BorderSide.none,
              padding: m.EdgeInsets.zero,
              visualDensity: m.VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  // ── 生成按鈕 ──
  m.Widget _buildGenerateButton() {
    if (_loading) {
      return m.Card(
        elevation: 0,
        color: _tealLight.withValues(alpha: 0.5),
        shape: m.RoundedRectangleBorder(
            borderRadius: m.BorderRadius.circular(20)),
        child: m.Padding(
          padding: const m.EdgeInsets.symmetric(vertical: 20),
          child: m.Column(
            children: [
              m.CircularProgressIndicator(color: _tealDark, strokeWidth: 2.5),
              const m.SizedBox(height: 12),
              m.Text(
                'AI 正在為你生成今日回饋…',
                style: m.TextStyle(color: _tealDark, fontSize: 14),
              ),
              const m.SizedBox(height: 4),
              m.Text(
                '這通常需要幾秒鐘，請稍候 🌿',
                style: m.TextStyle(
                    color: _tealDark.withValues(alpha: 0.7), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return m.SizedBox(
      width: double.infinity,
      child: m.FilledButton.icon(
        style: m.FilledButton.styleFrom(
          backgroundColor: _teal,
          foregroundColor: m.Colors.white,
          padding: const m.EdgeInsets.symmetric(vertical: 14),
          shape: m.RoundedRectangleBorder(
              borderRadius: m.BorderRadius.circular(16)),
        ),
        onPressed: _generateAndSave,
        icon: const m.Icon(m.Icons.auto_awesome_rounded, size: 20),
        label: m.Text(
          _hasSavedResult ? '重新生成 AI 回饋' : '生成今日 AI 回饋',
          style: const m.TextStyle(fontSize: 15, fontWeight: m.FontWeight.w600),
        ),
      ),
    );
  }

  // ── 錯誤卡片 ──
  m.Widget _buildErrorCard() {
    return m.Card(
      color: m.Colors.red.shade50,
      shape:
          m.RoundedRectangleBorder(borderRadius: m.BorderRadius.circular(16)),
      margin: const m.EdgeInsets.only(bottom: 16),
      child: m.Padding(
        padding: const m.EdgeInsets.all(16),
        child: m.Row(
          children: [
            const m.Icon(m.Icons.error_outline_rounded,
                color: m.Colors.red, size: 20),
            const m.SizedBox(width: 10),
            m.Expanded(
              child: m.Text(
                _error!,
                style:
                    const m.TextStyle(color: m.Colors.red, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 已儲存標記 ──
  m.Widget _buildSavedBadge() {
    return m.Padding(
      padding: const m.EdgeInsets.only(top: 4),
      child: m.Row(
        mainAxisAlignment: m.MainAxisAlignment.center,
        children: [
          m.Icon(m.Icons.check_circle_outline_rounded,
              color: _teal, size: 16),
          const m.SizedBox(width: 6),
          m.Text(
            '已儲存至雲端  •  $_docId',
            style: m.TextStyle(
                fontSize: 12, color: m.Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// ① 今日日記內容卡片
// ──────────────────────────────────────────────
class _DiaryContentCard extends m.StatelessWidget {
  final Map<String, dynamic>? diaryData;
  final m.Color teal;
  final m.Color tealLight;

  const _DiaryContentCard({
    required this.diaryData,
    required this.teal,
    required this.tealLight,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final content = diaryData?['content'] as String? ?? '';
    final title = diaryData?['title'] as String? ?? '';
    final highlight = diaryData?['highlight'] as String? ?? '';

    return _BaseCard(
      tealLight: tealLight,
      child: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: m.Icons.book_outlined,
            iconColor: teal,
            title: '今日日記',
          ),
          if (title.isNotEmpty) ...[
            const m.SizedBox(height: 8),
            m.Text(
              title,
              style: const m.TextStyle(
                  fontSize: 16, fontWeight: m.FontWeight.w700),
            ),
          ],
          if (content.isNotEmpty) ...[
            const m.SizedBox(height: 8),
            m.Text(
              content,
              style: m.TextStyle(
                  fontSize: 14, height: 1.65, color: m.Colors.grey.shade700),
            ),
          ],
          if (highlight.isNotEmpty) ...[
            const m.SizedBox(height: 10),
            m.Container(
              padding: const m.EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: m.BoxDecoration(
                color: tealLight.withValues(alpha: 0.5),
                borderRadius: m.BorderRadius.circular(10),
              ),
              child: m.Row(
                crossAxisAlignment: m.CrossAxisAlignment.start,
                children: [
                  const m.Text('✨ ', style: m.TextStyle(fontSize: 14)),
                  m.Expanded(
                    child: m.Text(
                      highlight,
                      style: m.TextStyle(
                          fontSize: 13,
                          color: m.Colors.teal.shade700,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (diaryData == null || (title.isEmpty && content.isEmpty))
            _EmptyHint(text: '今天還沒有日記內容，請先前往日記頁面記錄你的一天。'),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// ② 今日情緒與症狀摘要卡片
// ──────────────────────────────────────────────
class _DailyRecordCard extends m.StatelessWidget {
  final Map<String, dynamic>? recordData;
  final m.Color teal;
  final m.Color tealLight;

  const _DailyRecordCard({
    required this.recordData,
    required this.teal,
    required this.tealLight,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return _BaseCard(
      tealLight: tealLight,
      child: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: m.Icons.monitor_heart_outlined,
            iconColor: teal,
            title: '今日情緒與症狀摘要',
          ),
          const m.SizedBox(height: 10),
          if (recordData == null || recordData!.isEmpty)
            _EmptyHint(text: '今天尚無情緒與症狀紀錄。')
          else
            _RecordGrid(data: recordData!, teal: teal),
        ],
      ),
    );
  }
}

class _RecordGrid extends m.StatelessWidget {
  final Map<String, dynamic> data;
  final m.Color teal;

  const _RecordGrid({required this.data, required this.teal});

  @override
  m.Widget build(m.BuildContext context) {
    // 常見欄位映射
    final fields = <String, _RecordFieldMeta>{
      'overallMood': _RecordFieldMeta('整體情緒', m.Icons.sentiment_satisfied_alt_rounded),
      'mood': _RecordFieldMeta('今日情緒', m.Icons.mood_rounded),
      'overallHealth': _RecordFieldMeta('健康狀況', m.Icons.favorite_border_rounded),
      'overallSleepQuality': _RecordFieldMeta('睡眠品質', m.Icons.bedtime_outlined),
      'sleep': _RecordFieldMeta('睡眠', m.Icons.bedtime_outlined),
      'anxiety': _RecordFieldMeta('焦慮', m.Icons.psychology_outlined),
      'energy': _RecordFieldMeta('能量', m.Icons.bolt_rounded),
      'medication': _RecordFieldMeta('藥物', m.Icons.medication_outlined),
    };

    final items = <m.Widget>[];

    for (final entry in fields.entries) {
      final val = data[entry.key];
      if (val == null) continue;
      items.add(_ScoreChip(
        label: entry.value.label,
        icon: entry.value.icon,
        value: val.toString(),
        teal: teal,
      ));
    }

    // 症狀列表
    final symptoms = data['symptoms'];
    if (symptoms is List && symptoms.isNotEmpty) {
      items.add(
        m.Padding(
          padding: const m.EdgeInsets.only(top: 8),
          child: m.Column(
            crossAxisAlignment: m.CrossAxisAlignment.start,
            children: [
              m.Row(
                children: [
                  m.Icon(m.Icons.warning_amber_rounded,
                      size: 16, color: m.Colors.orange.shade400),
                  const m.SizedBox(width: 5),
                  const m.Text('症狀',
                      style: m.TextStyle(
                          fontSize: 12, fontWeight: m.FontWeight.w600)),
                ],
              ),
              const m.SizedBox(height: 4),
              m.Wrap(
                spacing: 6,
                runSpacing: 4,
                children: symptoms
                    .map(
                      (s) => m.Chip(
                        label: m.Text(s.toString(),
                            style: const m.TextStyle(fontSize: 11)),
                        materialTapTargetSize:
                            m.MaterialTapTargetSize.shrinkWrap,
                        padding: m.EdgeInsets.zero,
                        visualDensity: m.VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) return _EmptyHint(text: '尚無可顯示的紀錄欄位。');

    return m.Wrap(spacing: 8, runSpacing: 8, children: items);
  }
}

class _RecordFieldMeta {
  final String label;
  final m.IconData icon;
  const _RecordFieldMeta(this.label, this.icon);
}

class _ScoreChip extends m.StatelessWidget {
  final String label;
  final m.IconData icon;
  final String value;
  final m.Color teal;

  const _ScoreChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.teal,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return m.Container(
      padding:
          const m.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: m.BoxDecoration(
        color: teal.withValues(alpha: 0.1),
        borderRadius: m.BorderRadius.circular(12),
        border: m.Border.all(color: teal.withValues(alpha: 0.25)),
      ),
      child: m.Row(
        mainAxisSize: m.MainAxisSize.min,
        children: [
          m.Icon(icon, size: 14, color: teal),
          const m.SizedBox(width: 5),
          m.Text(label,
              style: m.TextStyle(
                  fontSize: 12,
                  color: m.Colors.grey.shade700)),
          const m.SizedBox(width: 4),
          m.Text(
            value,
            style: m.TextStyle(
                fontSize: 13,
                fontWeight: m.FontWeight.w700,
                color: teal),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// AI 通用 Section 卡片
// ──────────────────────────────────────────────
class _AiSectionCard extends m.StatelessWidget {
  final m.IconData icon;
  final m.Color iconColor;
  final String title;
  final m.Color tealLight;
  final m.Widget child;

  const _AiSectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.tealLight,
    required this.child,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return _BaseCard(
      tealLight: tealLight,
      child: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          _SectionHeader(icon: icon, iconColor: iconColor, title: title),
          const m.SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// ⑤ 主題分類 Chips
// ──────────────────────────────────────────────
class _TopicChips extends m.StatelessWidget {
  final List<String> topics;
  final m.Color teal;

  const _TopicChips({required this.topics, required this.teal});

  static const _topicColors = <String, m.Color>{
    '人際關係': m.Color(0xFFEF9A9A),
    '工作學習': m.Color(0xFF90CAF9),
    '自我反思': m.Color(0xFFA5D6A7),
    '自我成長': m.Color(0xFF80DEEA),
    '自我照顧': m.Color(0xFFC5E1A5),
    '感恩': m.Color(0xFFFFCC80),
    '日常生活': m.Color(0xFFB39DDB),
    '情緒覺察': m.Color(0xFFF48FB1),
    '當下感受': m.Color(0xFF80CBC4),
    '心境轉換': m.Color(0xFFFFAB91),
  };

  @override
  m.Widget build(m.BuildContext context) {
    if (topics.isEmpty) return _EmptyHint(text: '未偵測到明確主題。');
    return m.Wrap(
      spacing: 8,
      runSpacing: 6,
      children: topics.map((t) {
        final color = _topicColors[t] ?? teal.withValues(alpha: 0.3);
        return m.Container(
          padding: const m.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: m.BoxDecoration(
            color: color.withValues(alpha: 0.25),
            borderRadius: m.BorderRadius.circular(999),
            border: m.Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: m.Text(
            '# $t',
            style: m.TextStyle(
              fontSize: 13,
              fontWeight: m.FontWeight.w600,
              color: m.HSLColor.fromColor(color)
                  .withLightness(0.3)
                  .toColor(),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ──────────────────────────────────────────────
// ⑦ 感恩日記引導問題
// ──────────────────────────────────────────────
class _GratitudeQuestions extends m.StatelessWidget {
  final List<String> questions;
  final m.Color teal;

  const _GratitudeQuestions(
      {required this.questions, required this.teal});

  @override
  m.Widget build(m.BuildContext context) {
    if (questions.isEmpty) return _EmptyHint(text: '無引導問題。');
    return m.Column(
      crossAxisAlignment: m.CrossAxisAlignment.start,
      children: questions.asMap().entries.map((e) {
        return m.Padding(
          padding: const m.EdgeInsets.only(bottom: 10),
          child: m.Row(
            crossAxisAlignment: m.CrossAxisAlignment.start,
            children: [
              m.Container(
                width: 24,
                height: 24,
                margin: const m.EdgeInsets.only(top: 1, right: 10),
                decoration: m.BoxDecoration(
                  color: teal,
                  shape: m.BoxShape.circle,
                ),
                child: m.Center(
                  child: m.Text(
                    '${e.key + 1}',
                    style: const m.TextStyle(
                        fontSize: 12,
                        fontWeight: m.FontWeight.w700,
                        color: m.Colors.white),
                  ),
                ),
              ),
              m.Expanded(
                child: m.Text(
                  e.value,
                  style: m.TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: m.Colors.grey.shade700),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ──────────────────────────────────────────────
// 危機警示卡片
// ──────────────────────────────────────────────
class _CrisisAlertCard extends m.StatelessWidget {
  final m.Color teal;
  const _CrisisAlertCard({required this.teal});

  @override
  m.Widget build(m.BuildContext context) {
    return m.Card(
      elevation: 2,
      color: const m.Color(0xFFFFF3E0),
      shape:
          m.RoundedRectangleBorder(borderRadius: m.BorderRadius.circular(20)),
      child: m.Padding(
        padding: const m.EdgeInsets.all(16),
        child: m.Column(
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Row(
              children: [
                m.Icon(m.Icons.favorite_rounded,
                    color: m.Colors.red.shade400, size: 22),
                const m.SizedBox(width: 8),
                const m.Expanded(
                  child: m.Text(
                    '我注意到你今天有些沉重的感受',
                    style: m.TextStyle(
                      fontSize: 15,
                      fontWeight: m.FontWeight.w700,
                      color: m.Color(0xFFB71C1C),
                    ),
                  ),
                ),
              ],
            ),
            const m.SizedBox(height: 8),
            const m.Text(
              '你不需要一個人承擔。每一個人的感受都值得被認真對待，\n專業的支持隨時都在你身邊。',
              style: m.TextStyle(fontSize: 13, height: 1.6, color: m.Color(0xFF4E342E)),
            ),
            const m.SizedBox(height: 14),
            _CrisisContactTile(
              emoji: '💛',
              label: '1925 安心專線',
              subtitle: '24小時・免費・保密',
              phone: 'tel:1925',
            ),
            const m.SizedBox(height: 8),
            _CrisisContactTile(
              emoji: '🚑',
              label: '119 緊急救護',
              subtitle: '生命有立即危險時請撥打',
              phone: 'tel:119',
            ),
            const m.SizedBox(height: 8),
            _CrisisContactTile(
              emoji: '🚔',
              label: '110 警察報案',
              subtitle: '需要到場協助時請撥打',
              phone: 'tel:110',
            ),
          ],
        ),
      ),
    );
  }
}

class _CrisisContactTile extends m.StatelessWidget {
  final String emoji;
  final String label;
  final String subtitle;
  final String phone;

  const _CrisisContactTile({
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.phone,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return m.Material(
      color: m.Colors.white,
      borderRadius: m.BorderRadius.circular(12),
      child: m.InkWell(
        borderRadius: m.BorderRadius.circular(12),
        onTap: () async {
          final uri = Uri.parse(phone);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        },
        child: m.Padding(
          padding:
              const m.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: m.Row(
            children: [
              m.Text(emoji, style: const m.TextStyle(fontSize: 20)),
              const m.SizedBox(width: 10),
              m.Expanded(
                child: m.Column(
                  crossAxisAlignment: m.CrossAxisAlignment.start,
                  children: [
                    m.Text(label,
                        style: const m.TextStyle(
                            fontSize: 14,
                            fontWeight: m.FontWeight.w700,
                            color: m.Color(0xFFB71C1C))),
                    m.Text(subtitle,
                        style: m.TextStyle(
                            fontSize: 11,
                            color: m.Colors.grey.shade600)),
                  ],
                ),
              ),
              m.Icon(m.Icons.phone_outlined,
                  size: 18, color: m.Colors.red.shade300),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 共用小元件
// ──────────────────────────────────────────────

/// 通用卡片底座
class _BaseCard extends m.StatelessWidget {
  final m.Color tealLight;
  final m.Widget child;

  const _BaseCard({required this.tealLight, required this.child});

  @override
  m.Widget build(m.BuildContext context) {
    return m.Card(
      elevation: 1.5,
      shadowColor: m.Colors.black12,
      color: m.Theme.of(context).cardColor,
      shape:
          m.RoundedRectangleBorder(borderRadius: m.BorderRadius.circular(20)),
      child: m.Padding(
        padding: const m.EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: child,
      ),
    );
  }
}

/// Section 標題列
class _SectionHeader extends m.StatelessWidget {
  final m.IconData icon;
  final m.Color iconColor;
  final String title;

  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return m.Row(
      children: [
        m.Icon(icon, size: 20, color: iconColor),
        const m.SizedBox(width: 8),
        m.Text(
          title,
          style: m.Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: m.FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

/// 一般內文
class _BodyText extends m.StatelessWidget {
  final String text;
  const _BodyText(this.text);

  @override
  m.Widget build(m.BuildContext context) {
    if (text.isEmpty) return _EmptyHint(text: '無內容。');
    return m.Text(
      text,
      style: m.TextStyle(
          fontSize: 14, height: 1.7, color: m.Colors.grey.shade700),
      textAlign: m.TextAlign.justify,
    );
  }
}

/// 空內容提示
class _EmptyHint extends m.StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  m.Widget build(m.BuildContext context) {
    return m.Padding(
      padding: const m.EdgeInsets.symmetric(vertical: 6),
      child: m.Text(
        text,
        style: m.TextStyle(
            fontSize: 13,
            color: m.Colors.grey.shade400,
            fontStyle: m.FontStyle.italic),
      ),
    );
  }
}
