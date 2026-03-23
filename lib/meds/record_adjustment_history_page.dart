import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'medication_local_db.dart';

class RecordAdjustmentHistoryPage extends StatefulWidget {
  const RecordAdjustmentHistoryPage({super.key});

  @override
  State<RecordAdjustmentHistoryPage> createState() => _RecordAdjustmentHistoryPageState();
}

class _RecordAdjustmentHistoryPageState extends State<RecordAdjustmentHistoryPage> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _loadFromLocal();
    // 背景同步 Firebase 資料到本地（非 await，異步執行）
    if (uid != null && !_initialized) {
      _initialized = true;
      _syncFromFirebase(uid);
    }
  }

  void _loadFromLocal() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('❌ uid 為 null，無法載入調整記錄');
      _future = Future.value([]);
    } else {
      debugPrint('📋 正在從本地 DB 載入調整記錄，uid: $uid');
      _future = MedicationLocalDB().getAdjustmentRecordsForDisplay(uid).then((records) {
        debugPrint('✅ 本地 DB 載入成功，共 ${records.length} 筆記錄');
        return records;
      }).catchError((e) {
        debugPrint('❌ 本地 DB 載入失敗：$e');
        return <Map<String, dynamic>>[];
      });
    }
  }

  Future<void> _syncFromFirebase(String uid) async {
    try {
      debugPrint('🔥 開始從 Firebase 同步調整記錄...');
      final query = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medAdjustments')
          .orderBy('date', descending: true)
          .limit(60);

      final snap = await query.get();
      final docs = snap.docs;
      debugPrint('🔥 Firebase 返回 ${docs.length} 筆記錄');

      for (final doc in docs) {
        final data = doc.data();
        final date = data['date'];
        final dateStr = (date is Timestamp)
            ? _fmtYmd(date.toDate())
            : (date is DateTime)
                ? _fmtYmd(date)
                : date.toString();

        await MedicationLocalDB().addAdjustmentRecord(uid, doc.id, {
          'date': dateStr,
          'note': data['note'],
          'items': data['items'] ?? [],
          'createdAt': data['createdAt']?.toString() ?? DateTime.now().toString(),
        });
      }

      debugPrint('✅ Firebase 同步完成，共 ${docs.length} 筆');
      // 同步後重新載入本地資料
      if (mounted) {
        setState(() => _loadFromLocal());
      }
    } catch (e) {
      debugPrint('⚠️ Firebase 同步失敗：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('請先登入後使用')));
    }

    // 確保 _future 已初始化
    if (!_initialized) {
      _initialized = true;
      _syncFromFirebase(uid);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('調藥時間線')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          debugPrint('📊 FutureBuilder state: ${snap.connectionState}, hasData: ${snap.hasData}, hasError: ${snap.hasError}');
          
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            debugPrint('❌ FutureBuilder error: ${snap.error}');
            return Center(child: Text('讀取失敗：${snap.error}'));
          }

          final records = snap.data ?? [];
          if (records.isEmpty) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('尚無調藥紀錄。\n建立第一筆「紀錄調整」後，這裡會自動形成時間線。', textAlign: TextAlign.center),
            ));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final record = records[i];

              final dateStr = record['date'] as String?;
              final note = (record['note'] as String?)?.trim() ?? '';
              final items = (record['items'] as List?)?.whereType<Map>().toList() ?? const [];

              final summary = _buildSummary(items);

              return Card(
                elevation: 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showDetailSheet(context, dateStr ?? '', note, items),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timeline, size: 18),
                            const SizedBox(width: 8),
                            Text(dateStr ?? '', style: Theme.of(context).textTheme.titleSmall),
                            const Spacer(),
                            Text('${items.length} 項',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(summary, style: Theme.of(context).textTheme.bodyMedium),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(note, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _fmtYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  /// 讀你目前的 items schema：
  /// { name, type(added/injected/doseChanged/stopped), oldDose, newDose, unit, stopReason }
  static String _buildSummary(List items) {
    if (items.isEmpty) return '（本次沒有任何變更）';

    String fmtItem(dynamic it) {
      if (it is! Map) return '';
      final name = (it['name'] ?? '未命名藥物').toString();
      final type = (it['type'] ?? 'unchanged').toString();
      final unit = (it['unit'] ?? '').toString();
      final oldDose = it['oldDose'];
      final newDose = it['newDose'];

      switch (type) {
        case 'added':
          return '$name：新增 ${newDose ?? ''} $unit';
        case 'injected':
          return '$name：已施打';
        case 'injection':
          return '$name：已施打';
        case 'doseChanged':
          return '$name：${oldDose ?? ''}→${newDose ?? ''} $unit';
        case 'stopped':
          return '$name：停藥';
        default:
          return '$name：維持';
      }
    }

    final shown = items.take(3).map(fmtItem).where((s) => s.isNotEmpty).toList();
    final more = items.length > 3 ? '…等 ${items.length} 項' : '';
    return '${shown.join('、')} $more'.trim();
  }

  static void _showDetailSheet(BuildContext context, String title, String note, List items) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(note, style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: 12),
                ...items.map((it) {
                  if (it is! Map) return const SizedBox.shrink();
                  
                  final name = (it['name'] ?? '未命名藥物').toString();
                  final type = (it['type'] ?? 'unchanged').toString();
                  final unit = (it['unit'] ?? '').toString();
                  final oldDose = it['oldDose'];
                  final newDose = it['newDose'];
                  final stopReason = (it['stopReason'] ?? '').toString().trim();

                  String line;
                  if (type == 'added') {
                    line = '新增：${newDose ?? ''} $unit';
                  } else if (type == 'injected' || type == 'injection') {
                    line = '已施打';
                  } else if (type == 'doseChanged') {
                    line = '調整：${oldDose ?? ''} → ${newDose ?? ''} $unit';
                  } else if (type == 'stopped') {
                    line = stopReason.isEmpty ? '停藥' : '停藥（原因：$stopReason）';
                  } else {
                    line = '維持原劑量';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.circle, size: 10),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(line, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
