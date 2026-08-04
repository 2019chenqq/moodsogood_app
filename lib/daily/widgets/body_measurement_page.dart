import 'package:flutter/material.dart';
import '../../constants/healing_design_system.dart';
import '../../models/daily_record.dart';
import '../body_measurement_input.dart';

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
  late final TextEditingController _customTimeController;
  MeasurementTiming? _timing;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController();
    _bodyFatController = TextEditingController();
    _waistController = TextEditingController();
    _customTimeController = TextEditingController();
    _updateFromValue(widget.value);
  }

  @override
  void didUpdateWidget(BodyMeasurementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !_currentInputRepresents(widget.value)) {
      _updateFromValue(widget.value);
    }
  }

  /// Parent rebuilds echo each keystroke back through [value]. Keep transient
  /// input such as `75.` intact when it already represents that same value.
  bool _currentInputRepresents(BodyMeasurement? value) {
    return parseBodyMeasurementNumber(_weightController.text) ==
            value?.weightKg &&
        parseBodyMeasurementNumber(_bodyFatController.text) ==
            value?.bodyFatPercent &&
        parseBodyMeasurementNumber(_waistController.text) == value?.waistCm &&
        _timing == value?.measurementTiming &&
        (_timing != MeasurementTiming.other ||
            _customTimeController.text.trim() ==
                (value?.effectiveCustomMeasurementTime ?? ''));
  }

  void _updateFromValue(BodyMeasurement? value) {
    _setText(_weightController, formatBodyMeasurementNumber(value?.weightKg));
    _setText(
      _bodyFatController,
      formatBodyMeasurementNumber(value?.bodyFatPercent),
    );
    _setText(_waistController, formatBodyMeasurementNumber(value?.waistCm));
    _setText(
      _customTimeController,
      value?.effectiveCustomMeasurementTime ?? '',
    );
    _timing = value?.measurementTiming;
    _expanded = value?.hasData == true;
  }

  void _setText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _bodyFatController.dispose();
    _waistController.dispose();
    _customTimeController.dispose();
    super.dispose();
  }

  void _emit() {
    final measurement = BodyMeasurement(
      weightKg: parseBodyMeasurementNumber(_weightController.text),
      bodyFatPercent: parseBodyMeasurementNumber(_bodyFatController.text),
      waistCm: parseBodyMeasurementNumber(_waistController.text),
      measuredAt: widget.value?.measuredAt,
      measurementTiming: _timing,
      customMeasurementTime: _timing == MeasurementTiming.other
          ? _customTimeController.text.trim()
          : null,
    );
    widget.onChanged(measurement.hasData ? measurement : null);
  }

  String? _validate(String? raw, double min, double max, String unit) {
    return validateBodyMeasurementNumber(
      raw,
      min: min,
      max: max,
      unit: unit,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
      children: [
        Container(
          decoration: HealingDesignSystem.adaptiveCardDecoration(context),
          child: Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              initiallyExpanded: _expanded,
              onExpansionChanged: (value) => _expanded = value,
              leading: const Icon(Icons.monitor_weight_outlined,
                  color: HealingDesignSystem.primaryBlue),
              title: Text('身體數據（選填）',
                  style: HealingDesignSystem.titleMedium.copyWith(
                      color: HealingDesignSystem.adaptivePrimaryText(context))),
              subtitle: const Text('只記錄今天實際測量到的數字'),
              childrenPadding:
                  const EdgeInsets.all(HealingDesignSystem.paddingL),
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
                    setState(() {
                      _timing = value;
                      if (value != MeasurementTiming.other) {
                        _customTimeController.clear();
                      }
                    });
                    _emit();
                  },
                ),
                if (_timing == MeasurementTiming.other) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customTimeController,
                    decoration: const InputDecoration(
                      labelText: '自訂測量時間',
                      hintText: '例如：運動後、下午三點',
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) =>
                        value?.trim().isEmpty == false ? null : '選擇其他時間時請填寫',
                    onChanged: (_) => _emit(),
                  ),
                ],
                if (widget.value?.hasData == true) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        _weightController.clear();
                        _bodyFatController.clear();
                        _waistController.clear();
                        _customTimeController.clear();
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
        const OneDecimalTextInputFormatter(),
      ],
      decoration: InputDecoration(labelText: label, suffixText: unit),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) => _validate(value, min, max, unit),
      onChanged: (_) => _emit(),
    );
  }
}
