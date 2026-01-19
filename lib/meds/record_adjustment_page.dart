import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/firebase_sync_config.dart';
import 'medication_local_db.dart';

// 你已經有的新增藥物頁（路徑依你的專案調整）
import 'add_medication_page.dart';
import 'record_adjustment_history_page.dart';

enum MedChangeType {unchanged, doseChanged, stopped }

class RecordAdjustmentPage extends StatefulWidget {
  const RecordAdjustmentPage({super.key});

  @override
  State<RecordAdjustmentPage> createState() => _RecordAdjustmentPageState();
}

class _RecordAdjustmentPageState extends State<RecordAdjustmentPage> {
  DateTime _date = DateTime.now();
  final _noteCtrl = TextEditingController();

  // 每顆藥的暫存變動
  final Map<String, _MedDraft> _draftByDocId = {};

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 初始化時從 Firebase 同步最新藥物到本地
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _syncFromFirebase(uid);
    }
  }

  Future<void> _syncFromFirebase(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final startTs = data['startDate'];
        DateTime? startDate;
        if (startTs is Timestamp) startDate = startTs.toDate();
        if (startTs is String) startDate = DateTime.tryParse(startTs);

        final mapped = {
          'id': doc.id,
          'name': data['name'],
          'dose': data['dose'],
          'unit': data['unit'],
          'type': data['type'],
          'intervalDays': data['intervalDays'],
          'times': (data['times'] as List?)?.cast<String>() ?? <String>[],
          'purposes': (data['purposes'] as List?)?.cast<String>() ?? <String>[],
          'note': data['note'],
          'startDate': startDate?.toString(),
          'isActive': data['isActive'] ?? true,
          'bodySymptoms': (data['bodySymptoms'] as List?)?.cast<String>() ?? <String>[],
          'purposeOther': data['purposeOther'],
          'createdAt': DateTime.now().toString(),
          'updatedAt': DateTime.now().toString(),
          'lastChangeAt': (data['lastChangeAt'] is Timestamp)
              ? (data['lastChangeAt'] as Timestamp).toDate().toString()
              : data['lastChangeAt']?.toString(),
        };

        await MedicationLocalDB().addMedication(uid, mapped);
      }
    } catch (e) {
      debugPrint('紀錄調整頁同步 Firebase 失敗：$e');
    }
  }

  Future<List<Map<String, dynamic>>> _getMedsForAdjustment(String uid) async {
    final all = await MedicationLocalDB().getMedicationsForDisplay(uid);
    return all.where((m) => (m['isActive'] ?? true) == true).toList();
  }

_MedDraft _ensureUiDraft(
  String docId,
  Map<String, dynamic> baseData,
) {
  return _draftByDocId.putIfAbsent(docId, () {
    final oldDose = (baseData['dose'] is num)
        ? (baseData['dose'] as num).toDouble()
        : 0.0;

    final unit = (baseData['unit'] as String?) ?? 'mg';
    final name = (baseData['name'] as String?) ?? '未命名藥物';

    return _MedDraft(
      name: name,
      unit: unit,
      oldDose: oldDose,
      type: MedChangeType.unchanged,
      newDose: oldDose, // 預設 = 原劑量
    );
  });
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String _toStr(dynamic v, [String fallback = '']) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? fallback : s;
}
  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('紀錄調整')),
        body: const Center(child: Text('請先登入後使用')),
      );
    }

    return Scaffold(
      appBar: AppBar(
  title: const Text('紀錄調整'),
  actions: [
    IconButton(
      tooltip: '調藥時間線',
      icon: const Icon(Icons.timeline),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RecordAdjustmentHistoryPage()),
        );
      },
    ),
  ],
),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addNewMedication,
        icon: const Icon(Icons.add),
        label: const Text('新增這次新開的藥'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _getMedsForAdjustment(uid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorView(message: '讀取藥物失敗：${snap.error}');
            }

            final docs = snap.data ?? [];
            if (docs.isEmpty) {
              return _EmptyMedsView(
                onAdd: _addNewMedication,
              );
            }

            // 確保 draft 有初始化
            for (final med in docs) {
              final docId = med['id'] as String? ?? '';
              _draftByDocId.putIfAbsent(docId, () => _MedDraft.fromMap(med));
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
              children: [
                _SoftHeaderCard(
                  title: '回診 / 調藥紀錄',
                  subtitle:
                      '沒有變動就不用改。只把這次有調整的藥標出來，之後可和症狀趨勢做比對。',
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: '這次回診日期',
                  icon: Icons.event,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_fmtYmd(_date)),
                    subtitle: Text(
                      '會用這個日期標記「調藥事件」',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickDate,
                  ),
                ),

                const SizedBox(height: 12),

                _SectionCard(
                  title: '備註（可選）',
                  icon: Icons.notes_outlined,
                  child: TextField(
                    controller: _noteCtrl,
                    minLines: 2,
                    maxLines: 5,
                    decoration: _inputDeco(context, '例如：醫師交代、調藥原因、觀察重點…'),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  '逐顆藥物標註（預設：維持原劑量）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),

                ...docs.map((med) => _buildMedCard(context, med, _draftByDocId[med['id'] as String? ?? '']!)),

                const SizedBox(height: 14),

                FilledButton(
                  onPressed: _saving ? null : () => _save(uid),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('儲存這次調整'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMedCard(
    BuildContext context,
    Map<String, dynamic> med,
    _MedDraft draft,
  ) {
    final cs = Theme.of(context).colorScheme;

    final name = (med['name'] as String?) ?? '未命名藥物';
    final unit = (med['unit'] as String?) ?? 'mg';
    final dose = med['dose'];
    final doseStr = _doseToString(dose, unit);

    final times = (med['times'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final isActive = (med['isActive'] as bool?) ?? true;

    // 卡片視覺：有變動就稍微凸顯
    final changed = draft.type != MedChangeType.unchanged;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.medication_outlined, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        '$doseStr${times.isNotEmpty ? ' · ${times.join('、')}' : ''}${!isActive ? ' · 已停用' : ''}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (changed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _typeLabel(draft.type),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // 三段切換
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _choiceChip(
                  context,
                  label: '維持原劑量',
                  selected: draft.type == MedChangeType.unchanged,
                  onTap: () => setState(() {
                    draft.type = MedChangeType.unchanged;
                    draft.newDose = null;
                    draft.stopReason = null;
                  }),
                ),
                _choiceChip(
                  context,
                  label: '劑量調整',
                  selected: draft.type == MedChangeType.doseChanged,
                  onTap: () => setState(() {
                    draft.type = MedChangeType.doseChanged;
                    // 預設帶入目前劑量
                    draft.newDose ??= _doseToDouble(dose);
                  }),
                ),
                _choiceChip(
                  context,
                  label: '停藥',
                  selected: draft.type == MedChangeType.stopped,
                  onTap: () => setState(() {
                    draft.type = MedChangeType.stopped;
                    draft.newDose = null;
                  }),
                ),
              ],
            ),

            // 劑量調整展開
            if (draft.type == MedChangeType.doseChanged) ...[
              const SizedBox(height: 10),
              _InlineEditRow(
                title: '新劑量',
                valueText: draft.newDose == null ? '點擊輸入' : _doseToString(draft.newDose, unit),
                onTap: () => _editDose(docId: med['id'] as String? ?? '', unit: unit),
              ),
              const SizedBox(height: 8),
              Text(
                '建議填「調整後」的劑量（支援 0.5 / 1.25 這類小數）',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],

            // 停藥展開
            if (draft.type == MedChangeType.stopped) ...[
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => draft.stopReason = v.trim().isEmpty ? null : v.trim(),
                decoration: _inputDeco(context, '停藥原因（可選）例如：副作用、療程結束、醫師建議…'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choiceChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer.withOpacity(0.7) : cs.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? cs.primary.withOpacity(0.3) : cs.outlineVariant.withOpacity(0.35),
          ),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }

Future<void> _editDose({
  required String docId,
  required String unit,
}) async {
  final draft = _draftByDocId[docId]!;

  final initText = draft.newDose == null
      ? ''
      : (draft.newDose! % 1 == 0
          ? draft.newDose!.toInt().toString()
          : draft.newDose!.toString());

  final ctrl = TextEditingController(text: initText);
  double? picked;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      void submit() {
        final raw = ctrl.text.trim().replaceAll(',', '.');
        final v = double.tryParse(raw);
        if (v == null || v < 0) return;
        picked = v;
        Navigator.of(dialogContext).pop();
      }

      return AlertDialog(
        title: const Text('輸入調整後劑量'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(
            suffixText: unit,
            hintText: '例如 0.5、1.25、25',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: submit,
            child: const Text('確定'),
          ),
        ],
      );
    },
  );

  if (picked == null) return;

  setState(() {
    draft.newDose = picked;
  });
}







  Future<void> _addNewMedication() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddMedicationPage()),
    );
    // 回來後 StreamBuilder 會自動更新清單
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _save(String uid) async {
    if (_saving) return;

    debugPrint('🔄 開始保存調整記錄...');
    debugPrint('📍 調整日期：${_fmtYmd(_date)}');
    debugPrint('📝 備註：${_noteCtrl.text}');

    // 只取有變動的 items（無變化的不寫入）
    final changed = _draftByDocId.entries
        .where((e) => e.value.type != MedChangeType.unchanged)
        .toList();

    debugPrint('🔍 檢查變動：${_draftByDocId.length} 顆藥物，${changed.length} 顆有變動');

    if (changed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前沒有任何變動。請至少選一顆藥做「調整」或「停藥」。')),
      );
      return;
    }

    // 檢查：劑量調整一定要有 newDose
    for (final e in changed) {
      final d = e.value;
      if (d.type == MedChangeType.doseChanged && d.newDose == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('有藥物選了「劑量調整」，但尚未填入新劑量。')),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      final adjRef = userRef.collection('medAdjustments').doc();
      final adjDate = Timestamp.fromDate(DateTime(_date.year, _date.month, _date.day));

      final items = changed.map((e) {
        final docId = e.key;
        final d = e.value;

        return <String, dynamic>{
          'medDocId': docId,
          'name': d.name,
          'type': d.type.name, // unchanged/doseChanged/stopped
          'oldDose': d.oldDose,
          'newDose': d.newDose,
          'unit': d.unit,
          'stopReason': d.stopReason,
        };
      }).toList();

      final batch = FirebaseFirestore.instance.batch();

      // 1) 寫入調整紀錄到本地 DB（一定要寫入）
      final adjId = adjRef.id;
      final dateStr = _fmtYmd(DateTime(_date.year, _date.month, _date.day));
      debugPrint('📋 準備保存調整記錄 - adjId: $adjId, date: $dateStr, items 數量: ${items.length}');
      
      try {
        await MedicationLocalDB().addAdjustmentRecord(uid, adjId, {
          'date': dateStr,
          'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          'items': items,
          'createdAt': DateTime.now().toString(),
        });
        debugPrint('✅ 本地調整記錄已保存');
      } catch (e) {
        debugPrint('❌ 本地調整記錄保存失敗：$e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本地保存失敗：$e')),
        );
        return;
      }

      // 2) 寫入調整紀錄到 Firebase
      batch.set(adjRef, {
        'date': adjDate,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'items': items,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3) 同步更新藥物主檔（只更新有變動的）
      for (final e in changed) {
        final medDocId = e.key;
        final d = e.value;

        final medRef = userRef.collection('medications').doc(medDocId);

        final patch = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
          'lastChangeAt': adjDate,
        };

        if (d.type == MedChangeType.doseChanged) {
          patch['dose'] = d.newDose; // double
          patch['isActive'] = true;
        } else if (d.type == MedChangeType.stopped) {
          patch['isActive'] = false;
        }

        batch.set(medRef, patch, SetOptions(merge: true));
      }

      // 4️⃣ 先更新本地端藥物（一定要更新）
      for (final e in changed) {
        final medDocId = e.key;
        final d = e.value;

        final localMed = await MedicationLocalDB().getMedication(uid, medDocId);
        if (localMed != null) {
          final updated = Map<String, dynamic>.from(localMed);
          updated['updatedAt'] = DateTime.now().toString();
          updated['lastChangeAt'] = DateTime(_date.year, _date.month, _date.day).toString();

          if (d.type == MedChangeType.doseChanged) {
            updated['dose'] = d.newDose;
            updated['isActive'] = true;
          } else if (d.type == MedChangeType.stopped) {
            updated['isActive'] = false;
          }

          try {
            await MedicationLocalDB().updateMedication(uid, medDocId, updated);
          } catch (e) {
            debugPrint('⚠️ 更新藥物 $medDocId 失敗：$e');
          }
        }
      }
      debugPrint('✅ 本地藥物已更新');

      // 5️⃣ 再上傳 Firebase（如果啟用同步）
      if (FirebaseSyncConfig.shouldSync()) {
        try {
          await batch.commit();
          debugPrint('🔥 Firebase 調整已同步');
        } catch (e) {
          debugPrint('⚠️ Firebase 同步失敗：$e');
        }
      }

      if (!mounted) {
        debugPrint('❌ Widget 已卸載，無法返回');
        return;
      }
      
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存本次調整')),
      );
    } catch (e) {
      debugPrint('❌ 儲存異常：$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('儲存失敗：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  static InputDecoration _inputDeco(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  String _typeLabel(MedChangeType t) {
    switch (t) {
      case MedChangeType.unchanged:
        return '維持原劑量';
      case MedChangeType.doseChanged:
        return '調整';
      case MedChangeType.stopped:
        return '停藥';
    }
  }

  double _doseToDouble(dynamic dose) {
    if (dose is int) return dose.toDouble();
    if (dose is double) return dose;
    return 0;
  }

  String _doseToString(dynamic dose, String unit) {
    final v = (dose is int) ? dose.toDouble() : (dose is double ? dose : 0.0);
    if (v % 1 == 0) return '${v.toInt()} $unit';
    return '${v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')} $unit';
  }
}

class _MedDraft {
  String name;
  String unit;
  double oldDose;
  MedChangeType type;
  double? newDose;
  String? stopReason;

  _MedDraft({
    required this.name,
    required this.unit,
    required this.oldDose,
    required this.type,
    this.newDose,
    this.stopReason,
  });

  factory _MedDraft.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final name = (d['name'] as String?) ?? '未命名藥物';
    final unit = (d['unit'] as String?) ?? 'mg';
    final dose = d['dose'];
    final oldDose = (dose is int) ? dose.toDouble() : (dose is double ? dose : 0.0);

    return _MedDraft(
      name: name,
      unit: unit,
      oldDose: oldDose,
      type: MedChangeType.unchanged,
    );
  }

  factory _MedDraft.fromMap(Map<String, dynamic> m) {
    final name = (m['name'] as String?) ?? '未命名藥物';
    final unit = (m['unit'] as String?) ?? 'mg';
    final dose = m['dose'];
    final oldDose = (dose is int) ? dose.toDouble() : (dose is double ? dose : 0.0);

    return _MedDraft(
      name: name,
      unit: unit,
      oldDose: oldDose,
      type: MedChangeType.unchanged,
    );
  }
}

/* ====== 小元件：沿用你新增頁的風格 ====== */

class _SoftHeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SoftHeaderCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
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
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.65),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.playlist_add_check),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _InlineEditRow extends StatelessWidget {
  final String title;
  final String valueText;
  final VoidCallback onTap;

  const _InlineEditRow({
    required this.title,
    required this.valueText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Expanded(child: Text('$title：$valueText')),
            Icon(Icons.edit, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _EmptyMedsView extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyMedsView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.medication_outlined, size: 42),
            const SizedBox(height: 10),
            Text('先建立你的藥物清單', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '先新增至少一顆藥，才可以開始「紀錄調整」。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
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

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(message)));
  }
}

class MedChangeDraft {
  MedChangeType type;
  double? newDose;
  String? stopReason;

  MedChangeDraft({
    this.type = MedChangeType.unchanged,
    this.newDose,
    this.stopReason,
  });
}