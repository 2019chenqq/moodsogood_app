// record_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'edit_record_page.dart';
import '../utils/date_helper.dart';
import '../models/daily_record.dart';
import 'daily_record_repository.dart';

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
      final localData = await repo.getDailyRecord(userId: widget.uid, date: date);
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
          .collection('users').doc(widget.uid)
          .collection('dailyRecords').doc(widget.docId)
          .get();
      
      if (snap.exists && snap.data() != null) {
        debugPrint('✅ Loaded record from Firebase: ${widget.docId}');
        return DailyRecord.fromFirestore(snap);
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
        Map<String, dynamic> emotionMap;
        if (data['emotions'] is String) {
          emotionMap = jsonDecode(data['emotions']) as Map<String, dynamic>;
        } else if (data['emotions'] is Map) {
          emotionMap = data['emotions'] as Map<String, dynamic>;
        } else {
          throw TypeError();
        }
        emotionMap.forEach((name, value) {
          emotions.add(Emotion(name: name, value: value as int?));
        });
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
      sleepTime: sleepMap['sleepTime'] != null ? DateHelper.parseTime(sleepMap['sleepTime']) : null,
      wakeTime: sleepMap['wakeTime'] != null ? DateHelper.parseTime(sleepMap['wakeTime']) : null,
      finalWakeTime: sleepMap['finalWakeTime'] != null ? DateHelper.parseTime(sleepMap['finalWakeTime']) : null,
      midWakeList: sleepMap['midWakeList'],
      flags: List<String>.from(sleepMap['flags'] ?? []),
      note: sleepMap['note'],
      quality: sleepMap['quality'],
      naps: (sleepMap['naps'] as List?)
          ?.map((n) => NapItem(
            start: DateHelper.parseTime(n['start']) ?? const TimeOfDay(hour: 0, minute: 0),
            end: DateHelper.parseTime(n['end']) ?? const TimeOfDay(hour: 0, minute: 0),
          ))
          .toList() ?? [],
    );
  }
  
// 將 flags（英文字串）轉為中文，並固定顯示順序
  String _prettyFlags(List<String> keys) {
    if (keys.isEmpty) return '-';

    // 顯示順序
    const order = <String>[
      'good',          // 優
      'ok',            // 良好
      'earlyWake',     // 早醒
      'dreams',        // 多夢
      'lightSleep',         // 淺眠
      'nocturia',      // 夜尿
      'fragmented',       // 睡睡醒醒
      'insufficient',          // 睡眠不足
      'initInsomnia',  // 入睡困難
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
        title: const Text('清除這一天的紀錄？'),
        content: const Text('所有情緒、症狀、睡眠、生理期資料都會被清除，無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        final record = snap.data;
        if (record == null) {
          return const Scaffold(body: Center(child: Text('找不到資料')));
        }

        final sleep = record.sleep;

        // 定義樣式
        final TextStyle titleStyle = const TextStyle(fontSize: 16, height: 1.2);
        final TextStyle valueStyle = const TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
        final TextStyle noteStyle = const TextStyle(fontSize: 13);

        return Scaffold(
          appBar: AppBar(
            // 使用 Helper 統一標題格式 (yyyy/MM/dd)
            title: Text(DateHelper.toDisplay(record.date)),
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
              if (record.emotions.isEmpty)
                const ListTile(title: Text('無情緒紀錄', style: TextStyle(color: Colors.grey))),
              ...record.emotions.map((e) => ListTile(
                    title: Text(e.name),
                    trailing: Text(
                      e.value == null ? '-' : '${e.value}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  )),

              const Divider(height: 32),

              // ===== 症狀 =====
              _sectionHeader(context, '症狀'),
              if (record.symptoms.isEmpty)
                const ListTile(title: Text('無症狀紀錄', style: TextStyle(color: Colors.grey)))
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    record.symptoms
                        .where((symptom) => symptom.trim().isNotEmpty)
                        .join('、'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),

              const Divider(height: 32),

              // ===== 睡眠 =====
              _sectionHeader(context, '睡眠'),

              ListTile(
                title: Text('前一晚是否服用安眠藥', style: titleStyle),
                trailing: Text(
                  sleep.tookHypnotic ? '有' : '無',
                  style: valueStyle,
                ),
              ),
              if (sleep.tookHypnotic) ...[
                ListTile(
                  title: Text('藥物名稱', style: titleStyle),
                  trailing: Text(
                    (sleep.hypnoticName ?? '').isEmpty ? '-' : sleep.hypnoticName!,
                    style: valueStyle,
                  ),
                ),
                ListTile(
                  title: Text('劑量', style: titleStyle),
                  trailing: Text(
                    (sleep.hypnoticDose ?? '').isEmpty ? '-' : sleep.hypnoticDose!,
                    style: valueStyle,
                  ),
                ),
              ],
              ListTile(
                title: Text('入睡時間', style: titleStyle),
                // 使用 Helper
                trailing: Text(
                  DateHelper.formatTime(sleep.sleepTime),
                  style: valueStyle,
                ),
              ),
              ListTile(
  title: Text('夜間睡眠狀況', style: titleStyle),
  trailing: Text(
    _prettyFlags(sleep.flags),
    style: valueStyle,
  ),
),
              ListTile(
  title: const Text('夜間醒來時間'),
  trailing: Text(
    sleep.midWakeList == null || sleep.midWakeList!.trim().isEmpty
        ? '-'
        : sleep.midWakeList!,
    style: valueStyle,
  ),
),
              ListTile(
                title: Text('自覺睡眠品質', style: titleStyle),
                trailing: Text(
                  sleep.quality == null ? '-' : '${sleep.quality}',
                  style: valueStyle,
                ),
              ),
              ListTile(
                title: Text('睡眠註記', style: titleStyle),
                subtitle: Text(
                  (sleep.note ?? '').isEmpty ? '-' : sleep.note!,
                  style: noteStyle,
                ),
              ),

              ListTile(
                title: Text('起床開始活動時間', style: titleStyle),
                trailing: Text(
                  DateHelper.formatTime(sleep.wakeTime),
                  style: valueStyle,
                ),
              ),

              // === 小睡 (使用 Model 的 naps) ===
              Builder(builder: (_) {
                if (sleep.naps.isEmpty) return const SizedBox.shrink();

                // 🔥 使用 Helper 處理顯示
                final text = sleep.naps.map((nap) {
                  final s = DateHelper.formatTime(nap.start);
                  final e = DateHelper.formatTime(nap.end);
                  final dur = DateHelper.formatDurationText(nap.durationMinutes);
                  return '$s → $e （$dur）';
                }).join('\n');

                return ListTile(
                  title: Text('小睡', style: titleStyle),
                  subtitle: Text(text, style: noteStyle),
                );
              }),
              // ===== 生理期 =====
// _sectionHeader(context, '生理期'),
// ListTile(
//   title: const Text('生理期狀態'),
//   trailing: Text(
//     _buildPeriodText(record),
//     style: valueStyle,
//   ),
// ),
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

/// 區塊標題＋右上角編輯鈕（頂層函式，別放進 class 裡）
Widget _sectionHeader(BuildContext context, String title, {VoidCallback? onEdit}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ),
        if (onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '編輯$title',
            onPressed: onEdit,
          ),
      ],
    ),
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
