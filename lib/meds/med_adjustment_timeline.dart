import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MedicationAdjustmentTimeline extends StatelessWidget {
  final void Function(String adjustId, Map<String, dynamic> data)? onTapItem;

  const MedicationAdjustmentTimeline({super.key, this.onTapItem});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('請先登入'));
    }

    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medAdjustments')
        .orderBy('date', descending: true)
        .limit(50);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('讀取失敗：${snap.error}'));
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyTimeline();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();

            final ts = data['date'];
            final date = (ts is Timestamp) ? ts.toDate() : DateTime.now();

            final note = (data['note'] as String?)?.trim() ?? '';
            final changes = (data['changes'] as List?)?.whereType<Map>().toList() ?? [];

            final title = _fmtYmd(date);
            final subtitle = _buildSummary(changes);

            return Card(
              elevation: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTapItem == null ? null : () => onTapItem!(doc.id, data),
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
                          Text('${changes.length} 項', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
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
    );
  }

  static String _fmtYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  static String _buildSummary(List<Map> changes) {
    if (changes.isEmpty) return '（尚無變更內容）';

    // 取前 3 項做摘要
    final items = changes.take(3).map((c) {
      final nameZh = (c['nameZh'] ?? '').toString();
      final nameEn = (c['nameEn'] ?? '').toString();
      final name = nameZh.isNotEmpty ? nameZh : (nameEn.isNotEmpty ? nameEn : '未命名藥物');

      final action = (c['action'] ?? '').toString();
      final before = c['doseBefore'];
      final after = c['doseAfter'];
      final unit = (c['unit'] ?? '').toString();

      if (action == 'stop') return '$name：停藥';
      if (action == 'add') return '$name：新增 ${(after ?? '')} $unit';
      if (action == 'injection') return '$name：注射 ${(after ?? '')} $unit';
      if (action == 'adjust') return '$name：${before ?? ''}→${after ?? ''} $unit';
      return '$name：維持';
    }).toList();

    final more = changes.length > 3 ? '…等 ${changes.length} 項' : '';
    return '${items.join('、')} $more'.trim();
  }
}

class _EmptyTimeline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.history_toggle_off, size: 40),
          const SizedBox(height: 10),
          Text('尚無回診／調藥紀錄', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text('建立第一筆「紀錄調整」後，這裡會自動形成時間線。', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
