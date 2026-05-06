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

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' as m;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
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

  Future<Map<String, dynamic>> _buildMedicationContextForAi(String uid) async {
    try {
      final userRef = _db.collection('users').doc(uid);
      final checkinSnap = await userRef
          .collection('medicationCheckins')
          .doc(_docId)
          .get();
      final medsSnap = await userRef
          .collection('medications')
          .where('isActive', isEqualTo: true)
          .get();

      final medNameById = <String, String>{};
      final activeMedicationNames = <String>[];
      for (final doc in medsSnap.docs) {
        final data = doc.data();
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

      final data = checkinSnap.data() ?? const <String, dynamic>{};
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
    } catch (e) {
      m.debugPrint('⚠️ buildMedicationContextForAi failed: $e');
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
  Future<Map<String, dynamic>> generateMockAIReflection({
    required String diaryContent,
    required Map<String, dynamic> dailyRecord,
  }) async {
    // 模擬網路延遲
    await Future.delayed(const Duration(milliseconds: 1200));

    final mood = dailyRecord['overallMood'] ?? dailyRecord['mood'] ?? 5;
    final medNames = <String>{};
    void collectMed(dynamic value) {
      if (value == null) return;
      if (value is String) {
        final v = value.trim();
        if (v.isNotEmpty) medNames.add(v);
        return;
      }
      if (value is List) {
        for (final item in value) {
          collectMed(item);
        }
        return;
      }
      if (value is Map) {
        final name = (value['name'] ??
                value['title'] ??
                value['label'] ??
                value['medicationName'] ??
                value['drugName'])
            ?.toString()
            .trim();
        if (name != null && name.isNotEmpty) {
          medNames.add(name);
          return;
        }
        for (final v in value.values) {
          collectMed(v);
        }
      }
    }

    collectMed(dailyRecord['medication']);
    collectMed(dailyRecord['medications']);
    collectMed(dailyRecord['medicines']);

    final sleep = dailyRecord['sleep'];
    if (sleep is Map) {
      final hypnoticName = (sleep['hypnoticName'] ?? '').toString().trim();
      if (hypnoticName.isNotEmpty) {
        medNames.add('安眠藥：$hypnoticName');
      } else if (sleep['tookHypnotic'] == true) {
        medNames.add('安眠藥');
      }
    }

    final hasMedicationData = medNames.isNotEmpty;

    // ── Mock 資料庫（隨機挑選增加真實感）──
    final rng = Random();

    final summaries = [
      '今天你記錄了許多生活細節，文字中透著一份細膩與用心。無論今天的感受如何起伏，你願意把它寫下來，本身就是對自己的溫柔。',
      '這篇日記裡藏著你對生活的觀察。你注意到了周遭細微的變化，也誠實地面對自己的感受，這需要很大的勇氣。',
      '今天的文字帶有一種安靜的力量。你沒有迴避自己的情緒，而是選擇與它同在，這正是正念練習最珍貴的地方。',
    ];

    final emotionObservations = [
      '從文字的節奏與用詞來看，今天你可能帶著${mood >= 6 ? "輕盈愉快" : mood >= 4 ? "平靜沉著" : "些許疲憊"}的心情度過這一天。你對自己感受的描述很細膩，也展現了不逃避情緒的勇氣。',
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

    final summaryText = summaries[rng.nextInt(summaries.length)] +
      (hasMedicationData
        ? ' 另外你也留下了用藥資訊，這讓回顧時更容易對照身心變化。'
        : '');
    final observationText =
      emotionObservations[rng.nextInt(emotionObservations.length)] +
        (hasMedicationData
          ? ' 今天也有用藥紀錄，建議和情緒分數、症狀一起觀察是否有連動。'
          : '');
    final feedbackText =
      positiveFeedbacks[rng.nextInt(positiveFeedbacks.length)] +
        (hasMedicationData
          ? ' 你願意把用藥也一起記下來，這是很實際且有力量的自我照顧。'
          : '');

    return {
      'summary': summaryText,
      'emotionObservation': observationText,
      'topics': topics,
      'positiveFeedback': feedbackText,
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
      if (raw['emotionModel'] is Map)
        'emotionModel': Map<String, dynamic>.from(raw['emotionModel'] as Map),
    };
  }

  Future<Map<String, dynamic>> buildAIInputData() async {
    final uid = _uid;
    if (uid == null) {
      final empty = <String, dynamic>{
        'date': _docId,
        'diaryText': '',
        'emotions': <Map<String, dynamic>>[],
        'sleep': <String, dynamic>{
          'hours': null,
          'quality': '',
          'note': '',
        },
        'symptoms': <Map<String, dynamic>>[],
        'recentRecords': <Map<String, dynamic>>[],
      };
      m.debugPrint('🧪 buildAIInputData: $empty');
      return empty;
    }

    Map<String, dynamic> diary = _diaryData ?? const <String, dynamic>{};
    Map<String, dynamic> dailyRecord =
        _dailyRecordData ?? const <String, dynamic>{};

    try {
      if (_diaryData == null || _dailyRecordData == null) {
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

        diary = diarySnap.data() ?? const <String, dynamic>{};
        dailyRecord = recordSnap.data() ?? const <String, dynamic>{};
      }
    } catch (e) {
      m.debugPrint('⚠️ buildAIInputData read error: $e');
    }

    String _safeText(dynamic v) => (v ?? '').toString().trim();

    num? _toNum(dynamic v) {
      if (v is num) return v;
      return num.tryParse((v ?? '').toString().trim());
    }

    num? _calcSleepHours(Map<String, dynamic>? sleepMap) {
      if (sleepMap == null) return null;
      final sleepTimeStr = _safeText(sleepMap['sleepTime']);
      final finalWakeTimeStr = _safeText(sleepMap['finalWakeTime']);
      final wakeTimeStr = _safeText(sleepMap['wakeTime']);
      final end = finalWakeTimeStr.isNotEmpty ? finalWakeTimeStr : wakeTimeStr;
      if (sleepTimeStr.isEmpty || end.isEmpty) return null;
      try {
        final sParts = sleepTimeStr.split(':');
        final eParts = end.split(':');
        int sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
        int eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
        if (eMin <= sMin) eMin += 24 * 60;
        return ((eMin - sMin) / 60).round();
      } catch (_) {
        return null;
      }
    }

    String _sleepQualityLabel(dynamic quality) {
      final score = _toNum(quality);
      if (score == null) return '';
      if (score >= 8) return '良好';
      if (score >= 5) return '普通';
      return '較差';
    }

    final diarySections = <MapEntry<String, String>>[
      MapEntry('標題', _safeText(diary['title'])),
      MapEntry('內容', _safeText(diary['content'])),
      MapEntry('今日主題曲', _safeText(diary['themeSong'])),
      MapEntry('最想記錄的瞬間', _safeText(diary['highlight'])),
      MapEntry('今天情緒像', _safeText(diary['metaphor'])),
      MapEntry('為自己感到驕傲', _safeText(diary['conceited'])),
      MapEntry('做得不錯的地方', _safeText(diary['proudOf'])),
      MapEntry('可多照顧自己的地方', _safeText(diary['selfCare'])),
    ];
    final diaryText = diarySections
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');

    final emotions = <Map<String, dynamic>>[];
    final overallMood = _toNum(diary['overallMood'] ?? dailyRecord['overallMood']);
    if (overallMood != null) {
      emotions.add({'name': '整體情緒', 'score': overallMood});
    }
    final rawEmotions = dailyRecord['emotions'];
    if (rawEmotions is List) {
      for (final item in rawEmotions) {
        if (item is! Map) continue;
        final name = _safeText(item['name']);
        final score = _toNum(item['value'] ?? item['score']);
        if (name.isEmpty) continue;
        emotions.add({'name': name, 'score': score});
      }
    } else if (rawEmotions is Map) {
      for (final entry in rawEmotions.entries) {
        final name = _safeText(entry.key);
        if (name.isEmpty) continue;
        emotions.add({'name': name, 'score': _toNum(entry.value)});
      }
    }
    final anxiety = _toNum(dailyRecord['anxiety']);
    if (anxiety != null) {
      emotions.add({'name': '焦慮', 'score': anxiety});
    }

    final sleepMap = dailyRecord['sleep'] is Map
        ? Map<String, dynamic>.from(dailyRecord['sleep'] as Map)
        : null;
    final sleep = <String, dynamic>{
      'hours': _calcSleepHours(sleepMap),
      'quality': _sleepQualityLabel(
        sleepMap?['quality'] ?? diary['overallSleepQuality'] ?? dailyRecord['overallSleepQuality'],
      ),
      'note': _safeText(sleepMap?['note']),
    };

    final symptoms = <Map<String, dynamic>>[];
    final rawSymptoms = dailyRecord['symptoms'];
    if (rawSymptoms is List) {
      for (final item in rawSymptoms) {
        if (item is Map) {
          final name = _safeText(item['name'] ?? item['label'] ?? item['title']);
          if (name.isEmpty) continue;
          symptoms.add({'name': name, 'score': _toNum(item['score'] ?? item['value'])});
        } else {
          final name = _safeText(item);
          if (name.isEmpty) continue;
          symptoms.add({'name': name, 'score': null});
        }
      }
    } else if (rawSymptoms is Map) {
      for (final entry in rawSymptoms.entries) {
        final name = _safeText(entry.key);
        if (name.isEmpty) continue;
        symptoms.add({'name': name, 'score': _toNum(entry.value)});
      }
    }

    final result = <String, dynamic>{
      'date': _docId,
      'diaryText': diaryText,
      'emotions': emotions,
      'sleep': sleep,
      'symptoms': symptoms,
      'recentRecords': <Map<String, dynamic>>[],
    };

    m.debugPrint('🧪 buildAIInputData: $result');
    return result;
  }

  Future<Map<String, dynamic>> generateGeminiReflectionByMake({
    required String uid,
    required String docId,
    required Map<String, dynamic> aiInput,
    required String diaryContent,
    required Map<String, dynamic> diaryFields,
    required Map<String, dynamic> dailyRecord,
  }) async {
    const webhookUrl = 'https://hook.us2.make.com/1o186sfmo838wb7tto62i6neb67zob8r';

    final response = await http.post(
      Uri.parse(webhookUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'uid': uid,
        'docId': docId,
        'date': docId,
        'aiInput': aiInput,
        'diaryContent': diaryContent,
        'diaryFields': diaryFields,
        'dailyRecord': dailyRecord,
        'requestedAt': DateTime.now().toIso8601String(),
        'source': 'make_gemini',
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Make Webhook 呼叫失敗：${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return {
        'summary': decoded['summary'] ?? decoded['reply'] ?? '',
        'emotionObservation': decoded['emotionObservation'] ?? '',
        'topics': decoded['topics'] ?? [],
        'positiveFeedback': decoded['positiveFeedback'] ?? '',
        'gratitudeQuestions': decoded['gratitudeQuestions'] ?? [],
        'tomorrowAction': decoded['tomorrowAction'] ?? '',
        'crisisDetected': decoded['crisisDetected'] ?? false,
        'isMock': false,
        'model': 'gemini-1.5-flash',
        'source': 'make_gemini',
        'generatedAt': FieldValue.serverTimestamp(),
      };
    }

    if (decoded is String) {
      return {
        'summary': decoded,
        'emotionObservation': '',
        'topics': [],
        'positiveFeedback': '',
        'gratitudeQuestions': [],
        'tomorrowAction': '',
        'crisisDetected': false,
        'isMock': false,
        'model': 'gemini-1.5-flash',
        'source': 'make_gemini',
        'generatedAt': FieldValue.serverTimestamp(),
      };
    }

    throw Exception('Make Webhook 回傳格式無法解析：${response.body}');
  }

  Future<Map<String, dynamic>> generateAIReflection({
    required Map<String, dynamic> aiInput,
    required String diaryContent,
    required Map<String, dynamic> diaryFields,
    required Map<String, dynamic> dailyRecord,
  }) async {
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('generateAiJournalReflection');
      final response = await callable.call({
        'date': _docId,
        'aiInput': aiInput,
      });

      final data = response.data;
      if (data is! Map) {
        throw const FormatException('AI 回傳格式錯誤');
      }

      return _normalizeAiResult(Map<String, dynamic>.from(data));
    } catch (e, stack) {
  m.debugPrint('❌ generateAIReflection error: $e');
  m.debugPrint('❌ stack: $stack');
  rethrow;
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
      };

      final diarySections = <MapEntry<String, String>>[
        MapEntry('標題', (diaryFieldsForAi['title'] ?? '').toString().trim()),
        MapEntry('內容', (diaryFieldsForAi['content'] ?? '').toString().trim()),
        MapEntry('今日主題曲', (diaryFieldsForAi['themeSong'] ?? '').toString().trim()),
        MapEntry('最想記錄的瞬間', (diaryFieldsForAi['highlight'] ?? '').toString().trim()),
        MapEntry('今天情緒像', (diaryFieldsForAi['metaphor'] ?? '').toString().trim()),
        MapEntry('為自己感到驕傲', (diaryFieldsForAi['conceited'] ?? '').toString().trim()),
        MapEntry('做得不錯的地方', (diaryFieldsForAi['proudOf'] ?? '').toString().trim()),
        MapEntry('可多照顧自己的地方', (diaryFieldsForAi['selfCare'] ?? '').toString().trim()),
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
      final medicationContext = await _buildMedicationContextForAi(uid);
      final dailyRecordForAi = {
        if (_dailyRecordData != null) ..._dailyRecordData!,
        if (_diaryData?['overallMood'] != null)
          'overallMood': _diaryData!['overallMood'],
        if (medicationContext.isNotEmpty) 'medication': medicationContext,
        if (medicationContext['activeMedicationNames'] is List)
          'medications': medicationContext['activeMedicationNames'],
      };
      final result = await generateGeminiReflectionByMake(
        uid: uid,
        docId: _docId,
        aiInput: aiInput,
        diaryContent: diaryContent,
        diaryFields: diaryFieldsForAi,
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
    const appBarBg = _teal;
    const appBarFg = m.Colors.white;

    return m.AppBar(
      backgroundColor: appBarBg,
      foregroundColor: appBarFg,
      elevation: 0,
      centerTitle: false,
      title: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          m.Text(
            'AI 正念回饋',
            style: m.TextStyle(
              fontSize: 17,
              fontWeight: m.FontWeight.w700,
              color: appBarFg,
            ),
          ),
          m.Text(
            '${ _day.year }年${ _day.month }月${ _day.day }日',
            style: m.TextStyle(
              fontSize: 12,
              color: appBarFg.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
      actions: [
        if (_hasSavedResult)
          m.Padding(
            padding: const m.EdgeInsets.only(right: 12),
            child: m.Chip(
              label: m.Text('已儲存',
                  style: m.TextStyle(fontSize: 11, color: appBarFg)),
              backgroundColor: m.Colors.black.withValues(alpha: 0.22),
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

      // 睡眠欄位：只顯示總時數 + 夜間睡眠狀況
      if (entry.key == 'sleep') {
        final sleepMap = val is Map<String, dynamic> ? val : null;
        if (sleepMap == null) continue;

        // 計算夜間總時數
        final sleepTimeStr = sleepMap['sleepTime'] as String?;
        final wakeTimeStr = (sleepMap['finalWakeTime'] as String?)?.isNotEmpty == true
            ? sleepMap['finalWakeTime'] as String
            : sleepMap['wakeTime'] as String?;

        String? hoursLabel;
        if (sleepTimeStr != null && wakeTimeStr != null) {
          try {
            final sParts = sleepTimeStr.split(':');
            final wParts = wakeTimeStr.split(':');
            int sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
            int wMin = int.parse(wParts[0]) * 60 + int.parse(wParts[1]);
            if (wMin <= sMin) wMin += 24 * 60; // overnight
            final hours = (wMin - sMin) / 60.0;
            hoursLabel = '${hours.toStringAsFixed(1)} 小時';
          } catch (_) {}
        }

        if (hoursLabel != null) {
          items.add(_ScoreChip(
            label: '夜間睡眠',
            icon: m.Icons.bedtime_outlined,
            value: hoursLabel,
            teal: teal,
          ));
        }

        // 夜間睡眠狀況 flags
        const sleepFlagLabels = <String, String>{
          'good': '優',
          'ok': '良好',
          'earlyWake': '早醒',
          'dreams': '多夢',
          'lightSleep': '淺眠',
          'nocturia': '夜尿',
          'fragmented': '睡睡醒醒',
          'insufficient': '睡眠不足',
          'initInsomnia': '入睡困難 (躺超過 30 分鐘才入睡)',
          'interrupted': '睡眠中斷 (醒來後超過 30 分鐘才又入睡)',
        };
        final flags = sleepMap['flags'];
        if (flags is List && flags.isNotEmpty) {
          items.add(
            m.Padding(
              padding: const m.EdgeInsets.only(top: 8),
              child: m.Column(
                crossAxisAlignment: m.CrossAxisAlignment.start,
                children: [
                  m.Row(
                    children: [
                      m.Icon(m.Icons.nightlight_round,
                          size: 16, color: teal),
                      const m.SizedBox(width: 5),
                      const m.Text('夜間睡眠狀況',
                          style: m.TextStyle(
                              fontSize: 12, fontWeight: m.FontWeight.w600)),
                    ],
                  ),
                  const m.SizedBox(height: 4),
                  m.Wrap(
                    alignment: m.WrapAlignment.spaceBetween,
                    spacing: 6,
                    runSpacing: 4,
                    children: flags
                        .map(
                          (s) => m.Chip(
                            label: m.Text(
                                sleepFlagLabels[s.toString()] ?? s.toString(),
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
        continue;
      }

      items.add(_ScoreChip(
        label: entry.value.label,
        icon: entry.value.icon,
        value: val.toString(),
        teal: teal,
      ));
    }

    // 症狀列表
    final symptoms = data['symptoms'];
    if (symptoms is List) {
      final symptomList = symptoms
          .map((s) => s.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (symptomList.isNotEmpty) {
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
                  alignment: m.WrapAlignment.spaceBetween,
                  spacing: 6,
                  runSpacing: 4,
                  children: symptomList
                      .map(
                        (s) => m.Chip(
                          label: m.Text(s,
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
    }

    if (items.isEmpty) return _EmptyHint(text: '尚無可顯示的紀錄欄位。');

    return m.Wrap(alignment: m.WrapAlignment.spaceBetween, spacing: 8, runSpacing: 8, children: items);
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
      alignment: m.WrapAlignment.spaceBetween,
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
