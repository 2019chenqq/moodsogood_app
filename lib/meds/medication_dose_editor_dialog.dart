import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import 'medication_dose_units.dart';

/// 一般劑量編輯對話框的回傳結果。
class MedicationDoseEditResult {
  const MedicationDoseEditResult({required this.dose, required this.unit});

  final double dose;
  final String unit;
}

/// 一般劑量編輯對話框。
class MedicationDoseEditorDialog extends StatefulWidget {
  const MedicationDoseEditorDialog({
    super.key,
    this.initialDose,
    required this.initialUnit,
  });

  final double? initialDose;
  final String initialUnit;

  @override
  State<MedicationDoseEditorDialog> createState() =>
      _MedicationDoseEditorDialogState();
}

class _MedicationDoseEditorDialogState
    extends State<MedicationDoseEditorDialog> {
  late final TextEditingController _controller;
  late String _unit;

  @override
  void initState() {
    super.initState();
    final value = widget.initialDose;
    _controller = TextEditingController(
      text: value == null
          ? ''
          : (value % 1 == 0 ? value.toInt().toString() : value.toString()),
    );
    _unit = kMedicationDoseUnits.contains(widget.initialUnit)
        ? widget.initialUnit
        : 'mg';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null || value < 0) return;
    Navigator.of(context)
        .pop(MedicationDoseEditResult(dose: value, unit: _unit));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('輸入調整後劑量'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              suffixText: _unit,
              hintText: '例如 0.5、1.25、25',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: '劑量單位'),
            items: kMedicationDoseUnits
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _unit = value);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('確定'),
        ),
      ],
    );
  }
}

/// 口服（每顆劑量 × 顆數）劑量編輯對話框的回傳結果。
class MedicationOralDoseEditResult {
  const MedicationOralDoseEditResult({
    required this.dosePerUnit,
    required this.pillCount,
    required this.unit,
  });

  final double dosePerUnit;
  final double pillCount;
  final String unit;
}

/// 口服（每顆劑量 × 顆數）劑量編輯對話框。
class MedicationOralDoseEditorDialog extends StatefulWidget {
  const MedicationOralDoseEditorDialog({
    super.key,
    required this.initialDosePerUnit,
    required this.initialPillCount,
    required this.initialUnit,
  });

  final double initialDosePerUnit;
  final double initialPillCount;
  final String initialUnit;

  @override
  State<MedicationOralDoseEditorDialog> createState() =>
      _MedicationOralDoseEditorDialogState();
}

class _MedicationOralDoseEditorDialogState
    extends State<MedicationOralDoseEditorDialog> {
  late final TextEditingController _dosePerUnitController;
  late final TextEditingController _pillCountController;
  late String _unit;

  @override
  void initState() {
    super.initState();
    _dosePerUnitController = TextEditingController(
      text: _formatNumber(widget.initialDosePerUnit),
    );
    _pillCountController = TextEditingController(
      text: _formatNumber(widget.initialPillCount),
    );
    _unit = kMedicationDoseUnits.contains(widget.initialUnit)
        ? widget.initialUnit
        : 'mg';
  }

  @override
  void dispose() {
    _dosePerUnitController.dispose();
    _pillCountController.dispose();
    super.dispose();
  }

  double? _readNumber(TextEditingController controller) {
    final raw = controller.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  void _submit() {
    final dosePerUnit = _readNumber(_dosePerUnitController);
    final pillCount = _readNumber(_pillCountController);
    if (dosePerUnit == null || pillCount == null || pillCount <= 0) return;
    Navigator.of(context).pop(
      MedicationOralDoseEditResult(
        dosePerUnit: dosePerUnit,
        pillCount: pillCount,
        unit: _unit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dosePerUnit = _readNumber(_dosePerUnitController);
    final pillCount = _readNumber(_pillCountController);
    final isValid = dosePerUnit != null && pillCount != null && pillCount > 0;
    final totalDose = isValid ? _round1(dosePerUnit * pillCount) : null;

    return AlertDialog(
      title: const Text('調整後用量'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _dosePerUnitController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '每顆劑量',
              hintText: '例如 25',
              suffixText: _unit,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: '劑量單位'),
            items: kMedicationDoseUnits
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _unit = value);
              }
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pillCountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '一次顆數',
              hintText: '例如 0.5、1、2',
              suffixText: '顆',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            totalDose == null
                ? '請輸入有效的劑量與顆數'
                : '每次總量：${_formatNumber(dosePerUnit!)} $_unit × '
                    '${_formatNumber(pillCount!)} 顆 = '
                    '${_formatNumber(totalDose)} $_unit',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: totalDose == null
                      ? Theme.of(context).colorScheme.error
                      : HealingDesignSystem.adaptivePrimaryText(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: isValid ? _submit : null,
          child: const Text('確定'),
        ),
      ],
    );
  }
}

String _formatNumber(double value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

double _round1(double value) => double.parse(value.toStringAsFixed(1));
