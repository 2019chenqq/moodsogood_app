import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/firebase_sync_config.dart';

class EditMedicationPage extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> initialData;

  const EditMedicationPage({
    super.key,
    required this.docId,
    required this.initialData,
  });

  @override
  State<EditMedicationPage> createState() => _EditMedicationPageState();
}

class _EditMedicationPageState extends State<EditMedicationPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _purposeOtherCtrl = TextEditingController();
  final _bodySymptomCtrl = TextEditingController();

  double _dose = 0;
  String _unit = 'mg';
  String _medType = 'tablet'; // tablet / injection
int _intervalDays = 28;     // 長效針用：每幾天一次（例如 28、30）
Timer? _drugDebounce;
bool _isSearchingDrug = false;

// 候選結果：[{id, zh, en}]
List<Map<String, String>> _drugSuggestions = [];
  final Map<String, bool> _timeSlots = {
    '早上': false,
    '中午': false,
    '下午': false,
    '晚上': false,
    '睡前': false,
    '需要時': false,
  };

  final Map<String, bool> _purposes = {
    '睡眠': false,
    '焦慮': false,
    '憂鬱': false,
    '情緒穩定': false,
    '專注': false,
    '身體症狀': false,
    '其他': false,
  };

  DateTime _startDate = DateTime.now();
  bool _isActive = true;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromInitial(widget.initialData);
  }

  void _hydrateFromInitial(Map<String, dynamic> d) {
    _nameCtrl.text = (d['name'] as String?) ?? '';
    _noteCtrl.text = (d['note'] as String?) ?? '';
// ✅ 藥物形式：口服 / 長效針
_medType = (d['type'] as String?) ?? 'tablet';
// ✅ 注射間隔（天）
final iv = d['intervalDays'];
if (iv is int) _intervalDays = iv;
else if (iv is double) _intervalDays = iv.round();
else _intervalDays = 28;

// 若是長效針：通常不需要 times（避免混進早上/睡前）
if (_medType == 'injection') {
  for (final k in _timeSlots.keys) {
    _timeSlots[k] = false;
  }
}
    final doseVal = d['dose'];
    if (doseVal is int) _dose = doseVal.toDouble();
    else if (doseVal is double) _dose = doseVal;
    else _dose = 0;

    _unit = (d['unit'] as String?) ?? 'mg';

    final times = (d['times'] as List?)?.whereType<String>().toSet() ?? <String>{};
    for (final k in _timeSlots.keys) {
      _timeSlots[k] = times.contains(k);
    }

    final purposes = (d['purposes'] as List?)?.whereType<String>().toSet() ?? <String>{};
    for (final k in _purposes.keys) {
      _purposes[k] = purposes.contains(k);
    }

    // 自訂用途、身體症狀
    _purposeOtherCtrl.text = (d['purposeOther'] as String?) ?? '';
    final bodySymptoms = (d['bodySymptoms'] as List?)?.whereType<String>().toList() ?? <String>[];
    _bodySymptomCtrl.text = bodySymptoms.join('、');

    // startDate
    final sd = d['startDate'];
    if (sd is Timestamp) _startDate = sd.toDate();
    _startDate = DateTime(_startDate.year, _startDate.month, _startDate.day);

    _isActive = (d['isActive'] as bool?) ?? true;
  }

  @override
  void dispose() {
    _drugDebounce?.cancel();
  _nameCtrl.dispose();
  _nameEnCtrl.dispose();
    _noteCtrl.dispose();
    _purposeOtherCtrl.dispose();
    _bodySymptomCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 這兩個要在 build scope 先算好，才能 if (...)
    final bodySelected = _purposes['身體症狀'] == true;
    final otherSelected = _purposes['其他'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('編輯藥物')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              _SoftHeaderCard(
                title: '更新藥物資訊',
                subtitle: '你可以調整劑量、用途與服用時間。回診/調藥的「變更紀錄」之後再做在「紀錄調整」。',
              ),
              const SizedBox(height: 14),

              _SectionCard(
  title: '藥物名稱（中文）',
  icon: Icons.medication_outlined,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        controller: _nameCtrl,
        textInputAction: TextInputAction.next,
        decoration: _inputDeco('例如：克癲平、思樂康…')
            .copyWith(suffixIcon: _isSearchingDrug
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            ),
        onChanged: _onDrugNameChanged, // ✅ 關鍵：觸發字典搜尋
        validator: (v) {
          final t = (v ?? '').trim();
          if (t.isEmpty) return '請輸入藥物名稱';
          if (t.length < 2) return '名稱太短了';
          return null;
        },
      ),

      // ✅ 候選清單
      if (_drugSuggestions.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.6),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _drugSuggestions.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: Theme.of(context).dividerColor.withOpacity(0.6),
            ),
            itemBuilder: (context, i) {
              final s = _drugSuggestions[i];
              final zh = s['zh'] ?? '';
              final en = s['en'] ?? '';
              return ListTile(
                dense: true,
                title: Text(zh.isEmpty ? en : zh),
                subtitle: (zh.isNotEmpty && en.isNotEmpty) ? Text(en) : null,
                onTap: () => _applyDrugSuggestion(s),
              );
            },
          ),
        ),
      ],
      // 若沒有候選，提供新增到字典的選項
      if (!_isSearchingDrug && _drugSuggestions.isEmpty && _nameCtrl.text.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.add_box_outlined),
          title: const Text('找不到這個藥，新增到字典？'),
          subtitle: Text(_nameCtrl.text.trim()),
          trailing: TextButton(
            onPressed: () => _showAddDrugDialog(_nameCtrl.text.trim()),
            child: const Text('新增'),
          ),
        ),
      ],
    ],
  ),
),

const SizedBox(height: 12),

_SectionCard(
  title: '藥物名稱（英文，給醫師看）',
  icon: Icons.translate_outlined,
  child: TextFormField(
    controller: _nameEnCtrl,
    textInputAction: TextInputAction.next,
    decoration: _inputDeco('例如：Clonazepam、Quetiapine…（可自動帶入/也可手動改）'),
  ),
),

const SizedBox(height: 12),

              _SectionCard(
                title: '劑量',
                icon: Icons.tune,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 可點擊手動輸入
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _editDoseManually,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _doseLabel(_dose),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.edit, size: 16, color: cs.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        _UnitPicker(
                          value: _unit,
                          onChanged: (v) => setState(() => _unit = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // 0.5 mg 刻度（你可改成 0.25 -> divisions: 1200）
                    Slider(
                      value: _dose.clamp(0, 300),
                      min: 0,
                      max: 300,
                      divisions: 600,
                      label: _doseLabel(_dose),
                      onChanged: (v) => setState(() => _dose = v),
                    ),

                    Row(
                      children: [
                        _SmallGhostButton(
                          text: '−',
                          onTap: () => setState(() => _dose = (_dose - 0.5).clamp(0, 300)),
                        ),
                        const SizedBox(width: 8),
                        _SmallGhostButton(
                          text: '+',
                          onTap: () => setState(() => _dose = (_dose + 0.5).clamp(0, 300)),
                        ),
                        const Spacer(),
                        Text(
                          '可先填常用劑量，之後調整再記錄',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
_SectionCard(
  title: '藥物形式',
  icon: Icons.medical_services_outlined,
  child: Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ChoiceChip(
        label: const Text('口服藥'),
        selected: _medType == 'tablet',
        onSelected: (_) => setState(() => _medType = 'tablet'),
      ),
      ChoiceChip(
        label: const Text('長效針'),
        selected: _medType == 'injection',
        onSelected: (_) => setState(() {
          _medType = 'injection';
          // 切到長效針時，清掉服用時間，避免混入早/晚分類
          for (final k in _timeSlots.keys) {
            _timeSlots[k] = false;
          }
        }),
      ),
    ],
  ),
),
const SizedBox(height: 12),

if (_medType == 'injection') ...[
  _SectionCard(
    title: '注射間隔（天）',
    icon: Icons.calendar_today_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('每 $_intervalDays 天一次', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Slider(
          min: 7,
          max: 60,
          divisions: 46,
          value: _intervalDays.toDouble(),
          label: '$_intervalDays 天',
          onChanged: (v) => setState(() => _intervalDays = v.round()),
        ),
        Text(
          '提示：長效針通常不需要設定早/中/晚服用時間；每次施打請在「紀錄調整」記錄事件。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    ),
  ),
  const SizedBox(height: 12),
],

              if (_medType != 'injection') ...[
  _SectionCard(
    title: '服用時間',
    icon: Icons.schedule,
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _timeSlots.keys.map((k) {
        final selected = _timeSlots[k] ?? false;
        return FilterChip(
          selected: selected,
          label: Text(k),
          onSelected: (s) => setState(() => _timeSlots[k] = s),
        );
      }).toList(),
    ),
  ),
  const SizedBox(height: 12),
],

              const SizedBox(height: 12),

              _SectionCard(
                title: '用途（可選）',
                icon: Icons.local_offer_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _purposes.keys.map((k) {
                        final selected = _purposes[k] ?? false;
                        return FilterChip(
                          selected: selected,
                          label: Text(k),
                          onSelected: (s) {
                            setState(() {
                              _purposes[k] = s;
                              if (k == '其他' && !s) _purposeOtherCtrl.clear();
                              if (k == '身體症狀' && !s) _bodySymptomCtrl.clear();
                            });
                          },
                        );
                      }).toList(),
                    ),

                    if (bodySelected) ...[
                      const SizedBox(height: 12),
                      Text('身體症狀（可填多項）', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _bodySymptomCtrl,
                        decoration: _inputDeco('例如：頭痛、噁心、心悸、手抖（可用逗號/頓號分隔）'),
                      ),
                    ],

                    if (otherSelected) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _purposeOtherCtrl,
                        decoration: _inputDeco('其他用途（例如：戒斷反應、PTSD 相關…）'),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _SectionCard(
                title: '開始日期與狀態',
                icon: Icons.event_available,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('開始日期'),
                      subtitle: Text(_fmtYmd(_startDate)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickStartDate,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('目前服用中'),
                      subtitle: Text(_isActive ? '會顯示在「目前服用中」' : '會顯示在「已停用」'),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                  ],
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
                  decoration: _inputDeco('例如：副作用、醫囑、提醒事項…'),
                ),
              ),

              const SizedBox(height: 18),

              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('儲存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
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

  String _doseLabel(double v) {
    if (v % 1 == 0) return '${v.toInt()} $_unit';
    return '${v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')} $_unit';
  }

  Future<void> _editDoseManually() async {
    final ctrl = TextEditingController(
      text: (_dose % 1 == 0) ? _dose.toInt().toString() : _dose.toString(),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('輸入劑量'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: _unit,
              hintText: '例如 0.5、1.25、25、75',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
                if (value == null || value < 0) return;
                Navigator.pop(context, value);
              },
              child: const Text('確定'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      setState(() => _dose = result.clamp(0, 300));
    }
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先登入帳號')));
      return;
    }

    // 防呆：勾了身體症狀但沒填，可提醒（可改成不擋）
    if ((_purposes['身體症狀'] == true) && _bodySymptomCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('你選了「身體症狀」，可以補充一下內容（或取消勾選）')),
      );
      return;
    }

    final name = _nameCtrl.text.trim();
    final times = (_medType == 'injection')
    ? <String>[]
    : _timeSlots.entries.where((e) => e.value).map((e) => e.key).toList();
    final purposes = _purposes.entries.where((e) => e.value).map((e) => e.key).toList();

    final purposeOther = _purposeOtherCtrl.text.trim();
    final bodyText = _bodySymptomCtrl.text.trim();
    final bodySymptoms = bodyText.isEmpty
        ? <String>[]
        : bodyText
            .split(RegExp(r'[，,、]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    setState(() => _saving = true);

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications')
          .doc(widget.docId);

      if (FirebaseSyncConfig.shouldSync()) {
        await docRef.set({
          'name': name,
          'dose': _dose, // double，支援 0.5 / 1.25
          'unit': _unit,
          // ✅ 新增：口服/長效針
    'type': _medType,

    // ✅ 新增：注射間隔（天）— 口服藥就清掉
    'intervalDays': _medType == 'injection' ? _intervalDays : null,

    // ✅ 長效針不應該有 times
    'times': times,
                  'purposes': purposes,
          'purposeOther': purposeOther.isEmpty ? null : purposeOther,
          'bodySymptoms': bodySymptoms,
          'note': _noteCtrl.text.trim(),
          'startDate': Timestamp.fromDate(DateTime(_startDate.year, _startDate.month, _startDate.day)),
          'isActive': _isActive,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已更新藥物')));
    } catch (e) {
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
  Future<void> _searchDrugDict(String input) async {
  final q = input.trim().toLowerCase();
  if (q.length < 1) {
    setState(() {
      _drugSuggestions = [];
      _isSearchingDrug = false;
    });
    return;
  }

  setState(() => _isSearchingDrug = true);

  try {
    // 你需要在 drug_dictionary 文件中建立 keywords 陣列（含前綴字）
    final snap = await FirebaseFirestore.instance
        .collection('drug_dictionary')
        .where('keywords', arrayContains: q.length > 12 ? q.substring(0, 12) : q)
        .limit(8)
        .get();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('auth uid=$uid');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('drug_dict query "${q.length > 12 ? q.substring(0, 12) : q}" -> ${snap.size} (uid:${uid ?? 'null'})'),
        duration: const Duration(seconds: 2),
      ));
    }

    final list = snap.docs.map((d) {
      final data = d.data();

      // support zh as String or List<String>
      List<String> zhList = [];
      final zhRaw = data['zh'];
      if (zhRaw is String) {
        zhList = zhRaw
            .split(RegExp(r'[，,/]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (zhRaw is List) {
        zhList = zhRaw.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }

      final zhDisplay = zhList.isNotEmpty ? zhList.join(' / ') : ((data['zh'] as String?)?.trim() ?? '');
      final en = (data['en'] as String?)?.trim() ?? '';

      return <String, String>{
        'id': d.id,
        'zh': zhDisplay,
        'en': en,
        // encode zh list for later matching
        'zh_list': zhList.join('|'),
      };
    }).where((m) => (m['zh']!.isNotEmpty || m['en']!.isNotEmpty)).toList();

    if (!mounted) return;
    final inputLower = input.trim().toLowerCase();
    setState(() {
      _drugSuggestions = list;
      _isSearchingDrug = false;
    });

    // If any candidate has a zh alias exactly matching the input, auto-fill its english name.
    if (_nameEnCtrl.text.trim().isEmpty) {
      Map<String, String>? match;
      for (final s in list) {
        final zhList = (s['zh_list'] ?? '').split('|').where((t) => t.isNotEmpty).toList();
        final en = (s['en'] ?? '').trim();
        final zhDisplay = (s['zh'] ?? '').toString();
        if (zhList.any((z) => z.toLowerCase() == inputLower)) {
          match = s;
          break;
        }
        if (zhDisplay.toLowerCase() == inputLower) {
          match = s;
          break;
        }
        if (en.isNotEmpty && en.toLowerCase() == inputLower) {
          match = s;
          break;
        }
      }

      if (match != null) {
        final en = (match['en'] ?? '').trim();
        final zhDisplay = (match['zh'] ?? '').toString();
        if (en.isNotEmpty) _nameEnCtrl.text = en;
        if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = zhDisplay;
        setState(() => _drugSuggestions = [match!]);
      }
    }
  } catch (_) {
    if (!mounted) return;
    setState(() => _isSearchingDrug = false);
  }
}

void _onDrugNameChanged(String v) {
  _drugDebounce?.cancel();
  _drugDebounce = Timer(const Duration(milliseconds: 250), () {
    _searchDrugDict(v);
  });
}

void _applyDrugSuggestion(Map<String, String> s) {
  final zh = (s['zh'] ?? '').trim();
  final en = (s['en'] ?? '').trim();

  // 你可以決定：中文欄位顯示 zh，英文欄位顯示 en
  if (zh.isNotEmpty) _nameCtrl.text = zh;
  if (en.isNotEmpty) _nameEnCtrl.text = en;

  setState(() => _drugSuggestions = []);
  FocusScope.of(context).nextFocus(); // 跳到下一個輸入欄（可改成 unfocus）
}

Future<void> _showAddDrugDialog(String input) async {
  final zhCtrl = TextEditingController(text: input);
  final enCtrl = TextEditingController();
  final aliasCtrl = TextEditingController();

  final res = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('新增到藥物字典'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: zhCtrl, decoration: const InputDecoration(labelText: '中文名稱')),
            const SizedBox(height: 8),
            TextField(controller: enCtrl, decoration: const InputDecoration(labelText: '英文名稱（選填）')),
            const SizedBox(height: 8),
            TextField(controller: aliasCtrl, decoration: const InputDecoration(labelText: '其他別名，逗號分隔（選填）')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('新增'),
          ),
        ],
      );
    },
  );

  if (res != true) return;

  final zh = zhCtrl.text.trim();
  final en = enCtrl.text.trim();
  final aliases = aliasCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  try {
    await _addDrugToDict(zh: zh, en: en, aliases: aliases);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已新增至字典')));
    // refresh suggestions
    _searchDrugDict(zh);
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增失敗：$e')));
  }
}

Future<void> _addDrugToDict({required String zh, String? en, List<String>? aliases}) async {
  final doc = <String, dynamic>{
    'zh': zh,
    'en': (en ?? '').trim(),
    'alias': aliases ?? <String>[],
  };

  // generate simple keywords (lowercase prefixes up to 12 chars)
  final kw = <String>{};
  String addKeywordsFrom(String? s) {
    if (s == null || s.trim().isEmpty) return '';
    final t = s.trim().toLowerCase();
    for (int i = 1; i <= t.length && i <= 12; i++) {
      kw.add(t.substring(0, i));
    }
    // also add full token
    kw.add(t);
    return t;
  }

  addKeywordsFrom(zh);
  addKeywordsFrom(en);
  for (final a in aliases ?? []) addKeywordsFrom(a);

  doc['keywords'] = kw.toList();

  await FirebaseFirestore.instance.collection('drug_dictionary').add(doc);
}
}

/* ====== 以下是 UI 小元件（沿用你新增頁同款）====== */

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
            child: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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

class _UnitPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _UnitPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      items: const [
        DropdownMenuItem(value: 'mg', child: Text('mg')),
        DropdownMenuItem(value: 'mL', child: Text('mL')),
        DropdownMenuItem(value: '顆', child: Text('顆')),
        DropdownMenuItem(value: '錠', child: Text('錠')),
        DropdownMenuItem(value: '包', child: Text('包')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _SmallGhostButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SmallGhostButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }
}
