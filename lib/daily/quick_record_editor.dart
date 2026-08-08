import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../models/health_event.dart';
import '../widgets/emotion_slider.dart';
import '../analytics_service.dart';
import 'emotion_dimensions.dart';
import 'symptom_definitions.dart';
import 'health_event_repository.dart';

/// 「快速記錄現在狀況」編輯頁（新增／編輯共用）。
///
/// 可一天多次使用，時間預設現在、可修改，並以精確 timestamp 儲存。
/// 情緒／症狀資料字典直接重用 emotion_dimensions / symptom_definitions，
/// 分數（1~5）重用 [EmotionSlider]。
class QuickRecordEditor extends StatefulWidget {
  const QuickRecordEditor({super.key, this.initial});

  /// 若提供則進入編輯模式，否則為新增。
  final HealthEvent? initial;

  @override
  State<QuickRecordEditor> createState() => _QuickRecordEditorState();
}

class _QuickRecordEditorState extends State<QuickRecordEditor> {
  static const List<String> _contextOptions = [
    '休息中',
    '活動中',
    '用餐後',
    '剛起床',
    '其他',
  ];

  DateTime _timestamp = DateTime.now();

  final Set<String> _emotions = <String>{};
  final Map<String, int> _emotionIntensities = <String, int>{};

  final Set<String> _symptoms = <String>{};
  final Map<String, int> _symptomSeverities = <String, int>{};

  // 狀態（選填）：energy / appetite / activity
  final Set<String> _activeStates = <String>{};
  final Map<String, int> _stateValues = <String, int>{};

  String? _context;
  final TextEditingController _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('quick_record_editor');
    final initial = widget.initial;
    if (initial == null) {
      _timestamp = DateTime.now();
      return;
    }
    _timestamp = initial.timestamp;
    for (final e in initial.emotions) {
      _emotions.add(e.name);
      _emotionIntensities[e.name] = e.intensity;
    }
    for (final s in initial.symptoms) {
      _symptoms.add(s.name);
      _symptomSeverities[s.name] = s.severity;
    }
    for (final entry in initial.stateChanges.entries) {
      _activeStates.add(entry.key);
      _stateValues[entry.key] = entry.value;
    }
    _context = initial.context;
    _note.text = initial.note ?? '';
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.initial != null;

  Future<void> _pickTimestamp() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: '選擇快速記錄日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_timestamp),
      helpText: '選擇記錄時間',
    );
    if (time == null || !mounted) return;
    setState(() {
      _timestamp = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _toggleEmotion(String name) {
    setState(() {
      if (_emotions.contains(name)) {
        _emotions.remove(name);
        _emotionIntensities.remove(name);
      } else {
        _emotions.add(name);
        _emotionIntensities[name] = 3;
      }
    });
  }

  void _toggleSymptom(String name) {
    setState(() {
      if (_symptoms.contains(name)) {
        _symptoms.remove(name);
        _symptomSeverities.remove(name);
      } else {
        _symptoms.add(name);
        _symptomSeverities[name] = 3;
      }
    });
  }

  void _toggleState(String key) {
    setState(() {
      if (_activeStates.contains(key)) {
        _activeStates.remove(key);
        _stateValues.remove(key);
      } else {
        _activeStates.add(key);
        _stateValues[key] = 3;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先登入再儲存')),
      );
      return;
    }
    if (_emotions.isEmpty && _symptoms.isEmpty && _activeStates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少選擇一項情緒、症狀或狀態')),
      );
      return;
    }

    setState(() => _saving = true);
    final event = HealthEvent(
      id: widget.initial?.id ?? '',
      timestamp: _timestamp,
      emotions: _emotions
          .map((name) => HealthEventEmotion(
                name: name,
                intensity: _emotionIntensities[name] ?? 3,
              ))
          .toList(),
      symptoms: _symptoms
          .map((name) => HealthEventSymptom(
                name: normalizeSymptomName(name),
                severity: _symptomSeverities[name] ?? 3,
              ))
          .toList(),
      stateChanges: Map.of(_stateValues),
      context: _context,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: widget.initial?.createdAt,
      updatedAt: widget.initial?.updatedAt,
    );

    try {
      final repo = HealthEventRepository();
      if (_isEdit) {
        await repo.update(userId: uid, event: event);
      } else {
        await repo.create(userId: uid, event: event);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗：$e')),
      );
    }
  }

  Future<void> _delete() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final id = widget.initial?.id ?? '';
    if (uid == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除這筆快速記錄？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await HealthEventRepository().delete(userId: uid, eventId: id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刪除失敗：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text(_isEdit ? '編輯快速記錄' : '快速記錄現在狀況'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '刪除',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TimeSection(timestamp: _timestamp, onPick: _pickTimestamp),
            const SizedBox(height: 16),
            _selectionCard(
              context: context,
              title: '情緒（可複選，每個可調 1~5）',
              child: _emotionSection(context),
            ),
            const SizedBox(height: 16),
            _selectionCard(
              context: context,
              title: '症狀（可複選，每個可調 1~5）',
              child: _symptomSection(context),
            ),
            const SizedBox(height: 16),
            _selectionCard(
              context: context,
              title: '狀態（選填）',
              child: _stateSection(context),
            ),
            const SizedBox(height: 16),
            _selectionCard(
              context: context,
              title: '情境（選填）',
              child: _contextSection(context),
            ),
            const SizedBox(height: 16),
            _selectionCard(
              context: context,
              title: '備註（選填）',
              child: TextField(
                controller: _note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '寫點補充，例如：下午散步後覺得好一點…',
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isEdit ? '儲存變更' : '儲存'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _selectionCard({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: HealingDesignSystem.titleSmall.copyWith(
              color: HealingDesignSystem.adaptivePrimaryText(context),
            ),
          ),
          const SizedBox(height: HealingDesignSystem.paddingL),
          child,
        ],
      ),
    );
  }

  Widget _emotionSection(BuildContext context) {
    final selectedNames = _emotions.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in kEmotionCheckboxCategories.entries) ...[
          Text(
            category.key,
            style: HealingDesignSystem.labelMedium.copyWith(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
            ),
          ),
          const SizedBox(height: HealingDesignSystem.paddingS),
          _chipWrap(
            items: category.value,
            selected: _emotions,
            onToggle: _toggleEmotion,
          ),
          const SizedBox(height: HealingDesignSystem.paddingM),
        ],
        const SizedBox(height: HealingDesignSystem.paddingS),
        if (selectedNames.isEmpty)
          Text(
            '尚未選擇情緒',
            style: HealingDesignSystem.bodySmall,
          )
        else
          ...selectedNames.map(
            (name) => _scoreSliderCard(
              context: context,
              name: name,
              value: _emotionIntensities[name] ?? 3,
              onChanged: (v) => setState(() => _emotionIntensities[name] = v),
            ),
          ),
      ],
    );
  }

  Widget _symptomSection(BuildContext context) {
    final selectedNames = _symptoms.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in kSymptomCategories.entries) ...[
          Text(
            category.key,
            style: HealingDesignSystem.labelMedium.copyWith(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
            ),
          ),
          const SizedBox(height: HealingDesignSystem.paddingS),
          _chipWrap(
            items: category.value,
            selected: _symptoms,
            onToggle: _toggleSymptom,
          ),
          const SizedBox(height: HealingDesignSystem.paddingM),
        ],
        if (selectedNames.isEmpty)
          Text(
            '尚未選擇症狀',
            style: HealingDesignSystem.bodySmall,
          )
        else
          ...selectedNames.map(
            (name) => _scoreSliderCard(
              context: context,
              name: name,
              value: _symptomSeverities[name] ?? 3,
              label: '嚴重程度',
              onChanged: (v) => setState(() => _symptomSeverities[name] = v),
            ),
          ),
      ],
    );
  }

  Widget _stateSection(BuildContext context) {
    const keys = ['energy', 'appetite', 'activity'];
    const labels = ['能量', '食慾', '活動量'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${labels[i]}（與平常相比）',
                  style: HealingDesignSystem.labelMedium.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _toggleState(keys[i]),
                child: Text(_activeStates.contains(keys[i]) ? '清除' : '記錄'),
              ),
            ],
          ),
          if (_activeStates.contains(keys[i]))
            EmotionSlider(
              label: labels[i],
              value: _stateValues[keys[i]] ?? 3,
              onChanged: (v) => setState(() => _stateValues[keys[i]] = v),
              leftIcon: 'assets/emotion/default.png',
              rightIcon: 'assets/emotion/default.png',
              gradientColors: const [
                Color(0xFF9AD0EC),
                Color(0xFFFFE08A),
              ],
            ),
          const SizedBox(height: HealingDesignSystem.paddingS),
        ],
      ],
    );
  }

  Widget _contextSection(BuildContext context) {
    return _chipWrap(
      items: _contextOptions,
      selected: {if (_context != null) _context!},
      onToggle: (value) => setState(() => _context = value),
      singleSelect: true,
    );
  }

  Widget _chipWrap({
    required List<String> items,
    required Set<String> selected,
    required void Function(String) onToggle,
    bool singleSelect = false,
  }) {
    return Wrap(
      spacing: HealingDesignSystem.paddingM,
      runSpacing: HealingDesignSystem.paddingM,
      children: items.map((name) {
        final isSelected = selected.contains(name);
        return InkWell(
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
          onTap: () => onToggle(name),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: HealingDesignSystem.paddingM,
              vertical: HealingDesignSystem.paddingS,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? (singleSelect
                      ? HealingDesignSystem.primaryBlue
                      : HealingDesignSystem.primaryBlue.withOpacity(0.15))
                  : HealingDesignSystem.adaptiveSurface(context),
              border: Border.all(
                color: isSelected
                    ? HealingDesignSystem.primaryBlue
                    : HealingDesignSystem.adaptiveCardBorder(context),
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
              boxShadow:
                  isSelected ? [HealingDesignSystem.shadowLight()] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(
                    singleSelect ? Icons.check : Icons.check_circle,
                    size: 16,
                    color: singleSelect
                        ? Colors.white
                        : HealingDesignSystem.primaryBlue,
                  ),
                  const SizedBox(width: HealingDesignSystem.paddingS),
                ],
                Text(
                  name,
                  style: TextStyle(
                    color: singleSelect && isSelected
                        ? Colors.white
                        : (isSelected
                            ? HealingDesignSystem.primaryBlue
                            : HealingDesignSystem.adaptivePrimaryText(context)),
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _scoreSliderCard({
    required BuildContext context,
    required String name,
    required int value,
    required ValueChanged<int> onChanged,
    String label = '強度',
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: HealingDesignSystem.paddingL),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name  $label：$value / 5',
              style: HealingDesignSystem.titleSmall.copyWith(
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
            ),
            const SizedBox(height: HealingDesignSystem.paddingM),
            EmotionSlider(
              label: name,
              value: value,
              onChanged: onChanged,
              leftIcon: 'assets/emotion/default.png',
              rightIcon: 'assets/emotion/default.png',
              gradientColors: const [
                Color(0xFF9AD0EC),
                Color(0xFFFFE08A),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeSection extends StatelessWidget {
  const _TimeSection({required this.timestamp, required this.onPick});

  final DateTime timestamp;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final text = '${timestamp.year}/${timestamp.month}/${timestamp.day}  '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: HealingDesignSystem.primaryBlue),
          const SizedBox(width: HealingDesignSystem.paddingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '記錄時間',
                  style: HealingDesignSystem.labelMedium.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: HealingDesignSystem.titleMedium.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onPick, child: const Text('更改')),
        ],
      ),
    );
  }
}
