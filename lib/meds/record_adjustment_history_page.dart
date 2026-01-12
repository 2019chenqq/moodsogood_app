import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RecordAdjustmentHistoryPage extends StatelessWidget {
  const RecordAdjustmentHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('請先登入後使用')));
    }

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medAdjustments')
        .orderBy('date', descending: true)
        .limit(60);

    return Scaffold(
      appBar: AppBar(title: const Text('調藥時間線')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('讀取失敗：${snap.error}'));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('尚無調藥紀錄。\n建立第一筆「紀錄調整」後，這裡會自動形成時間線。', textAlign: TextAlign.center),
            ));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data();

              final ts = d['date'];
              final date = (ts is Timestamp) ? ts.toDate() : DateTime.now();
              final note = (d['note'] as String?)?.trim() ?? '';
              final items = (d['items'] as List?)?.whereType<Map>().toList() ?? const [];

              final title = _fmtYmd(date);
              final summary = _buildSummary(items);

              return Card(
                elevation: 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showDetailSheet(context, title, note, items),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timeline, size: 18),
                            const SizedBox(width: 8),
                            Text(title, style: Theme.of(context).textTheme.titleSmall),
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
  /// { name, type(unchanged/doseChanged/stopped), oldDose, newDose, unit, stopReason }
  static String _buildSummary(List<Map> items) {
    if (items.isEmpty) return '（本次沒有任何變更）';

    String fmtItem(Map it) {
      final name = (it['name'] ?? '未命名藥物').toString();
      final type = (it['type'] ?? 'unchanged').toString();
      final unit = (it['unit'] ?? '').toString();
      final oldDose = it['oldDose'];
      final newDose = it['newDose'];

      switch (type) {
        case 'doseChanged':
          return '$name：${oldDose ?? ''}→${newDose ?? ''} $unit';
        case 'stopped':
          return '$name：停藥';
        default:
          return '$name：維持';
      }
    }

    final shown = items.take(3).map(fmtItem).toList();
    final more = items.length > 3 ? '…等 ${items.length} 項' : '';
    return '${shown.join('、')} $more'.trim();
  }

  static void _showDetailSheet(BuildContext context, String title, String note, List<Map> items) {
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
                  final name = (it['name'] ?? '未命名藥物').toString();
                  final type = (it['type'] ?? 'unchanged').toString();
                  final unit = (it['unit'] ?? '').toString();
                  final oldDose = it['oldDose'];
                  final newDose = it['newDose'];
                  final stopReason = (it['stopReason'] ?? '').toString().trim();

                  String line;
                  if (type == 'doseChanged') {
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
