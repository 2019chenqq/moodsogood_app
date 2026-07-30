// record_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'edit_record_page.dart';
import '../utils/date_helper.dart';
import '../models/daily_record.dart';
import 'daily_record_repository.dart';
import '../constants/healing_design_system.dart';
import '../analytics_service.dart';
import '../utils/health_data_encryption_service.dart';

class RecordDetailScreen extends StatefulWidget {
  final String uid;
  final String docId;
  final bool autoOpenEditor;

  const RecordDetailScreen({
    super.key,
    required this.uid,
    required this.docId,
    this.autoOpenEditor = false,
  });

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('record_detail_screen');
  }

  /// 從本地 SQLite 和 Firebase 加載混合數據
  Future<DailyRecord?> _loadMergedRecord() async {
    final date = DateHelper.parseIdToDate(widget.docId);
    if (date == null) {
      debugPrint('❌ Failed to parse date from docId: ${widget.docId}');
      return null;
    }

    // 1. 先嘗試本地
    try {
      final repo = DailyRecordRepository();
      final localData =
          await repo.getDailyRecord(userId: widget.uid, date: date);
      if (localData != null) {
        debugPrint('✅ Loaded record from local SQLite: ${widget.docId}');
        return _convertLocalToRecord(localData, date);
      }
    } catch (e) {
      debugPrint('⚠️  Local load failed: $e');
    }

    // 2. 再嘗試 Firebase
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('dailyRecords')
          .doc(widget.docId)
          .get();

      if (snap.exists && snap.data() != null) {
        debugPrint('✅ Loaded record from Firebase: ${widget.docId}');
        final data =
            await HealthDataEncryptionService.decryptData(snap.data()!);
        return DailyRecord.fromData(snap.id, data);
      }
    } catch (e) {
      debugPrint('⚠️  Firebase load failed: $e');
    }

    return null;
  }

  /// 從本地 Map 轉換為 DailyRecord
  DailyRecord _convertLocalToRecord(Map<String, dynamic> data, DateTime date) {
    List<Emotion> emotions = [];
    if (data['emotions'] != null) {
      try {
        final rawEmotions = data['emotions'];
        if (rawEmotions is List) {
          emotions = rawEmotions
              .whereType<Map>()
              .map((item) => Emotion.fromMap(Map<String, dynamic>.from(item)))
              .toList();
        } else {
          final emotionMap = rawEmotions is String
              ? jsonDecode(rawEmotions) as Map<String, dynamic>
              : (rawEmotions as Map).cast<String, dynamic>();
          emotionMap.forEach((name, value) {
            emotions.add(Emotion(name: name, value: value as int?));
          });
        }
      } catch (e) {
        debugPrint('❌ Failed to parse emotions: $e');
      }
    }

    List<String> symptoms = [];
    if (data['bodySymptoms'] != null) {
      try {
        List<dynamic> symptomList;
        if (data['bodySymptoms'] is String) {
          symptomList = jsonDecode(data['bodySymptoms']) as List<dynamic>;
        } else if (data['bodySymptoms'] is List) {
          symptomList = data['bodySymptoms'] as List<dynamic>;
        } else {
          throw TypeError();
        }
        symptoms = symptomList.cast<String>();
      } catch (e) {
        debugPrint('❌ Failed to parse symptoms: $e');
      }
    }

    SleepData sleepData = SleepData();
    if (data['sleep'] != null) {
      try {
        Map<String, dynamic> sleepMap;
        if (data['sleep'] is String) {
          sleepMap = jsonDecode(data['sleep']) as Map<String, dynamic>;
        } else if (data['sleep'] is Map) {
          sleepMap = data['sleep'] as Map<String, dynamic>;
        } else {
          throw TypeError();
        }
        sleepData = _parseSleepDataFromMap(sleepMap);
      } catch (e) {
        debugPrint('❌ Failed to parse sleep: $e');
      }
    }

    bool isPeriod = false;
    String? periodStartId;
    String? periodEndId;
    if (data['periodData'] != null) {
      try {
        Map<String, dynamic> periodMap;
        if (data['periodData'] is String) {
          periodMap = jsonDecode(data['periodData']) as Map<String, dynamic>;
        } else if (data['periodData'] is Map) {
          periodMap = data['periodData'] as Map<String, dynamic>;
        } else {
          throw TypeError();
        }
        isPeriod = periodMap['isPeriod'] ?? false;
        periodStartId = periodMap['periodStartId'];
        periodEndId = periodMap['periodEndId'];
      } catch (e) {
        debugPrint('❌ Failed to parse periodData: $e');
      }
    }

    return DailyRecord(
      id: data['id'] ?? widget.docId,
      date: date,
      emotions: emotions,
      symptoms: symptoms,
      sleep: sleepData,
      isPeriod: isPeriod,
      periodStartId: periodStartId,
      periodEndId: periodEndId,
    );
  }

  /// 解析睡眠數據
  SleepData _parseSleepDataFromMap(Map<String, dynamic> sleepMap) {
    return SleepData(
      tookHypnotic: sleepMap['tookHypnotic'] ?? false,
      hypnoticName: sleepMap['hypnoticName'],
      hypnoticDose: sleepMap['hypnoticDose'],
      sleepTime: sleepMap['sleepTime'] != null
          ? DateHelper.parseTime(sleepMap['sleepTime'])
          : null,
      wakeTime: sleepMap['wakeTime'] != null
          ? DateHelper.parseTime(sleepMap['wakeTime'])
          : null,
      finalWakeTime: sleepMap['finalWakeTime'] != null
          ? DateHelper.parseTime(sleepMap['finalWakeTime'])
          : null,
      midWakeList: sleepMap['midWakeList'],
      flags: List<String>.from(sleepMap['flags'] ?? []),
      note: sleepMap['note'],
      quality: sleepMap['quality'],
      naps: (sleepMap['naps'] as List?)
              ?.map((n) => NapItem(
                    start: DateHelper.parseTime(n['start']) ??
                        const TimeOfDay(hour: 0, minute: 0),
                    end: DateHelper.parseTime(n['end']) ??
                        const TimeOfDay(hour: 0, minute: 0),
                  ))
              .toList() ??
          [],
    );
  }

// 將 flags（英文字串）轉為中文，並固定顯示順序
  String _prettyFlags(List<String> keys) {
    if (keys.isEmpty) return '-';

    // 顯示順序
    const order = <String>[
      'good', // 優
      'ok', // 良好
      'earlyWake', // 早醒
      'dreams', // 多夢
      'lightSleep', // 淺眠
      'nocturia', // 夜尿
      'fragmented', // 睡睡醒醒
      'insufficient', // 睡眠不足
      'initInsomnia', // 入睡困難
      'interrupted', // 睡眠中斷
    ];

    const label = <String, String>{
      'good': '優',
      'ok': '良好',
      'earlyWake': '早醒',
      'dreams': '多夢',
      'lightSleep': '淺眠',
      'nocturia': '夜尿',
      'fragmented': '睡睡醒醒',
      'insufficient': '睡眠不足',
      'initInsomnia': '入睡困難 (躺超過 30 分鐘才入睡)',
      'interrupted': '睡眠中斷 (醒來超過 30 分鐘才又入睡)',
    };

    final out = <String>[];
    for (final k in order) {
      if (keys.contains(k)) {
        // 如果有對應中文就顯示，沒有就顯示原英文 key
        out.add(label[k] ?? k);
      }
    }
    return out.isEmpty ? '-' : out.join('、');
  }

  Future<void> _clearRecord(BuildContext context) async {
    final uid = widget.uid;
    final docId = widget.docId;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
          ),
          title: const Text('清除這一天的紀錄？',
              style: TextStyle(fontWeight: FontWeight.w600)),
          content: Text(
            '所有情緒、症狀、睡眠、生理期資料都會被清除，無法復原。',
            style: TextStyle(
                color: HealingDesignSystem.adaptiveSecondaryText(context)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                '取消',
                style: TextStyle(
                    color: HealingDesignSystem.adaptiveSecondaryText(context)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HealingDesignSystem.dangerRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(HealingDesignSystem.radiusM),
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .doc(docId)
          .delete();

      if (!mounted) return;

      messenger.showSnackBar(
        const SnackBar(content: Text('已清除當日紀錄')),
      );

      navigator.pop(); // 返回上一頁（歷程頁）
    } catch (e) {
      debugPrint('刪除當日紀錄錯誤: $e');
      messenger.showSnackBar(
        SnackBar(content: Text('刪除失敗：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DailyRecord?>(
      future: _loadMergedRecord(),
      builder: (context, snap) {
        // 1. 處理載入中與錯誤
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final record = snap.data;
        if (record == null) {
          return const Scaffold(body: Center(child: Text('找不到資料')));
        }

        final sleep = record.sleep;

        return Scaffold(
          backgroundColor: HealingDesignSystem.adaptiveBackground(context),
          appBar: AppBar(
            backgroundColor:
                HealingDesignSystem.adaptiveAppBarBackground(context),
            foregroundColor:
                HealingDesignSystem.adaptiveAppBarForeground(context),
            elevation: 0,
            title: Text(
              DateHelper.toDisplay(record.date),
              style: TextStyle(
                color: HealingDesignSystem.adaptiveAppBarForeground(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '編輯',
                onPressed: () async {
                  try {
                    // 這裡把 Model 轉回 Map 傳給編輯頁 (保持相容性)
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditRecordPage(
                          uid: widget.uid,
                          docId: widget.docId,
                          initData: record.toFirestore(), // Model -> Map
                        ),
                      ),
                    );

                    // 如果編輯頁返回 true，觸發畫面更新
                    if (changed == true) {
                      setState(() {});
                    }
                  } catch (e) {
                    debugPrint('開啟編輯頁錯誤：$e');
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '清除當日資料',
                onPressed: () => _clearRecord(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ===== 情緒 =====
              _sectionHeader(context, '情緒'),
              Container(
                margin: const EdgeInsets.only(bottom: 18),
                decoration: HealingDesignSystem.adaptiveCardDecoration(
                  context,
                  bgColor: HealingDesignSystem.adaptiveSurface(context),
                ),
                child: Column(
                  children: [
                    if (record.emotions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('無情緒紀錄',
                            style: HealingDesignSystem.bodySmall.copyWith(
                                color:
                                    HealingDesignSystem.adaptiveSecondaryText(
                                        context))),
                      ),
                    ...record.emotions.map((e) => ListTile(
                          title: Text(e.name,
                              style: HealingDesignSystem.bodyMedium.copyWith(
                                  color:
                                      HealingDesignSystem.adaptivePrimaryText(
                                          context))),
                          trailing: Text(
                            e.value == null ? '-' : '${e.value}',
                            style: HealingDesignSystem.bodyMedium.copyWith(
                                color: HealingDesignSystem.adaptivePrimaryText(
                                    context),
                                fontWeight: FontWeight.w600),
                          ),
                        )),
                  ],
                ),
              ),

              // ===== 症狀 =====
              _sectionHeader(context, '症狀'),
              Container(
                margin: const EdgeInsets.only(bottom: 18),
                decoration: HealingDesignSystem.adaptiveCardDecoration(
                  context,
                  bgColor: HealingDesignSystem.adaptiveSurface(context),
                ),
                child: record.symptoms.isEmpty
                    ? Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            '無症狀紀錄',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: HealingDesignSystem.adaptiveSecondaryText(
                                  context),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Text(
                          record.symptoms
                              .where((s) => s.trim().isNotEmpty)
                              .join('、'),
                          style: HealingDesignSystem.bodyMedium.copyWith(
                              color: HealingDesignSystem.adaptivePrimaryText(
                                  context)),
                        ),
                      ),
              ),

              // ===== 睡眠 =====
              _sectionHeader(context, '睡眠'),
              Container(
                margin: const EdgeInsets.only(bottom: 18),
                decoration: HealingDesignSystem.adaptiveCardDecoration(
                  context,
                  bgColor: HealingDesignSystem.adaptiveSurface(context),
                ),
                child: Column(
                  children: [
                    _detailTile(
                        context, '前一晚是否服用安眠藥', sleep.tookHypnotic ? '有' : '無'),
                    if (sleep.tookHypnotic) ...[
                      _detailTile(
                          context,
                          '藥物名稱',
                          (sleep.hypnoticName ?? '').isEmpty
                              ? '-'
                              : sleep.hypnoticName!),
                      _detailTile(
                          context,
                          '劑量',
                          (sleep.hypnoticDose ?? '').isEmpty
                              ? '-'
                              : sleep.hypnoticDose!),
                    ],
                    _detailTile(context, '入睡時間',
                        DateHelper.formatTime(sleep.sleepTime)),
                    _detailTile(context, '夜間睡眠狀況', _prettyFlags(sleep.flags)),
                    _detailTile(
                        context,
                        '夜間醒來時間',
                        sleep.midWakeList == null ||
                                sleep.midWakeList!.trim().isEmpty
                            ? '-'
                            : sleep.midWakeList!),
                    _detailTile(context, '自覺睡眠品質',
                        sleep.quality == null ? '-' : '${sleep.quality}'),
                    if ((sleep.note ?? '').isNotEmpty)
                      ListTile(
                        title: Text('睡眠註記',
                            style: HealingDesignSystem.bodyMedium.copyWith(
                                color:
                                    HealingDesignSystem.adaptiveSecondaryText(
                                        context))),
                        subtitle: Text(sleep.note!,
                            style: HealingDesignSystem.bodyMedium.copyWith(
                                color: HealingDesignSystem.adaptivePrimaryText(
                                    context))),
                      ),
                    _detailTile(
                        context,
                        '甦醒時間',
                        DateHelper.formatTime(
                            sleep.finalWakeTime ?? sleep.wakeTime)),
                    _detailTile(context, '起床開始活動時間',
                        DateHelper.formatTime(sleep.wakeTime)),
                    // 小睡
                    if (sleep.naps.isNotEmpty)
                      ListTile(
                        title: Text('小睡',
                            style: HealingDesignSystem.bodyMedium.copyWith(
                                color:
                                    HealingDesignSystem.adaptiveSecondaryText(
                                        context))),
                        subtitle: Text(
                          sleep.naps.map((nap) {
                            final s = DateHelper.formatTime(nap.start);
                            final e = DateHelper.formatTime(nap.end);
                            final dur = DateHelper.formatDurationText(
                                nap.durationMinutes);
                            return '$s → $e （$dur）';
                          }).join('\n'),
                          style: HealingDesignSystem.bodyMedium.copyWith(
                              color: HealingDesignSystem.adaptivePrimaryText(
                                  context)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
//     String _buildPeriodText(DailyRecord r) {
//   if (r.isPeriod == true) {
//     return '🌸 生理期';
//   }
//   return '—';
}

/// 區塊標題
Widget _sectionHeader(BuildContext context, String title,
    {VoidCallback? onEdit}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: HealingDesignSystem.adaptiveAccent(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: HealingDesignSystem.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: HealingDesignSystem.adaptiveAccent(context),
            ),
          ),
        ),
        if (onEdit != null)
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              color: HealingDesignSystem.adaptiveAccent(context),
            ),
            tooltip: '編輯$title',
            onPressed: onEdit,
          ),
      ],
    ),
  );
}

/// 明細行
Widget _detailTile(BuildContext context, String label, String value) {
  return ListTile(
    dense: true,
    title: Text(label,
        style: HealingDesignSystem.bodyMedium.copyWith(
          color: HealingDesignSystem.adaptiveSecondaryText(context),
        )),
    trailing: Text(value,
        style: HealingDesignSystem.bodyMedium.copyWith(
          color: HealingDesignSystem.adaptivePrimaryText(context),
          fontWeight: FontWeight.w600,
        )),
  );
}

Future<void> openEmotionEditor(
  BuildContext context,
  String uid,
  String docId,
  List<Map> emotions,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('編輯情緒',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // TODO: 放你的情緒編輯 UI（滾輪 / Dropdown / TextField ...）
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  // TODO: 將 emotions 寫回 Firestore（users/uid/dailyRecords/docId）
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('情緒已更新')));
                },
                child: const Text('送出'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
