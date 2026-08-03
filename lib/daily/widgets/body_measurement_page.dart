import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/healing_design_system.dart';
import '../../models/daily_record.dart';

class BodyMeasurementPage extends StatefulWidget {
  const BodyMeasurementPage({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final BodyMeasurement? value;
  final ValueChanged<BodyMeasurement?> onChanged;

  @override
  State<BodyMeasurementPage> createState() => _BodyMeasurementPageState();
}

class _BodyMeasurementPageState extends State<BodyMeasurementPage> {
  late final TextEditingController _weightController;
  late final TextEditingController _bodyFatController;
  late final TextEditingController _waistController;
  MeasurementTiming? _timing;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController();
    _bodyFatController = TextEditingController();
    _waistController = TextEditingController();
    _updateFromValue(widget.value);
  }

  @override
  void didUpdateWidget(BodyMeasurementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _updateFromValue(widget.value);
  }

  void _updateFromValue(BodyMeasurement? value) {
    _weightController.text = _format(value?.weightKg);
    _bodyFatController.text = _format(value?.bodyFatPercent);
    _waistController.text = _format(value?.waistCm);
    _timing = value?.measurementTiming;
    _expanded = value?.hasData == true;
  }

  String _format(double? value) => value == null ? '' : value.toString();

  @override
  void dispose() {
    _weightController.dispose();
    _bodyFatController.dispose();
    _waistController.dispose();
    super.dispose();
  }

  void _emit() {
    final measurement = BodyMeasurement(
      weightKg: double.tryParse(_weightController.text),
      bodyFatPercent: double.tryParse(_bodyFatController.text),
      waistCm: double.tryParse(_waistController.text),
      measuredAt: widget.value?.measuredAt,
      measurementTiming: _timing,
    );
    widget.onChanged(measurement.hasData ? measurement : null);
  }

  String? _validate(String? raw, double min, double max, String unit) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null) return '請輸入有效數字';
    if (value < min || value > max) return '請輸入 $min～$max $unit';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
      children: [
        Container(
          decoration: HealingDesignSystem.adaptiveCardDecoration(context),
          child: ExpansionTile(
            initiallyExpanded: _expanded,
            onExpansionChanged: (value) => _expanded = value,
            leading: const Icon(Icons.monitor_weight_outlined,
                color: HealingDesignSystem.primaryBlue),
            title: Text('身體數據（選填）',
                style: HealingDesignSystem.titleMedium.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context))),
            subtitle: const Text('只記錄今天實際測量到的數字'),
            childrenPadding: const EdgeInsets.all(HealingDesignSystem.paddingL),
            children: [
              _numberField(_weightController, '體重', 'kg', 20, 300),
              const SizedBox(height: 12),
              _numberField(_bodyFatController, '體脂率', '%', 1, 70),
              const SizedBox(height: 12),
              _numberField(_waistController, '腰圍（選填）', 'cm', 30, 250),
              const SizedBox(height: 12),
              DropdownButtonFormField<MeasurementTiming?>(
                value: _timing,
                decoration: const InputDecoration(labelText: '測量時間（選填）'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('尚未填寫')),
                  ...MeasurementTiming.values.map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.displayName),
                      )),
                ],
                onChanged: (value) {
                  setState(() => _timing = value);
                  _emit();
                },
              ),
              if (widget.value?.hasData == true) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      _weightController.clear();
                      _bodyFatController.clear();
                      _waistController.clear();
                      setState(() => _timing = null);
                      widget.onChanged(null);
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('清除身體數據'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label,
      String unit, double min, double max) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
      ],
      decoration: InputDecoration(labelText: label, suffixText: unit),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) => _validate(value, min, max, unit),
      onChanged: (_) => _emit(),
    );
  }
}
