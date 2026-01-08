import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'edit_medication_page.dart'; // 你剛做好的編輯頁

class MedicationDetailPage extends StatelessWidget {
  final String medId;
  const MedicationDetailPage({super.key, required this.medId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('請先登入')),
      );
    }

    final medRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medications')
        .doc(medId);

    final changesRef = medRef.collection('changes').orderBy('at', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('藥物詳情'),
        actions: [
          IconButton(
            tooltip: '編輯',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final snap = await medRef.get();
              if (!context.mounted) return;
              if (!snap.exists) return;

              final data = snap.data() as Map<String, dynamic>;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditMedicationPage(docId: medId, initialData: data),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: medRef.snapshots(),
        builder: (context, medSnap) {
          if (medSnap.hasError) {
            return Center(child: Text('讀取失敗：${medSnap.error}'));
          }
          if (!medSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final doc = medSnap.data!;
          if (!doc.exists) return const Center(child: Text('找不到這筆藥物'));

          final data = doc.data()!;
          final cs = Theme.of(context).colorScheme;

          final name = (data['name'] as String?) ?? '未命名';
          final unit = (data['unit'] as String?) ?? 'mg';
          final dose = _readDose(data['dose']);
          final times = (data['times'] as List?)?.whereType<String>().toList() ?? <String>[];
          final purposes = (data['purposes'] as List?)?.whereType<String>().toList() ?? <String>[];
          final purposeOther = (data['purposeOther'] as String?)?.trim();
          final bodySymptoms = (data['bodySymptoms'] as List?)?.whereType<String>().toList() ?? <String>[];

          final allPurposes = <String>[
  ...purposes,
  if (purposeOther != null && purposeOther.isNotEmpty) '其他：$purposeOther',
];

          final isActive = (data['isActive'] as bool?) ?? true;
          final startDate = _readDate(data['startDate']);
          final createdAt = _readDateTime(data['createdAt']);
          final updatedAt = _readDateTime(data['updatedAt']);

          // 把「主檔時間點」先變成 timeline event（即使你還沒做 changes 子集合也能顯示）
          final baseEvents = <_TimelineEvent>[
            if (startDate != null)
              _TimelineEvent(
                at: DateTime(startDate.year, startDate.month, startDate.day),
                title: '開始服用',
                subtitle: '開始日期：${_fmtYmd(startDate)}',
                icon: Icons.play_circle_outline,
              ),
            if (createdAt != null)
              _TimelineEvent(
                at: createdAt,
                title: '建立藥物',
                subtitle: '首次加入藥物清單',
                icon: Icons.add_circle_outline,
              ),
            if (updatedAt != null && createdAt != null && updatedAt.isAfter(createdAt))
              _TimelineEvent(
                at: updatedAt,
                title: '更新藥物資訊',
                subtitle: '藥物資料曾被更新',
                icon: Icons.edit_outlined,
              ),
            _TimelineEvent(
              at: DateTime.now(),
              title: isActive ? '目前服用中' : '已停用',
              subtitle: isActive ? '狀態：服用中' : '狀態：停用',
              icon: isActive ? Icons.check_circle_outline : Icons.pause_circle_outline,
            ),
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              // 顶部主卡（像你喜歡的柔和卡片感）
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primaryContainer.withOpacity(0.55),
                      cs.secondaryContainer.withOpacity(0.45),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: cs.surface.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.medication_outlined),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 4),
                              Text(
                                '${_doseLabel(dose)} $unit',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        _StatusPill(isActive: isActive),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (times.isNotEmpty) ...[
                      _MiniLabel('服用時間'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: times.map((t) => _Chip(text: t)).toList(),
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (allPurposes.isNotEmpty) ...[
                      _MiniLabel('用途'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allPurposes.map((p) => _Chip(text: p)).toList(),
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (bodySymptoms.isNotEmpty) ...[
                      _MiniLabel('身體症狀'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: bodySymptoms.map((s) => _Chip(text: s)).toList(),
                      ),
                      const SizedBox(height: 10),
                    ],

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('尚未建立「紀錄調整」頁面')),
                              );
                            },
                            icon: const Icon(Icons.tune),
                            label: const Text('紀錄調整'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final snap = await medRef.get();
                              if (!context.mounted) return;
                              if (!snap.exists) return;
                              final data = snap.data() as Map<String, dynamic>;
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EditMedicationPage(docId: medId, initialData: data),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('編輯'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Text('時間線', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Text(
                    '（由新到舊）',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 子集合 changes + 主檔 baseEvents 合併顯示
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: changesRef.snapshots(),
                builder: (context, chSnap) {
                  final events = <_TimelineEvent>[];

                  // 先放 changes（如果你還沒做 changes 也不會壞）
                  if (chSnap.hasData) {
                    for (final d in chSnap.data!.docs) {
                      final m = d.data();
                      final at = _readDateTime(m['at']) ?? DateTime.now();
                      final type = (m['type'] as String?) ?? 'note';
                      final title = _typeTitle(type);
                      final subtitle = _typeSubtitle(m);
                      events.add(
                        _TimelineEvent(
                          at: at,
                          title: title,
                          subtitle: subtitle,
                          icon: _typeIcon(type),
                        ),
                      );
                    }
                  }

                  // 再補上 baseEvents（去重：同一天同標題不嚴格去，先簡單）
                  events.addAll(baseEvents);

                  // 排序（新到舊）
                  events.sort((a, b) => b.at.compareTo(a.at));

                  if (events.isEmpty) {
                    return Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          '目前還沒有時間線紀錄。之後做「紀錄調整」後，會在這裡看到每一次調藥與變更。',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    );
                  }

                  return Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          for (int i = 0; i < events.length; i++)
                            _TimelineTile(
                              event: events[i],
                              isFirst: i == 0,
                              isLast: i == events.length - 1,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static double _readDose(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    return 0;
  }

  static DateTime? _readDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static DateTime? _readDateTime(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static String _doseLabel(double v) {
    if (v % 1 == 0) return '${v.toInt()}';
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _fmtYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  static String _typeTitle(String type) {
    switch (type) {
      case 'dose_change':
        return '調整劑量';
      case 'stop':
        return '停藥';
      case 'restart':
        return '恢復服用';
      case 'note':
      default:
        return '備註';
    }
  }

  static IconData _typeIcon(String type) {
    switch (type) {
      case 'dose_change':
        return Icons.swap_horiz;
      case 'stop':
        return Icons.pause_circle_outline;
      case 'restart':
        return Icons.play_circle_outline;
      case 'note':
      default:
        return Icons.sticky_note_2_outlined;
    }
  }

  static String _typeSubtitle(Map<String, dynamic> m) {
    // 你之後在「紀錄調整」存什麼，這裡就顯示什麼
    // 建議欄位：fromDose, toDose, unit, note
    final type = (m['type'] as String?) ?? 'note';
    final unit = (m['unit'] as String?) ?? '';
    if (type == 'dose_change') {
      final fromDose = _readDose(m['fromDose']);
      final toDose = _readDose(m['toDose']);
      return '${_doseLabel(fromDose)}$unit → ${_doseLabel(toDose)}$unit';
    }
    final note = (m['note'] as String?)?.trim();
    return (note == null || note.isEmpty) ? '—' : note;
  }
}

/* ===== UI components ===== */

class _StatusPill extends StatelessWidget {
  final bool isActive;
  const _StatusPill({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isActive ? cs.tertiaryContainer : cs.surfaceContainerHighest;
    final fg = isActive ? cs.onTertiaryContainer : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(isActive ? '服用中' : '已停用', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  final String text;
  const _MiniLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

class _TimelineEvent {
  final DateTime at;
  final String title;
  final String subtitle;
  final IconData icon;

  _TimelineEvent({
    required this.at,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _TimelineTile extends StatelessWidget {
  final _TimelineEvent event;
  final bool isFirst;
  final bool isLast;

  const _TimelineTile({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                // 上方線
                if (!isFirst)
                  Container(
                    width: 2,
                    height: 12,
                    color: cs.outlineVariant.withOpacity(0.7),
                  ),
                // 圓點
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withOpacity(0.75),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(event.icon, size: 14, color: cs.onPrimaryContainer),
                ),
                // 下方線
                if (!isLast)
                  Container(
                    width: 2,
                    height: 36,
                    color: cs.outlineVariant.withOpacity(0.7),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  event.subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  _fmt(event.at),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y/$m/$d  $hh:$mm';
  }
}
