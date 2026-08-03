import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../daily/emotion_trend_calculator.dart';
import '../daily/daily_record_repository.dart';
import '../utils/health_data_encryption_service.dart';
import '../models/daily_record.dart';
import '../utils/date_helper.dart';

/// ============================================================
/// 測試資料產生器
/// 只在 debug/dev 模式使用，正式 release 版不可觸發。
/// ============================================================
class TestDataGenerator {
  TestDataGenerator._();

  static Random _rng = Random(42); // 固定 seed 確保可重現

  /// 所有測試資料都會加上這個標記
  static const String kTestSource = 'dev_seed';
  static const String kTestFlagField = 'isTestData';
  static const String kTestOwnedField = 'isDevSeedOwned';

  // ============================================================
  // 內建情緒定義
  // ============================================================
  static const List<String> kPositiveEmotions = [
    '平靜',
    '放鬆',
    '安心',
    '快樂',
    '興奮',
    '有希望',
  ];

  static const List<String> kNegativeEmotions = [
    '焦慮',
    '低落',
    '疲憊',
    '空虛',
    '煩躁',
    '無助',
    '恐慌',
    '自殺意念',
  ];

  // ============================================================
  // 情境定義：每段區間的天數與情緒設定
  // ============================================================
  /// 每段情境的設定
  /// [startDayOffset] = 距離今天往回推的天數（起點）
  /// [durationDays] = 這段情境持續幾天（含頭尾）
  /// [recordDensity] = 每週約幾天有紀錄 (3~7)
  /// [positiveRange] = 正向情緒分數範圍 [min, max]
  /// [negativeRange] = 負向情緒分數範圍 [min, max]
  /// [positiveWeights] = 各正向情緒出現的相對權重
  /// [negativeWeights] = 各負向情緒出現的相對權重
  /// [use10Scale] = 是否使用 10 點量表
  /// [includeDanger] = 是否包含自殺意念
  /// [dangerRate] = 自殺意念出現機率 (0~1)

  static List<int> _scaledDurations(int totalDays) {
    const baseDurations = [7, 14, 24, 25, 25, 25];
    const baseTotal = 120;
    final durations = baseDurations
        .map((days) => max(1, (days * totalDays / baseTotal).round()))
        .toList();

    var diff = totalDays - durations.fold<int>(0, (acc, days) => acc + days);
    var index = durations.length - 1;
    while (diff != 0) {
      if (diff > 0) {
        durations[index]++;
        diff--;
      } else if (durations[index] > 1) {
        durations[index]--;
        diff++;
      }
      index = (index - 1 + durations.length) % durations.length;
    }

    return durations;
  }

  static List<Map<String, dynamic>> _buildScenarios({
    required int totalDays,
  }) {
    final durations = _scaledDurations(totalDays);
    var endOffset = -1;

    Map<String, dynamic> scenario({
      required String label,
      required int duration,
      required int recordDensity,
      required List<double> positiveRange,
      required List<double> negativeRange,
      required List<int> positiveWeights,
      required List<int> negativeWeights,
      required bool use10Scale,
    }) {
      endOffset += duration;
      return {
        'label': label,
        'startDayOffset': endOffset,
        'durationDays': duration,
        'recordDensity': recordDensity,
        'positiveRange': positiveRange,
        'negativeRange': negativeRange,
        'positiveWeights': positiveWeights,
        'negativeWeights': negativeWeights,
        'use10Scale': use10Scale,
        'includeDanger': false,
        'dangerRate': 0.0,
      };
    }

    return [
      // ── 情境 1：穩定期（最近 7 天）──
      scenario(
        label: '穩定期',
        duration: durations[0],
        recordDensity: 5,
        positiveRange: [3.0, 4.0],
        negativeRange: [1.0, 2.0],
        positiveWeights: [3, 3, 3, 2, 1, 1], // 平靜/放鬆/安心較多
        negativeWeights: [1, 1, 2, 1, 1, 1, 0, 0], // 疲憊稍多
        use10Scale: false,
      ),
      // ── 情境 2：壓力上升期（第 8~21 天）──
      scenario(
        label: '壓力上升期',
        duration: durations[1],
        recordDensity: 4,
        positiveRange: [2.0, 3.5], // 正向逐漸下降
        negativeRange: [2.0, 4.5], // 負向逐漸上升
        positiveWeights: [2, 2, 2, 2, 1, 1],
        negativeWeights: [3, 2, 3, 1, 3, 2, 1, 0], // 焦慮/疲憊/煩躁較多
        use10Scale: false,
      ),
      // ── 情境 3：低落期（第 22~45 天）──
      scenario(
        label: '低落期',
        duration: durations[2],
        recordDensity: 3, // 紀錄較少
        positiveRange: [0.5, 2.0], // 正向很少
        negativeRange: [3.5, 5.0], // 負向偏高
        positiveWeights: [1, 1, 1, 1, 0, 0], // 正向幾乎不出現
        negativeWeights: [2, 4, 4, 3, 2, 3, 1, 0], // 低落/疲憊/空虛/無助較多
        use10Scale: false,
      ),
      // ── 情境 4：恢復期（第 46~70 天）──
      scenario(
        label: '恢復期',
        duration: durations[3],
        recordDensity: 4,
        positiveRange: [2.0, 4.0], // 正向逐漸回升
        negativeRange: [1.5, 3.0], // 負向下降
        positiveWeights: [2, 2, 2, 3, 2, 2], // 快樂/有希望增加
        negativeWeights: [1, 2, 2, 1, 1, 1, 0, 0],
        use10Scale: false,
      ),
      // ── 情境 5：高能量正向期（第 71~95 天）──
      scenario(
        label: '高能量正向期',
        duration: durations[4],
        recordDensity: 5,
        positiveRange: [4.0, 5.0], // 正向高分
        negativeRange: [0.5, 1.5], // 負向很低
        positiveWeights: [2, 2, 2, 4, 4, 3], // 快樂/興奮/有希望較多
        negativeWeights: [1, 0, 1, 0, 1, 0, 0, 0],
        use10Scale: false,
      ),
      // ── 情境 6：舊資料 10 點量表區（第 96~120 天）──
      scenario(
        label: '10點量表舊資料',
        duration: durations[5],
        recordDensity: 4,
        positiveRange: [3.0, 8.0], // 10 點量表分數範圍不同
        negativeRange: [1.0, 6.0],
        positiveWeights: [3, 3, 3, 2, 1, 1],
        negativeWeights: [2, 2, 2, 1, 2, 1, 1, 0],
        use10Scale: true, // 使用 10 點量表
      ),
    ];
  }

  // ============================================================
  // 危險警訊：在整個時間範圍內極少量加入自殺意念
  // ============================================================
  /// 在指定日期範圍內，隨機挑選少量日期加入自殺意念
  static List<DateTime> _pickDangerDates(
    DateTime startDate,
    DateTime endDate,
    int count,
  ) {
    final totalDays = endDate.difference(startDate).inDays;
    if (totalDays <= 0 || count <= 0) return [];

    final picked = <DateTime>{};
    int attempts = 0;
    while (picked.length < count && attempts < totalDays * 3) {
      attempts++;
      final offset = _rng.nextInt(totalDays + 1);
      final date = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).add(Duration(days: offset));
      // 避免集中在同一週
      final tooClose = picked.any((d) => d.difference(date).abs().inDays < 14);
      if (!tooClose) {
        picked.add(date);
      }
    }
    return picked.toList()..sort();
  }

  // ============================================================
  // 主要產生邏輯
  // ============================================================
  /// 產生測試資料並寫入 Firestore + 本地 SQLite
  /// [progressCallback] 可選，用於回報進度 (0.0 ~ 1.0)
  static Future<int> generateTestData({
    required String userId,
    int totalDays = 365,
    void Function(double progress)? progressCallback,
  }) async {
    final daysToGenerate = totalDays.clamp(30, 730);
    _rng = Random(42 + daysToGenerate);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scenarios = _buildScenarios(totalDays: daysToGenerate);
    final allRecords = <Map<String, dynamic>>[];

    // ── 1. 產生各情境的資料 ──
    for (final scenario in scenarios) {
      final startOffset = scenario['startDayOffset'] as int;
      final duration = scenario['durationDays'] as int;
      final density = scenario['recordDensity'] as int;
      final posRange = scenario['positiveRange'] as List<double>;
      final negRange = scenario['negativeRange'] as List<double>;
      final posWeights = scenario['positiveWeights'] as List<int>;
      final negWeights = scenario['negativeWeights'] as List<int>;
      final use10Scale = scenario['use10Scale'] as bool;

      final scenarioEndDate = today.subtract(Duration(days: startOffset));
      final scenarioStartDate =
          scenarioEndDate.subtract(Duration(days: duration - 1));

      // 計算這區間內要產生幾天
      final totalDays = duration;
      final targetRecords = ((duration / 7) * density).round();
      final actualRecords = targetRecords.clamp(1, totalDays);

      // 決定哪些天有紀錄
      final recordedDays = <DateTime>{};
      final allDays = List.generate(
        totalDays,
        (i) => DateTime(
          scenarioStartDate.year,
          scenarioStartDate.month,
          scenarioStartDate.day,
        ).add(Duration(days: i)),
      );

      // 確保有連續 7 天的區段
      if (duration >= 10) {
        final maxStart = duration - 7;
        if (maxStart > 0) {
          final consecutiveStart = _rng.nextInt(maxStart);
          for (int i = 0; i < 7; i++) {
            if (consecutiveStart + i < allDays.length) {
              recordedDays.add(allDays[consecutiveStart + i]);
            }
          }
        }
      }

      // 補滿到 targetRecords
      final remaining = allDays.where((d) => !recordedDays.contains(d)).toList()
        ..shuffle(_rng);
      final needed = actualRecords - recordedDays.length;
      for (int i = 0; i < needed && i < remaining.length; i++) {
        recordedDays.add(remaining[i]);
      }

      // 對每個有紀錄的天產生情緒資料
      for (final date in recordedDays) {
        final dayProgress = (date.difference(scenarioStartDate).inDays /
            (scenarioEndDate.difference(scenarioStartDate).inDays + 1));

        // 正向分數：在範圍內隨機，但可隨時間微調
        final posBase =
            posRange[0] + (posRange[1] - posRange[0]) * _rng.nextDouble();
        // 負向分數
        final negBase =
            negRange[0] + (negRange[1] - negRange[0]) * _rng.nextDouble();

        // 壓力上升期：負向隨時間增加
        final isStressRising = scenario['label'] == '壓力上升期';
        // 恢復期：正向隨時間增加
        final isRecovery = scenario['label'] == '恢復期';

        double posScore;
        double negScore;
        if (isStressRising) {
          posScore = posBase * (1.0 - dayProgress * 0.3);
          negScore = negBase * (1.0 + dayProgress * 0.5);
        } else if (isRecovery) {
          posScore = posBase * (1.0 + dayProgress * 0.3);
          negScore = negBase * (1.0 - dayProgress * 0.3);
        } else {
          posScore = posBase;
          negScore = negBase;
        }

        // 轉換為對應量表的整數分數
        int toScaleValue(double val, bool is10Scale) {
          if (is10Scale) {
            return (val * 2).round().clamp(0, 10);
          } else {
            return val.round().clamp(0, 5);
          }
        }

        // 建立情緒列表
        final emotions = <Map<String, dynamic>>[];

        // 加入正向情緒
        for (int i = 0; i < kPositiveEmotions.length; i++) {
          if (_weightedBool(posWeights[i])) {
            final score = toScaleValue(
              posScore * (0.7 + _rng.nextDouble() * 0.6),
              use10Scale,
            );
            if (score > 0) {
              emotions.add({'name': kPositiveEmotions[i], 'value': score});
            }
          }
        }

        // 加入負向情緒
        for (int i = 0; i < kNegativeEmotions.length; i++) {
          if (kNegativeEmotions[i] == '自殺意念') {
            // 自殺意念由 dangerDates 控制，不在這裡隨機產生
            continue;
          }
          if (_weightedBool(negWeights[i])) {
            final score = toScaleValue(
              negScore * (0.7 + _rng.nextDouble() * 0.6),
              use10Scale,
            );
            if (score > 0) {
              emotions.add({'name': kNegativeEmotions[i], 'value': score});
            }
          }
        }

        // 計算 overallMood
        double? overallMood;
        if (emotions.isNotEmpty) {
          final sum =
              emotions.fold<int>(0, (acc, e) => acc + (e['value'] as int));
          overallMood = sum / emotions.length;
        }

        allRecords.add({
          'date': date,
          'emotions': emotions,
          'overallMood': overallMood,
          'moodScale': use10Scale ? 10 : 5,
          'isTestData': true,
          'source': kTestSource,
        });
      }
    }

    // ── 2. 加入危險警訊（自殺意念）──
    // 只在整個範圍內加入 2~3 筆
    final allDates = allRecords.map((r) => r['date'] as DateTime).toSet();
    if (allDates.isNotEmpty) {
      final sortedDates = allDates.toList()..sort();
      final dangerDates = _pickDangerDates(
        sortedDates.first,
        sortedDates.last,
        min(5, max(2, (daysToGenerate / 90).round())),
      );
      for (final dangerDate in dangerDates) {
        // 找這天有沒有既有紀錄
        final existing = allRecords.where((r) {
          final d = r['date'] as DateTime;
          return d.year == dangerDate.year &&
              d.month == dangerDate.month &&
              d.day == dangerDate.day;
        }).toList();

        if (existing.isNotEmpty) {
          // 在既有紀錄中加入自殺意念
          for (final record in existing) {
            final emotions = record['emotions'] as List<Map<String, dynamic>>;
            // 檢查是否已有自殺意念
            final hasDanger = emotions.any((e) => e['name'] == '自殺意念');
            if (!hasDanger) {
              emotions.add({'name': '自殺意念', 'value': 3});
            }
          }
        } else {
          // 這天原本沒紀錄，新增一筆只有自殺意念的紀錄
          allRecords.add({
            'date': dangerDate,
            'emotions': [
              {'name': '自殺意念', 'value': 3},
            ],
            'overallMood': 3.0,
            'moodScale': 5,
            'isTestData': true,
            'source': kTestSource,
          });
        }
      }
    }

    final trendPoints = EmotionTrendCalculator.calculate(
      allRecords.map(_toDailyRecord).toList(),
    );
    final hasClassifiedTrend =
        trendPoints.any((point) => point.hasClassifiedData);
    if (!hasClassifiedTrend) {
      throw StateError('測試資料未產生可供正式趨勢圖分類的情緒資料');
    }

    // ── 3. 透過正式每日紀錄 repository 寫入 ──
    allRecords.sort(
      (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
    );
    final total = allRecords.length;
    int written = 0;
    final repo = DailyRecordRepository();

    for (final record in allRecords) {
      final date = record['date'] as DateTime;
      final docId = DateHelper.toId(date);
      final emotions = record['emotions'] as List<Map<String, dynamic>>;
      final moodScale = record['moodScale'] as int;

      try {
        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('dailyRecords')
            .doc(docId);
        final cloudDoc = await ref.get();
        final cloudData = cloudDoc.data() == null
            ? null
            : await HealthDataEncryptionService.decryptData(cloudDoc.data()!);
        final isOwnedTestRecord =
            cloudData != null && _isOwnedTestRecord(cloudData);
        final localData = await repo.getDailyRecord(userId: userId, date: date);

        if ((cloudDoc.exists || localData != null) && !isOwnedTestRecord) {
          debugPrint('⏭️ Skip existing real record: $docId');
          written++;
          if (progressCallback != null) {
            progressCallback(written / total);
          }
          continue;
        }

        final emotionsMap = <String, dynamic>{};
        for (final e in emotions) {
          emotionsMap[e['name'] as String] = e['value'] as int;
        }

        await repo.saveDailyRecord(
          id: docId,
          userId: userId,
          date: date,
          emotions: emotionsMap,
          emotionSectionCompleted: true,
          symptomSectionCompleted: false,
          stateSectionCompleted: false,
          moodScale: moodScale,
        );

        await HealthDataEncryptionService.setEncrypted(ref, {
          kTestFlagField: true,
          kTestOwnedField: true,
          'source': kTestSource,
          'testGeneratedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('⚠️ Test record save failed for $docId: $e');
      }

      written++;
      if (progressCallback != null) {
        progressCallback(written / total);
      }
    }

    debugPrint('✅ Test data generation complete: $written records written');
    return written;
  }

  static bool _isOwnedTestRecord(Map<String, dynamic> data) {
    return data[kTestFlagField] == true &&
        data[kTestOwnedField] == true &&
        data['source'] == kTestSource;
  }

  static DailyRecord _toDailyRecord(Map<String, dynamic> record) {
    final date = record['date'] as DateTime;
    final emotions = (record['emotions'] as List<Map<String, dynamic>>)
        .map((e) => Emotion(
              name: e['name'] as String,
              value: e['value'] as int?,
            ))
        .toList();

    return DailyRecord(
      id: DateHelper.toId(date),
      date: date,
      emotions: emotions,
      overallMood: record['overallMood'] as double?,
      moodScale: record['moodScale'] as int,
    );
  }

  // ============================================================
  // 刪除測試資料
  // ============================================================
  /// 只刪除由新版測試資料產生器建立、明確標記為 owned 的紀錄。
  static Future<int> deleteTestData({
    required String userId,
    void Function(double progress)? progressCallback,
  }) async {
    int deleted = 0;

    // 從 Firestore 找出所有測試資料
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('dailyRecords')
          .where(kTestOwnedField, isEqualTo: true)
          .get();

      final total = snapshot.docs.length;
      int processed = 0;

      for (final doc in snapshot.docs) {
        try {
          await doc.reference.delete();
          deleted++;
        } catch (e) {
          debugPrint('⚠️ Firestore delete failed for ${doc.id}: $e');
        }

        // 也從本地 SQLite 刪除
        try {
          final repo = DailyRecordRepository();
          await repo.deleteDailyRecord(doc.id);
        } catch (e) {
          debugPrint('⚠️ Local delete failed for ${doc.id}: $e');
        }

        processed++;
        if (progressCallback != null) {
          progressCallback(processed / total);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Firestore query for test data failed: $e');
      // 如果 Firestore 查詢失敗（可能沒有複合索引），改用逐筆讀取
      debugPrint('⚠️ Falling back to scanning all records...');
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('dailyRecords')
            .get();

        int processed = 0;
        final total = snapshot.docs.length;

        for (final doc in snapshot.docs) {
          final data =
              await HealthDataEncryptionService.decryptData(doc.data());
          if (_isOwnedTestRecord(data)) {
            try {
              await doc.reference.delete();
              deleted++;
            } catch (e) {
              debugPrint('⚠️ Firestore delete failed for ${doc.id}: $e');
            }

            try {
              final repo = DailyRecordRepository();
              await repo.deleteDailyRecord(doc.id);
            } catch (e) {
              debugPrint('⚠️ Local delete failed for ${doc.id}: $e');
            }
          }
          processed++;
          if (progressCallback != null) {
            progressCallback(processed / total);
          }
        }
      } catch (e2) {
        debugPrint('❌ Fallback scan also failed: $e2');
      }
    }

    debugPrint('✅ Test data deletion complete: $deleted records deleted');
    return deleted;
  }

  // ============================================================
  // 檢查是否已有測試資料
  // ============================================================
  static Future<bool> hasTestData({required String userId}) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('dailyRecords')
          .where(kTestOwnedField, isEqualTo: true)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ hasTestData check failed: $e');
      return false;
    }
  }

  // ============================================================
  // 取得測試資料統計
  // ============================================================
  static Future<Map<String, dynamic>> getTestDataStats({
    required String userId,
  }) async {
    int count = 0;
    int minScale = 10;
    int maxScale = 5;
    DateTime? earliest;
    DateTime? latest;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('dailyRecords')
          .where(kTestOwnedField, isEqualTo: true)
          .orderBy('date', descending: true)
          .get();

      count = snapshot.docs.length;
      for (final doc in snapshot.docs) {
        final data = await HealthDataEncryptionService.decryptData(doc.data());
        final scale = (data['moodScale'] as num?)?.toInt() ?? 10;
        if (scale < minScale) minScale = scale;
        if (scale > maxScale) maxScale = scale;

        final date = (data['date'] as Timestamp?)?.toDate();
        if (date != null) {
          if (earliest == null || date.isBefore(earliest)) earliest = date;
          if (latest == null || date.isAfter(latest)) latest = date;
        }
      }
    } catch (e) {
      debugPrint('⚠️ getTestDataStats failed: $e');
    }

    return {
      'count': count,
      'earliest': earliest,
      'latest': latest,
      'scaleRange': '$minScale ~ $maxScale',
    };
  }

  // ============================================================
  // 工具方法
  // ============================================================
  static bool _weightedBool(int weight) {
    if (weight <= 0) return false;
    return _rng.nextInt(10) < weight;
  }
}
