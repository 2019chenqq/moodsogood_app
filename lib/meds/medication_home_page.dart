import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_medication_page.dart';

class MedicationHomePage extends StatelessWidget {
  const MedicationHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('請先登入帳號')),
      );
    }

    final medsQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medications')
        .orderBy('isActive', descending: true)
        .orderBy('updatedAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('藥物'),
        actions: [
          IconButton(
            tooltip: '紀錄調整（回診/調藥）',
            onPressed: () {
              // TODO: 下一步做 Change Wizard 後，把這裡導過去
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('尚未建立「紀錄調整」頁面')),
              );
            },
            icon: const Icon(Icons.edit_note),
          ),
          IconButton(
            tooltip: '新增藥物',
            onPressed: () async {
  final added = await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AddMedicationPage()),
  );
  // added == true 代表新增成功（可選）
},
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: medsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('發生錯誤：${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _EmptyState(
  onAdd: () async {
    final added = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddMedicationPage()),
    );
    // added == true 代表新增成功；StreamBuilder 會自動更新，不一定要做任何事
  },
);
          }

          final active = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final inactive = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          for (final d in docs) {
            final data = d.data();
            final isActive = (data['isActive'] as bool?) ?? true;
            (isActive ? active : inactive).add(d);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _HeaderHintCard(
                lastChangeAt: _readTimestampToDate(docs.first.data()['lastChangeAt']),
              ),
              const SizedBox(height: 12),

              _SectionTitle(title: '目前服用中', count: active.length),
              const SizedBox(height: 8),
              if (active.isEmpty)
                const _MutedText('目前沒有「服用中」的藥物。')
              else
                ...active.map((d) => _MedicationCard(
                      docId: d.id,
                      data: d.data(),
                      onTap: () {
                        // TODO: 之後導到 Medication Detail
                      },
                      onMore: () async {
                        await _showMedicationActions(context, uid, d.id, d.data());
                      },
                    )),

              const SizedBox(height: 20),

              _ExpandableSection(
                title: '已停用',
                count: inactive.length,
                initiallyExpanded: false,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    if (inactive.isEmpty)
                      const _MutedText('沒有已停用的藥物。')
                    else
                      ...inactive.map((d) => _MedicationCard(
                            docId: d.id,
                            data: d.data(),
                            onTap: () {},
                            onMore: () async {
                              await _showMedicationActions(context, uid, d.id, d.data());
                            },
                          )),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
  final added = await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AddMedicationPage()),
  );
  // added == true 代表新增成功（可選）
},
        icon: const Icon(Icons.add),
        label: const Text('新增藥物'),
      ),
    );
  }

  DateTime? _readTimestampToDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    return null;
  }
}

class _HeaderHintCard extends StatelessWidget {
  final DateTime? lastChangeAt;
  const _HeaderHintCard({required this.lastChangeAt});

  @override
  Widget build(BuildContext context) {
    final text = (lastChangeAt == null)
        ? '若今天回診或調藥，點右上角「紀錄調整」。'
        : '上次調整：${_fmtYmd(lastChangeAt!)}｜若今天回診或調藥，點右上角「紀錄調整」。';

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;
  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        _CountPill(count: count),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;
  const _CountPill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _ExpandableSection extends StatefulWidget {
  final String title;
  final int count;
  final bool initiallyExpanded;
  final Widget child;

  const _ExpandableSection({
    required this.title,
    required this.count,
    required this.initiallyExpanded,
    required this.child,
  });

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(width: 8),
                          _CountPill(count: widget.count),
                        ],
                      ),
                    ),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
            if (_expanded) widget.child,
          ],
        ),
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _MedicationCard({
    required this.docId,
    required this.data,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?)?.trim().isNotEmpty == true ? data['name'] as String : '未命名藥物';
    final dose = data['dose'];
    final unit = (data['unit'] as String?) ?? 'mg';

    final times = (data['times'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final purposes = (data['purposes'] as List?)?.whereType<String>().toList() ?? const <String>[];

    final subtitle = (dose == null) ? '劑量未填' : '$dose $unit';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.medication_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                      if (times.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: times.map((t) => _Chip(text: t)).toList(),
                        ),
                      ],
                      if (purposes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: purposes.map((p) => _Chip(text: p, isSecondary: true)).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '更多',
                  onPressed: onMore,
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool isSecondary;
  const _Chip({required this.text, this.isSecondary = false});

  @override
  Widget build(BuildContext context) {
    final bg = isSecondary
        ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.7)
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _MutedText extends StatelessWidget {
  final String text;
  const _MutedText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.medication_outlined, size: 44),
            const SizedBox(height: 12),
            Text('先建立你的藥物清單', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '平常不需要每天填藥。只有回診或調藥時，再做一次「紀錄調整」。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('新增第一顆藥'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showMedicationActions(
  BuildContext context,
  String uid,
  String docId,
  Map<String, dynamic> data,
) async {
  final isActive = (data['isActive'] as bool?) ?? true;

  final res = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('編輯藥物（之後做）'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(isActive ? Icons.pause_circle_outline : Icons.play_circle_outline),
              title: Text(isActive ? '停藥（標記為已停用）' : '恢復服用（標記為服用中）'),
              onTap: () => Navigator.pop(ctx, 'toggle'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (res == 'toggle') {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medications')
        .doc(docId)
        .set({
      'isActive': !isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(!isActive ? '已標記為「服用中」' : '已標記為「已停用」')),
      );
    }
  }
}
