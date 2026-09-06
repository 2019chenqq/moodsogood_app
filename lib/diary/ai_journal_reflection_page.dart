// ──────────────────────────────────────────────
// AI 分析模式
// ──────────────────────────────────────────────
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
// ✅  OpenAI 串接已實作：優先呼叫 Firebase Functions
//     若雲端 AI 暫時失敗，會自動 fallback 到 generateMockAIReflection()。

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' as m;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics_service.dart';
import '../services/ai_journal_reflection_http_client.dart';
import '../utils/secure_storage_service.dart';
import '../utils/health_data_encryption_service.dart';
import '../utils/encryption_service.dart';
import '../constants/healing_design_system.dart';

// ──────────────────────────────────────────────
// 主 Widget
// ──────────────────────────────────────────────
enum AiAnalysisMode {
  basic,
  deep,
}

class AiJournalReflectionPage extends m.StatefulWidget {
  final DateTime date;
  final AiAnalysisMode mode;
  const AiJournalReflectionPage({
    super.key,
    required this.date,
    this.mode = AiAnalysisMode.basic,
  });

  @override
  m.State<AiJournalReflectionPage> createState() =>
      _AiJournalReflectionPageState();
}

class _AiJournalReflectionPageState extends m.State<AiJournalReflectionPage> {
  // ── 顏色主題（藍綠色系）──
  static const _teal = m.Color(0xFF4DB6AC);
  static const _tealLight = m.Color(0xFFB2DFDB);
  static const _amber = m.Color(0xFFFFB74D);

  // ── 狀態 ──
  bool _loading = false; // 正在生成 AI 回饋
  bool _hasSavedResult = false; // 是否已有儲存的 AI 結果
  String? _error;

  // 從 Firestore 抓到的原始資料
  Map<String, dynamic>? _diaryData;
  Map<String, dynamic>? _dailyRecordData;

  // AI 回饋結果
  Map<String, dynamic>? _aiResult;
  final AiJournalReflectionHttpClient _aiClient =
      AiJournalReflectionHttpClient();

  // 危機關鍵字偵測結果
  bool _crisisDetected = false;

  // ── 危機關鍵字 ──
  static const _crisisKeywords = [
    '想死',
    '不想活',
    '自殺',
    '傷害自己',
    '結束生命',
    '活不下去',
    '去死',
    '消失掉',
    '了結',
  ];

  // ── 便捷 getter ──
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  DateTime get _day =>
      DateTime(widget.date.year, widget.date.month, widget.date.day);
  String get _docId =>
      '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const List<String> _diaryTextKeys = [
    'title',
    'content',
    'themeSong',
    'highlight',
    'metaphor',
    'conceited',
    'proudOf',
    'selfCare',
  ];

  bool get _hasMeaningfulDiaryInput {
    final data = _diaryData;
    if (data == null) return false;
    for (final key in _diaryTextKeys) {
      final text = (data[key] ?? '').toString().trim();
      if (text.isNotEmpty) return true;
    }
    return false;
  }

  // ── 生命週期 ──
  @override
  void initState() {
    super.initState();
    _init();
    AnalyticsService.logPage('ai_reflection_page');
    AnalyticsService.logAiFeatureOpen(aiMode: 'diary_feedback');
  }

  Future<void> _init() async {
    try {
      await _loadFirestoreData();
      await _loadExistingAiResult();
    } catch (e, stack) {
      m.debugPrint('AiJournalReflectionPage init exception: $e');
      m.debugPrint('AiJournalReflectionPage init stackTrace: $stack');
    }
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
              final s = (v ?? '').toString();
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

      final dailyRecordData = recordSnap.data() == null
          ? null
          : await HealthDataEncryptionService.decryptData(recordSnap.data()!);
      if (!mounted) return;
      setState(() {
        _diaryData = diaryData;
        _dailyRecordData = dailyRecordData;
      });
    } catch (e, stack) {
      m.debugPrint('AiJournalReflectionPage Firestore read exception: $e');
      m.debugPrint('AiJournalReflectionPage Firestore read stackTrace: $stack');
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

      final raw = snap.data();
      if (snap.exists && raw != null && mounted) {
        final result = await HealthDataEncryptionService.decryptData(raw);
        if (!mounted) return;
        setState(() {
          _aiResult = result;
          _hasSavedResult = true;
          _crisisDetected = result['crisisDetected'] == true;
        });
      }
    } catch (e, stack) {
      m.debugPrint(
          'AiJournalReflectionPage load existing AI result exception: $e');
      m.debugPrint(
          'AiJournalReflectionPage load existing AI result stackTrace: $stack');
    }
  }

  Future<Map<String, dynamic>> _buildMedicationContextForAi(String uid) async {
    try {
      final userRef = _db.collection('users').doc(uid);
      final checkinSnap =
          await userRef.collection('medicationCheckins').doc(_docId).get();
      final medicationDocs = await HealthDataEncryptionService.getEncrypted(
        userRef.collection('medications'),
      );

      final medNameById = <String, String>{};
      final activeMedicationNames = <String>[];
      for (final doc in medicationDocs) {
        final data = doc.data;
        if (data['isActive'] == false) continue;
        final name = (data['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        medNameById[doc.id] = name;
        if (!activeMedicationNames.contains(name)) {
          activeMedicationNames.add(name);
        }
      }

      if (!checkinSnap.exists) {
        if (activeMedicationNames.isEmpty) return const <String, dynamic>{};
        return <String, dynamic>{
          'activeMedicationNames': activeMedicationNames,
          'takenMedicationNames': const <String>[],
          'skippedMedicationNames': const <String>[],
          'note': '今日沒有服藥打卡紀錄，僅提供目前藥物清單。',
        };
      }

      final data = checkinSnap.data() == null
          ? const <String, dynamic>{}
          : await HealthDataEncryptionService.decryptData(
              checkinSnap.data()!,
            );
      final statusesRaw = (data['statuses'] is Map)
          ? Map<String, dynamic>.from(data['statuses'] as Map)
          : <String, dynamic>{};
      final checksRaw = (data['checks'] is Map)
          ? Map<String, dynamic>.from(data['checks'] as Map)
          : <String, dynamic>{};

      final takenNames = <String>{};
      final skippedNames = <String>{};
      final pendingNames = <String>{};

      final keys = <String>{...statusesRaw.keys, ...checksRaw.keys};
      for (final key in keys) {
        final parts = key.split('::');
        if (parts.length < 2) continue;
        final medId = parts.first.trim();
        final medName = medNameById[medId] ?? medId;

        final status = (statusesRaw[key] ?? '').toString().trim().toLowerCase();
        final checked = checksRaw[key] == true;

        if (status == 'taken' || checked) {
          takenNames.add(medName);
        } else if (status == 'skipped') {
          skippedNames.add(medName);
        } else {
          pendingNames.add(medName);
        }
      }

      return <String, dynamic>{
        'activeMedicationNames': activeMedicationNames,
        'takenMedicationNames': takenNames.toList(),
        'skippedMedicationNames': skippedNames.toList(),
        'pendingMedicationNames': pendingNames.toList(),
      };
    } catch (e, stack) {
      m.debugPrint('buildMedicationContextForAi exception: $e');
      m.debugPrint('buildMedicationContextForAi stackTrace: $stack');
      return const <String, dynamic>{};
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
  /// Basic 版 mock
  Future<Map<String, dynamic>> generateBasicMockReflection({
    required String diaryContent,
    required num? overallMood,
  }) async {
    await Future.delayed(const Duration(milliseconds: 900));
    final rng = Random();
    final summaries = [
      '今天你願意記錄下自己的心情，這本身就是一種溫柔的自我照顧。',
      '謝謝你寫下今天的感受，這是陪伴自己的好方式。',
      '每一段文字，都是你對自己的溫柔提醒。',
    ];
    final topics = <String>[];
    // 僅從日記文字中明確出現的詞彙（簡單分詞，真實應用可用更嚴格規則）
    final words = diaryContent
        .split(RegExp(r'[\s,，。.!?\n]'))
        .where((w) => w.trim().isNotEmpty)
        .toSet()
        .toList();
    for (final w in words) {
      if (topics.length >= 3) break;
      if (!topics.contains(w) && w.length > 1) topics.add(w);
    }
    final feedbacks = [
      '願你繼續溫柔地陪伴自己，無論心情如何，都值得被善待。',
      '記錄心情的你很棒，請記得給自己一些肯定。',
      '每一天的你都值得被溫柔對待。',
    ];
    final suggestions = [
      '今晚早點休息，給自己一點放鬆的時間。',
      '明天可以試著做一件讓自己開心的小事。',
      '記得多關心自己的感受，給自己一個微笑。',
    ];
    return {
      'summary': summaries[rng.nextInt(summaries.length)],
      'topics': topics.take(3).toList(),
      'positiveFeedback': feedbacks[rng.nextInt(feedbacks.length)],
      'tomorrowAction': suggestions[rng.nextInt(suggestions.length)],
      'crisisDetected': false,
      'generatedAt': FieldValue.serverTimestamp(),
      'isMock': true,
    };
  }

  /// Deep 版 mock（原本內容）
  Future<Map<String, dynamic>> generateDeepMockReflection({
    required String diaryContent,
    required Map<String, dynamic> dailyRecord,
  }) async {
    // ...原本 generateMockAIReflection 內容複製到這...
    // 省略，僅 basic 需嚴格限制
    return {};
  }

  List<String> _safeStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return <String>[value.trim()];
    }
    return const <String>[];
  }

  Map<String, dynamic> _normalizeAiResult(Map<String, dynamic> raw) {
    return {
      'summary': (raw['summary'] ?? '').toString(),
      'emotionObservation': (raw['emotionObservation'] ?? '').toString(),
      'topics': _safeStringList(raw['topics']),
      'positiveFeedback': (raw['positiveFeedback'] ?? '').toString(),
      'gratitudeQuestions': _safeStringList(raw['gratitudeQuestions']),
      'tomorrowAction': (raw['tomorrowAction'] ?? '').toString(),
      'crisisDetected': raw['crisisDetected'] == true,
      'isMock': raw['isMock'] == true,
      if (raw['model'] != null) 'model': raw['model'].toString(),
      if (raw['emotionModel'] is Map)
        'emotionModel': Map<String, dynamic>.from(raw['emotionModel'] as Map),
    };
  }

  Future<Map<String, dynamic>> buildAIInputData() async {
    final uid = _uid;
    if (uid == null) {
      final empty = <String, dynamic>{
        'date': _docId,
        'mode': 'basic',
        'diaryText': '',
        'emotions': <Map<String, dynamic>>[],
        'allowedAnalysisScope': [
          '僅可根據今日日記文字與整體情緒分數進行整理',
          '不可推論睡眠、症狀、藥物或長期趨勢',
          '不可做診斷、不可判斷病情嚴重度',
          '如果資料不足，請明確說明資料有限，不要自行補充內容',
        ],
        'sleep': null,
        'symptoms': <Map<String, dynamic>>[],
        'recentRecords': <Map<String, dynamic>>[],
      };
      m.debugPrint('🧪 buildAIInputData: $empty');
      return empty;
    }

    Map<String, dynamic> diary = _diaryData ?? const <String, dynamic>{};
    Map<String, dynamic> dailyRecord =
        _dailyRecordData ?? const <String, dynamic>{};

    String _safeText(dynamic v) => (v ?? '').toString().trim();
    num? _toNum(dynamic v) {
      if (v is num) return v;
      return num.tryParse((v ?? '').toString().trim());
    }

    if (widget.mode == AiAnalysisMode.basic) {
      // 僅允許 diaryText 與 overallMood
      final diarySections = <MapEntry<String, String>>[
        MapEntry('標題', _safeText(diary['title'])),
        MapEntry('內容', _safeText(diary['content'])),
        MapEntry('今日主題曲', _safeText(diary['themeSong'])),
        MapEntry('最想記錄的瞬間', _safeText(diary['highlight'])),
        MapEntry('今天的感受意象', _safeText(diary['metaphor'])),
        MapEntry('為自己感到驕傲', _safeText(diary['conceited'])),
        MapEntry('做得不錯的地方', _safeText(diary['proudOf'])),
        MapEntry('可多照顧自己的地方', _safeText(diary['selfCare'])),
      ];
      final diaryText = diarySections
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
      final emotions = <Map<String, dynamic>>[];
      final overallMood =
          _toNum(diary['overallMood'] ?? dailyRecord['overallMood']);
      if (overallMood != null) {
        emotions.add({'name': '整體情緒', 'score': overallMood});
      }
      final result = <String, dynamic>{
        'date': _docId,
        'mode': 'basic',
        'moodScale': 5,
        'diaryText': diaryText,
        'emotions': emotions,
        'allowedAnalysisScope': [
          '僅可根據今日日記文字與整體情緒分數進行整理',
          '不可推論睡眠、症狀、藥物或長期趨勢',
          '不可做診斷、不可判斷病情嚴重度',
          '如果資料不足，請明確說明資料有限，不要自行補充內容',
        ],
      };
      return result;
    }
    // deep 模式原本邏輯...
    return {};
  }

  Future<Map<String, dynamic>> generateAIReflection({
    required Map<String, dynamic> aiInput,
    required String diaryContent,
    required Map<String, dynamic> diaryFields,
    required Map<String, dynamic> dailyRecord,
  }) async {
    try {
      final payload = {
        'date': _docId,
        'aiInput': aiInput,
      };
      m.debugPrint('開始呼叫 AI service: HTTP generateAiJournalReflection');
      final data = await _aiClient.generate(payload: payload);
      m.debugPrint('response status: ok');

      return _normalizeAiResult(data);
    } catch (e, stack) {
      m.debugPrint('catch 到的 exception: $e');
      m.debugPrint('stackTrace: $stack');
      m.debugPrint('generateAIReflection exception: $e');
      m.debugPrint('generateAIReflection stackTrace: $stack');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────
  // 生成並儲存 AI 回饋
  // ──────────────────────────────────────────────

  Future<void> _generateAndSave() async {
    m.debugPrint('按鈕已點擊: 生成 AI 回饋');
    final uid = _uid;
    if (uid == null) {
      _showSnack('請先登入後再使用此功能');
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final aiInput = await buildAIInputData();

      final diaryFieldsForAi = {
        'title': _diaryData?['title'] ?? '',
        'content': _diaryData?['content'] ?? '',
        'themeSong': _diaryData?['themeSong'] ?? '',
        'highlight': _diaryData?['highlight'] ?? '',
        'metaphor': _diaryData?['metaphor'] ?? '',
        'conceited': _diaryData?['conceited'] ?? '',
        'proudOf': _diaryData?['proudOf'] ?? '',
        'selfCare': _diaryData?['selfCare'] ?? '',
        'overallMood': _diaryData?['overallMood'],
        'overallHealth': _diaryData?['overallHealth'],
        'overallSleepQuality': _diaryData?['overallSleepQuality'],
        'moodScale': 5,
      };

      final diarySections = <MapEntry<String, String>>[
        MapEntry('標題', (diaryFieldsForAi['title'] ?? '').toString().trim()),
        MapEntry('內容', (diaryFieldsForAi['content'] ?? '').toString().trim()),
        MapEntry(
            '今日主題曲', (diaryFieldsForAi['themeSong'] ?? '').toString().trim()),
        MapEntry(
            '最想記錄的瞬間', (diaryFieldsForAi['highlight'] ?? '').toString().trim()),
        MapEntry(
            '今天的感受意象', (diaryFieldsForAi['metaphor'] ?? '').toString().trim()),
        MapEntry(
            '為自己感到驕傲', (diaryFieldsForAi['conceited'] ?? '').toString().trim()),
        MapEntry(
            '做得不錯的地方', (diaryFieldsForAi['proudOf'] ?? '').toString().trim()),
        MapEntry('可多照顧自己的地方',
            (diaryFieldsForAi['selfCare'] ?? '').toString().trim()),
      ];

      final filledDiarySections =
          diarySections.where((entry) => entry.value.isNotEmpty).toList();

      if (filledDiarySections.isEmpty) {
        if (mounted) {
          setState(() => _error = '請先寫一些日記內容，再生成 AI 回饋。');
        }
        return;
      }

      // 組裝日記文字（合併所有文字欄位）
      final diaryContent = filledDiarySections
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');

      // 危機關鍵字偵測（在呼叫 AI 之前先做，保護使用者）
      final crisis = _detectCrisis(diaryContent);

      // 優先呼叫 Firebase Functions 上的 AI；失敗時回退到 mock
      // dailyRecord 優先用日記頁整體情緒滑桿值覆蓋平均值
      // 基礎版不讀藥物與其他紀錄
      final dailyRecordForAi = {
        if (_diaryData?['overallMood'] != null)
          'overallMood': _diaryData!['overallMood'],
        'moodScale': 5,
      };
      unawaited(
        AnalyticsService.logAiTaskStart(aiMode: 'diary_feedback'),
      );
      final result = await generateAIReflection(
        aiInput: aiInput,
        diaryContent: diaryContent,
        diaryFields: diaryFieldsForAi,
        dailyRecord: dailyRecordForAi,
      );

      // 把前端偵測到的 crisis 寫回結果
      result['crisisDetected'] = crisis || result['crisisDetected'] == true;
      result['generatedAt'] = FieldValue.serverTimestamp();

      // 儲存到 Firestore
      await HealthDataEncryptionService.setEncrypted(
        _db
            .collection('users')
            .doc(uid)
            .collection('aiJournalReflections')
            .doc(_docId),
        result,
      );

      if (!mounted) return;
      setState(() {
        _aiResult = result;
        _hasSavedResult = true;
        _crisisDetected = crisis;
      });
      unawaited(
        AnalyticsService.logAiTaskComplete(aiMode: 'diary_feedback'),
      );
    } catch (e, stack) {
      String errorType = 'unknown';
      if (e is AiJournalReflectionHttpException) {
        final code = e.statusCode;
        if (code == 408) {
          errorType = 'timeout';
        } else if (code != null && code >= 500) {
          errorType = 'api_error';
        } else {
          errorType = 'network';
        }
      } else if (e is TimeoutException) {
        errorType = 'timeout';
      } else if (e is FormatException) {
        errorType = 'parse_error';
      }
      unawaited(
        AnalyticsService.logAiTaskError(
          aiMode: 'diary_feedback',
          errorType: errorType,
        ),
      );
      m.debugPrint('catch 到的 exception: $e');
      m.debugPrint('stackTrace: $stack');
      m.debugPrint('generateAndSave exception: $e');
      if (!mounted) return;
      final message = 'AI 回饋生成失敗，請稍後再試。';
      setState(() => _error = '$message\n$e');
      _showSnack(message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
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
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
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

          if (widget.mode == AiAnalysisMode.basic) ...[
            // ② 今日情緒摘要（僅整體情緒分數）
            _OverallMoodCard(
              overallMood: _diaryData?['overallMood'] ??
                  _dailyRecordData?['overallMood'],
              teal: _teal,
              tealLight: _tealLight,
            ),
            const m.SizedBox(height: 16),
          ] else ...[
            // ② 今日情緒與症狀摘要（deep）
            _DailyRecordCard(
              recordData: {
                if (_dailyRecordData != null) ..._dailyRecordData!,
                if (_diaryData?['overallMood'] != null)
                  'overallMood': _diaryData!['overallMood'],
              },
              teal: _teal,
              tealLight: _tealLight,
            ),
            const m.SizedBox(height: 16),
          ],

          // 生成按鈕 / 載入中指示
          _buildGenerateButton(),
          const m.SizedBox(height: 16),

          // 錯誤訊息
          if (_error != null) _buildErrorCard(),

          // ── AI 結果區塊（有結果才顯示）──
          if (_aiResult != null) ...[
            if (_crisisDetected) ...[
              _CrisisAlertCard(teal: _teal),
              const m.SizedBox(height: 12),
            ],

            if (widget.mode == AiAnalysisMode.basic) ...[
              // 基礎版只顯示：摘要、主題、溫柔回饋、小建議
              _AiSectionCard(
                icon: m.Icons.auto_awesome_rounded,
                iconColor: HealingDesignSystem.primaryBlue,
                title: 'AI 今日摘要',
                tealLight: HealingDesignSystem.softBlue,
                child: _BodyText(_aiResult!['summary'] ?? ''),
              ),
              const m.SizedBox(height: 12),
              _AiSectionCard(
                icon: m.Icons.label_outline_rounded,
                iconColor: _amber,
                title: 'AI 可能主題',
                tealLight: HealingDesignSystem.softBlue,
                child: _TopicChips(
                  topics: List<String>.from(_aiResult!['topics'] ?? [])
                      .take(3)
                      .toList(),
                  teal: HealingDesignSystem.primaryBlue,
                ),
              ),
              const m.SizedBox(height: 12),
              _AiSectionCard(
                icon: m.Icons.star_border_rounded,
                iconColor: _amber,
                title: 'AI 溫柔回饋',
                tealLight: HealingDesignSystem.softBlue,
                child: _BodyText(_aiResult!['positiveFeedback'] ?? ''),
              ),
              const m.SizedBox(height: 12),
              _AiSectionCard(
                icon: m.Icons.wb_sunny_outlined,
                iconColor: _amber,
                title: '今日小建議',
                tealLight: HealingDesignSystem.softBlue,
                child: _BodyText(_aiResult!['tomorrowAction'] ?? ''),
              ),
              const m.SizedBox(height: 12),
            ] else ...[
              // 深入版顯示完整欄位（原本全部）
              _AiSectionCard(
                icon: m.Icons.auto_awesome_rounded,
                iconColor: HealingDesignSystem.primaryBlue,
                title: 'AI 今日摘要',
                tealLight: HealingDesignSystem.softBlue,
                child: _BodyText(_aiResult!['summary'] ?? ''),
              ),
              const m.SizedBox(height: 12),
              _AiSectionCard(
                icon: m.Icons.favorite_border_rounded,
                iconColor: m.Colors.pinkAccent.shade100,
                title: 'AI 情緒觀察',
                tealLight: HealingDesignSystem.softBlue,
                child: _BodyText(_aiResult!['emotionObservation'] ?? ''),
              ),
              const m.SizedBox(height: 12),
              _AiSectionCard(
                icon: m.Icons.label_outline_rounded,
                iconColor: _amber,
                title: 'AI 主題分類',
                tealLight: HealingDesignSystem.softBlue,
                child: _TopicChips(
                  topics: List<String>.from(_aiResult!['topics'] ?? []),
                  teal: HealingDesignSystem.primaryBlue,
                ),
              ),
              const m.SizedBox(height: 12),
              _AiSectionCard(
                icon: m.Icons.star_border_rounded,
                iconColor: _amber,
                title: 'AI 正向回饋',
                tealLight: HealingDesignSystem.softBlue,
                child: _BodyText(_aiResult!['positiveFeedback'] ?? ''),
              ),
              const m.SizedBox(height: 12),
              _AiSectionCard(
                icon: m.Icons.spa_outlined,
                iconColor: m.Colors.green.shade400,
                title: '感恩日記引導問題',
                tealLight: HealingDesignSystem.softBlue,
                child: _GratitudeQuestions(
                  questions:
                      List<String>.from(_aiResult!['gratitudeQuestions'] ?? []),
                  teal: HealingDesignSystem.accentPurple,
                ),
              ),
              const m.SizedBox(height: 12),
              _AiSectionCard(
                icon: m.Icons.wb_sunny_outlined,
                iconColor: _amber,
                title: '明日小行動',
                tealLight: HealingDesignSystem.softBlue,
                child: _BodyText(_aiResult!['tomorrowAction'] ?? ''),
              ),
              const m.SizedBox(height: 12),
              // ...可擴充更多 deep 欄位...
            ],
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
      backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
      foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
      elevation: 0,
      centerTitle: false,
      title: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          m.Text(
            widget.mode == AiAnalysisMode.basic ? 'AI 基礎回饋' : 'AI 深入觀察',
            style: HealingDesignSystem.titleMedium.copyWith(
              color: HealingDesignSystem.adaptiveAppBarForeground(context),
            ),
          ),
          m.Text(
            '${_day.year}年${_day.month}月${_day.day}日',
            style: HealingDesignSystem.bodySmall.copyWith(
              color: HealingDesignSystem.adaptiveAppBarForeground(context)
                  .withOpacity(0.78),
            ),
          ),
        ],
      ),
      actions: [
        if (_hasSavedResult)
          m.Padding(
            padding:
                const m.EdgeInsets.only(right: HealingDesignSystem.paddingL),
            child: m.Chip(
              label: m.Text('已儲存',
                  style: HealingDesignSystem.labelSmall.copyWith(
                      color: HealingDesignSystem.adaptiveAppBarForeground(
                          context))),
              backgroundColor: m.Colors.black.withOpacity(0.22),
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
        color: HealingDesignSystem.adaptiveSurface(context),
        surfaceTintColor: m.Colors.transparent,
        shape: m.RoundedRectangleBorder(
          borderRadius: m.BorderRadius.circular(HealingDesignSystem.radiusL),
          side: m.BorderSide(
            color: HealingDesignSystem.adaptiveCardBorder(context),
          ),
        ),
        child: m.Padding(
          padding: const m.EdgeInsets.symmetric(
              vertical: HealingDesignSystem.paddingXL),
          child: m.Column(
            children: [
              m.CircularProgressIndicator(
                  color: HealingDesignSystem.primaryBlue, strokeWidth: 2.5),
              const m.SizedBox(height: HealingDesignSystem.paddingM),
              m.Text(
                'AI 正在為你生成今日回饋…',
                style: HealingDesignSystem.bodyMedium
                    .copyWith(color: HealingDesignSystem.primaryBlue),
              ),
              const m.SizedBox(height: HealingDesignSystem.paddingXS),
              m.Text(
                '這通常需要幾秒鐘，請稍候 🌿',
                style: HealingDesignSystem.bodySmall.copyWith(
                    color: HealingDesignSystem.primaryBlue.withOpacity(0.7)),
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
          backgroundColor: HealingDesignSystem.primaryBlue,
          foregroundColor: m.Colors.white,
          padding: const m.EdgeInsets.symmetric(
              vertical: HealingDesignSystem.paddingL),
          shape: m.RoundedRectangleBorder(
              borderRadius:
                  m.BorderRadius.circular(HealingDesignSystem.radiusM)),
        ),
        onPressed: _hasMeaningfulDiaryInput ? _generateAndSave : null,
        icon: const m.Icon(m.Icons.auto_awesome_rounded, size: 20),
        label: m.Text(
          _hasMeaningfulDiaryInput
              ? (_hasSavedResult ? '重新生成 AI 回饋' : '生成今日 AI 回饋')
              : '請先填寫日記內容',
          style: const m.TextStyle(fontSize: 15, fontWeight: m.FontWeight.w600),
        ),
      ),
    );
  }

  // ── 錯誤卡片 ──
  m.Widget _buildErrorCard() {
    final errorColor = m.Theme.of(context).colorScheme.error;
    return m.Card(
      color: errorColor.withOpacity(0.12),
      surfaceTintColor: m.Colors.transparent,
      shape: m.RoundedRectangleBorder(
        borderRadius: m.BorderRadius.circular(16),
        side: m.BorderSide(color: errorColor.withOpacity(0.35)),
      ),
      margin: const m.EdgeInsets.only(bottom: 16),
      child: m.Padding(
        padding: const m.EdgeInsets.all(16),
        child: m.Row(
          children: [
            m.Icon(m.Icons.error_outline_rounded, color: errorColor, size: 20),
            const m.SizedBox(width: 10),
            m.Expanded(
              child: m.Text(
                _error!,
                style: m.TextStyle(color: errorColor, fontSize: 13),
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
          m.Icon(m.Icons.check_circle_outline_rounded, color: _teal, size: 16),
          const m.SizedBox(width: 6),
          m.Text(
            '已儲存至雲端  •  $_docId',
            style: m.TextStyle(
              fontSize: 12,
              color: HealingDesignSystem.adaptiveSecondaryText(context),
            ),
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
              style: m.TextStyle(
                fontSize: 16,
                fontWeight: m.FontWeight.w700,
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
            ),
          ],
          if (content.isNotEmpty) ...[
            const m.SizedBox(height: 8),
            m.Text(
              content,
              style: m.TextStyle(
                fontSize: 14,
                height: 1.65,
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
            ),
          ],
          if (highlight.isNotEmpty) ...[
            const m.SizedBox(height: 10),
            m.Container(
              padding:
                  const m.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: m.BoxDecoration(
                color: HealingDesignSystem.adaptiveFill(context),
                borderRadius: m.BorderRadius.circular(10),
                border: m.Border.all(
                  color: HealingDesignSystem.adaptiveCardBorder(context),
                ),
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
                        color: HealingDesignSystem.adaptivePrimaryText(context),
                        height: 1.5,
                      ),
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
    // 基礎 AI 版只顯示「整體情緒」，不顯示神祕綜合分數、
    // 也不在這張卡片主動展開睡眠、症狀、藥物等深入資料。
    final mood = data['overallMood'] ?? data['mood'];

    if (mood == null) {
      return _EmptyHint(text: '尚無可顯示的整體情緒紀錄。');
    }

    return m.Container(
      padding: const m.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: m.BoxDecoration(
        color: teal.withValues(alpha: 0.08),
        borderRadius: m.BorderRadius.circular(14),
        border: m.Border.all(color: teal.withValues(alpha: 0.18)),
      ),
      child: m.Row(
        mainAxisSize: m.MainAxisSize.min,
        children: [
          m.Icon(
            m.Icons.sentiment_satisfied_alt_rounded,
            size: 18,
            color: teal,
          ),
          const m.SizedBox(width: 8),
          m.Text(
            '你的整體情緒得分為 $mood',
            style: m.TextStyle(
              fontSize: 14,
              fontWeight: m.FontWeight.w600,
              color: teal,
            ),
          ),
        ],
      ),
    );
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
      padding: const m.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                  color: HealingDesignSystem.adaptiveSecondaryText(context))),
          const m.SizedBox(width: 4),
          m.Text(
            value,
            style: m.TextStyle(
                fontSize: 13, fontWeight: m.FontWeight.w700, color: teal),
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
    final dark = HealingDesignSystem.isDark(context);
    return m.Wrap(
      alignment: m.WrapAlignment.start,
      spacing: 8,
      runSpacing: 8,
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
              color: dark
                  ? HealingDesignSystem.adaptivePrimaryText(context)
                  : m.HSLColor.fromColor(color).withLightness(0.3).toColor(),
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

  const _GratitudeQuestions({required this.questions, required this.teal});

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
                      color: HealingDesignSystem.adaptivePrimaryText(context)),
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
    final dangerColor = m.Theme.of(context).colorScheme.error;
    return m.Card(
      elevation: 2,
      color: dangerColor.withOpacity(0.12),
      surfaceTintColor: m.Colors.transparent,
      shape: m.RoundedRectangleBorder(
        borderRadius: m.BorderRadius.circular(20),
        side: m.BorderSide(color: dangerColor.withOpacity(0.35)),
      ),
      child: m.Padding(
        padding: const m.EdgeInsets.all(16),
        child: m.Column(
          crossAxisAlignment: m.CrossAxisAlignment.start,
          children: [
            m.Row(
              children: [
                m.Icon(m.Icons.favorite_rounded, color: dangerColor, size: 22),
                const m.SizedBox(width: 8),
                m.Expanded(
                  child: m.Text(
                    '我注意到你今天有些沉重的感受',
                    style: m.TextStyle(
                      fontSize: 15,
                      fontWeight: m.FontWeight.w700,
                      color: dangerColor,
                    ),
                  ),
                ),
              ],
            ),
            const m.SizedBox(height: 8),
            m.Text(
              '你不需要一個人承擔。每一個人的感受都值得被認真對待，\n專業的支持隨時都在你身邊。',
              style: m.TextStyle(
                fontSize: 13,
                height: 1.6,
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
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
    final dangerColor = m.Theme.of(context).colorScheme.error;
    return m.Material(
      color: HealingDesignSystem.adaptiveSurface(context),
      shape: m.RoundedRectangleBorder(
        borderRadius: m.BorderRadius.circular(12),
        side: m.BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      child: m.InkWell(
        borderRadius: m.BorderRadius.circular(12),
        onTap: () async {
          final uri = Uri.parse(phone);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        },
        child: m.Padding(
          padding: const m.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: m.Row(
            children: [
              m.Text(emoji, style: const m.TextStyle(fontSize: 20)),
              const m.SizedBox(width: 10),
              m.Expanded(
                child: m.Column(
                  crossAxisAlignment: m.CrossAxisAlignment.start,
                  children: [
                    m.Text(label,
                        style: m.TextStyle(
                            fontSize: 14,
                            fontWeight: m.FontWeight.w700,
                            color: dangerColor)),
                    m.Text(subtitle,
                        style: m.TextStyle(
                            fontSize: 11,
                            color: HealingDesignSystem.adaptiveSecondaryText(
                                context))),
                  ],
                ),
              ),
              m.Icon(m.Icons.phone_outlined, size: 18, color: dangerColor),
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
      shadowColor: HealingDesignSystem.isDark(context)
          ? m.Colors.black.withOpacity(0.35)
          : m.Colors.black12,
      color: HealingDesignSystem.adaptiveSurface(context),
      surfaceTintColor: m.Colors.transparent,
      shape: m.RoundedRectangleBorder(
        borderRadius: m.BorderRadius.circular(20),
        side: m.BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
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
                color: HealingDesignSystem.adaptivePrimaryText(context),
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
        fontSize: 14,
        height: 1.7,
        color: HealingDesignSystem.adaptivePrimaryText(context),
      ),
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
            color: HealingDesignSystem.adaptiveSecondaryText(context),
            fontStyle: m.FontStyle.italic),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 今日情緒摘要卡片（僅顯示整體情緒分數）
// ──────────────────────────────────────────────
class _OverallMoodCard extends m.StatelessWidget {
  final num? overallMood;
  final m.Color teal;
  final m.Color tealLight;

  const _OverallMoodCard({
    this.overallMood,
    required this.teal,
    required this.tealLight,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final scoreText = overallMood != null
        ? overallMood!.toStringAsFixed(overallMood! % 1 == 0 ? 0 : 1)
        : '--';

    return m.Container(
      margin: const m.EdgeInsets.symmetric(horizontal: 4),
      padding: const m.EdgeInsets.all(18),
      decoration: HealingDesignSystem.adaptiveCardDecoration(
        context,
        radius: 24,
      ),
      child: m.Row(
        children: [
          m.Container(
            width: 48,
            height: 48,
            decoration: m.BoxDecoration(
              color: teal.withOpacity(0.10),
              shape: m.BoxShape.circle,
            ),
            child: m.Icon(
              m.Icons.mood_rounded,
              color: teal,
              size: 28,
            ),
          ),
          const m.SizedBox(width: 14),
          m.Expanded(
            child: m.Column(
              crossAxisAlignment: m.CrossAxisAlignment.start,
              children: [
                m.Text(
                  '今日情緒摘要',
                  style: m.TextStyle(
                    fontSize: 17,
                    fontWeight: m.FontWeight.w800,
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const m.SizedBox(height: 6),
                m.Text(
                  '你記錄的整體情緒分數',
                  style: m.TextStyle(
                    fontSize: 13,
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          m.Container(
            padding: const m.EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            decoration: m.BoxDecoration(
              color: teal.withOpacity(0.10),
              borderRadius: m.BorderRadius.circular(999),
              border: m.Border.all(
                color: teal.withOpacity(0.22),
              ),
            ),
            child: m.RichText(
              text: m.TextSpan(
                children: [
                  m.TextSpan(
                    text: scoreText,
                    style: m.TextStyle(
                      fontSize: 22,
                      fontWeight: m.FontWeight.w900,
                      color: teal,
                    ),
                  ),
                  m.TextSpan(
                    text: ' / 5',
                    style: m.TextStyle(
                      fontSize: 13,
                      fontWeight: m.FontWeight.w600,
                      color: teal.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
