// record_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_record_page.dart';
import '../utils/date_helper.dart';
import '../models/daily_record.dart';

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
  int _reload = 0; // 控制重新載入

  Future<Map<String, dynamic>?> _fetch() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('dailyRecords')
        .doc(widget.docId)
        .get();
    return snap.data();
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除當日紀錄')),
    );

    Navigator.pop(context); // 返回上一頁（歷程頁）
  } catch (e) {
    debugPrint('刪除當日紀錄錯誤: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('刪除失敗：$e')),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    final docRef = FirebaseFirestore.instance
        .collection('users').doc(widget.uid)
        .collection('dailyRecords').doc(widget.docId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        // 1. 處理載入中與錯誤
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const Scaffold(body: Center(child: Text('找不到資料')));
        }

        // 2. 🔥 核心改變：一行代碼將 Map 轉為強型別物件
        final record = DailyRecord.fromFirestore(snap.data!);
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
                ...record.symptoms.map((s) => ListTile(title: Text(s))),

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
