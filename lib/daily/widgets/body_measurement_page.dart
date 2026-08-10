import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../constants/healing_design_system.dart';
import '../../models/daily_record.dart';
import '../../models/body_measurement_record.dart';
import '../body_measurement_input.dart';
import '../body_measurement_record_service.dart';
import '../unified_body_measurement_repository.dart';

class BodyMeasurementPage extends StatefulWidget {
  const BodyMeasurementPage({
    super.key,
    required this.value,
    required this.onChanged,
    required this.date,
  });

  final BodyMeasurement? value;
  final ValueChanged<BodyMeasurement?> onChanged;
  final DateTime date;

  @override
  State<BodyMeasurementPage> createState() => _BodyMeasurementPageState();
}

class _BodyMeasurementPageState extends State<BodyMeasurementPage> {
  late final TextEditingController _weightController;
  late final TextEditingController _bodyFatController;
  late final TextEditingController _waistController;
  late final TextEditingController _customTimeController;
  late final TextEditingController _noteController;
  MeasurementTiming? _timing;
  bool _expanded = false;
  bool _saving = false;
  BodyMeasurementRecord? _editing;
  List<BodyMeasurementRecord> _records = const [];
  BodyMeasurement? _legacyMeasurement;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController();
    _bodyFatController = TextEditingController();
    _waistController = TextEditingController();
    _customTimeController = TextEditingController();
    _noteController = TextEditingController();
    _updateFromValue(null);
    _loadRecords();
  }

  @override
  void didUpdateWidget(BodyMeasurementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !_currentInputRepresents(widget.value)) {
      if (_editing != null) _updateFromValue(widget.value);
    }
    if (!_sameDay(oldWidget.date, widget.date)) {
      _clearForm();
      _loadRecords();
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
    _noteController.dispose();
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

  Future<void> _loadRecords() async {
    if (Firebase.apps.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final records = await BodyMeasurementRecordService().getByDate(
        userId: uid,
        date: widget.date,
      );
      final unified = await UnifiedBodyMeasurementRepository().getByDateRange(
        userId: uid,
        start: widget.date,
        end: widget.date,
      );
      final legacy = unified
          .where(
              (item) => item.source == BodyMeasurementSource.legacyDailyRecord)
          .firstOrNull;
      if (mounted) {
        setState(() {
          _records = records.reversed.toList();
          _legacyMeasurement = legacy?.measurement;
        });
      }
    } catch (error) {
      debugPrint('Body measurements load failed: $error');
    }
  }

  Future<void> _saveMeasurement() async {
    if (Firebase.apps.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final value = BodyMeasurement(
      weightKg: parseBodyMeasurementNumber(_weightController.text),
      bodyFatPercent: parseBodyMeasurementNumber(_bodyFatController.text),
      waistCm: parseBodyMeasurementNumber(_waistController.text),
      measurementTiming: _timing,
      customMeasurementTime: _customTimeController.text.trim(),
    );
    if (uid == null || !value.hasData || !value.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先完成有效的測量資料')),
      );
      return;
    }
    final now = DateTime.now();
    final timestamp = _editing?.timestamp ??
        DateTime(
          widget.date.year,
          widget.date.month,
          widget.date.day,
          now.hour,
          now.minute,
          now.second,
          now.millisecond,
        );
    setState(() => _saving = true);
    try {
      await BodyMeasurementRecordService().save(
        userId: uid,
        record: BodyMeasurementRecord(
          id: _editing?.id ?? '',
          timestamp: timestamp,
          weightKg: value.weightKg,
          bodyFatPercent: value.bodyFatPercent,
          waistCm: value.waistCm,
          measurementTiming: value.measurementTiming,
          otherTimingText: value.effectiveCustomMeasurementTime,
          note: _noteController.text,
        ),
      );
      _clearForm();
      await _loadRecords();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _editRecord(BodyMeasurementRecord record) {
    setState(() {
      _editing = record;
      _expanded = true;
      _setText(_weightController, formatBodyMeasurementNumber(record.weightKg));
      _setText(
        _bodyFatController,
        formatBodyMeasurementNumber(record.bodyFatPercent),
      );
      _setText(_waistController, formatBodyMeasurementNumber(record.waistCm));
      _setText(_customTimeController, record.otherTimingText ?? '');
      _setText(_noteController, record.note ?? '');
      _timing = record.measurementTiming;
    });
  }

  Future<void> _deleteRecord(BodyMeasurementRecord record) async {
    if (Firebase.apps.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await BodyMeasurementRecordService().delete(
      userId: uid,
      recordId: record.id,
    );
    if (_editing?.id == record.id) _clearForm();
    await _loadRecords();
  }

  void _clearForm() {
    _weightController.clear();
    _bodyFatController.clear();
    _waistController.clear();
    _customTimeController.clear();
    _noteController.clear();
    _editing = null;
    _timing = null;
    widget.onChanged(null);
    if (mounted) setState(() {});
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
        if (_legacyMeasurement?.hasData == true) ...[
          Text(
            '舊版每日測量',
            style: HealingDesignSystem.titleMedium.copyWith(
              color: HealingDesignSystem.adaptivePrimaryText(context),
            ),
          ),
          const SizedBox(height: HealingDesignSystem.paddingS),
          Container(
            decoration: HealingDesignSystem.adaptiveCardDecoration(context),
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(_legacySummary(_legacyMeasurement!)),
              subtitle: const Text('舊 DailyRecord 日資料（僅供讀取）'),
            ),
          ),
          const SizedBox(height: HealingDesignSystem.paddingM),
        ],
        if (_records.isNotEmpty) ...[
          Text(
            '當日測量',
            style: HealingDesignSystem.titleMedium.copyWith(
              color: HealingDesignSystem.adaptivePrimaryText(context),
            ),
          ),
          const SizedBox(height: HealingDesignSystem.paddingS),
          for (final record in _records)
            Padding(
              padding:
                  const EdgeInsets.only(bottom: HealingDesignSystem.paddingS),
              child: Container(
                decoration: HealingDesignSystem.adaptiveCardDecoration(
                  context,
                  radius: HealingDesignSystem.radiusM,
                ),
                child: ListTile(
                  title: Text(_measurementSummary(record)),
                  subtitle: Text(_measurementSubtitle(record)),
                  onTap: () => _editRecord(record),
                  trailing: IconButton(
                    tooltip: '刪除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteRecord(record),
                  ),
                ),
              ),
            ),
          const SizedBox(height: HealingDesignSystem.paddingM),
        ],
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
                const SizedBox(height: HealingDesignSystem.paddingM),
                _numberField(_bodyFatController, '體脂率', '%', 1, 70),
                const SizedBox(height: HealingDesignSystem.paddingM),
                _numberField(_waistController, '腰圍（選填）', 'cm', 30, 250),
                const SizedBox(height: HealingDesignSystem.paddingM),
                _TimingPicker(
                  value: _timing,
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
                  const SizedBox(height: HealingDesignSystem.paddingM),
                  TextFormField(
                    controller: _customTimeController,
                    decoration: _fieldDecoration(
                      context,
                      labelText: '自訂測量時間',
                      hintText: '例如：運動後、下午三點',
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) =>
                        value?.trim().isEmpty == false ? null : '選擇其他時間時請填寫',
                    onChanged: (_) => _emit(),
                  ),
                ],
                const SizedBox(height: HealingDesignSystem.paddingM),
                TextField(
                  controller: _noteController,
                  decoration: _fieldDecoration(context, labelText: '備註（選填）'),
                  maxLines: 2,
                ),
                const SizedBox(height: HealingDesignSystem.paddingM),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _saveMeasurement,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_editing == null ? '新增測量' : '儲存修改'),
                  ),
                ),
                if (widget.value?.hasData == true) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        _clearForm();
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

  String _measurementSummary(BodyMeasurementRecord record) => [
        if (record.weightKg != null)
          '${formatBodyMeasurementNumber(record.weightKg)} kg',
        if (record.bodyFatPercent != null)
          '${formatBodyMeasurementNumber(record.bodyFatPercent)}%',
        if (record.waistCm != null)
          '${formatBodyMeasurementNumber(record.waistCm)} cm',
      ].join(' · ');

  String _legacySummary(BodyMeasurement measurement) => [
        if (measurement.weightKg != null)
          '${formatBodyMeasurementNumber(measurement.weightKg)} kg',
        if (measurement.bodyFatPercent != null)
          '${formatBodyMeasurementNumber(measurement.bodyFatPercent)}%',
        if (measurement.waistCm != null)
          '${formatBodyMeasurementNumber(measurement.waistCm)} cm',
      ].join(' · ');

  String _measurementSubtitle(BodyMeasurementRecord record) {
    final time = record.timestamp;
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final timing = record.measurementTiming == MeasurementTiming.other
        ? record.otherTimingText
        : record.measurementTiming?.displayName;
    return [
      clock,
      if (timing?.isNotEmpty == true) timing!,
      if (record.note?.trim().isNotEmpty == true) record.note!.trim()
    ].join(' · ');
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _numberField(TextEditingController controller, String label,
      String unit, double min, double max) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        const OneDecimalTextInputFormatter(),
      ],
      decoration: _fieldDecoration(context, labelText: label, suffixText: unit),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) => _validate(value, min, max, unit),
      onChanged: (_) => _emit(),
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String labelText,
    String? hintText,
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      suffixText: suffixText,
      filled: true,
      fillColor: HealingDesignSystem.adaptiveFill(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        borderSide: BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        borderSide: BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        borderSide: const BorderSide(color: HealingDesignSystem.primaryBlue),
      ),
    );
  }
}

class _TimingPicker extends StatelessWidget {
  const _TimingPicker({
    required this.value,
    required this.onChanged,
  });

  final MeasurementTiming? value;
  final ValueChanged<MeasurementTiming?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <MeasurementTiming?>[null, ...MeasurementTiming.values];
    return InputDecorator(
      decoration: InputDecoration(
        labelText: '測量時間（選填）',
        filled: true,
        fillColor: HealingDesignSystem.adaptiveFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
          borderSide: BorderSide(
            color: HealingDesignSystem.adaptiveCardBorder(context),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
          borderSide: BorderSide(
            color: HealingDesignSystem.adaptiveCardBorder(context),
          ),
        ),
      ),
      child: Column(
        children: [
          for (final option in options)
            InkWell(
              borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
              onTap: () => onChanged(option),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: HealingDesignSystem.paddingS,
                ),
                child: Row(
                  children: [
                    Icon(
                      option == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: option == value
                          ? HealingDesignSystem.primaryBlue
                          : HealingDesignSystem.adaptiveSecondaryText(context),
                    ),
                    const SizedBox(width: HealingDesignSystem.paddingM),
                    Expanded(
                      child: Text(
                        option?.displayName ?? '尚未填寫',
                        style: HealingDesignSystem.bodyMedium.copyWith(
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
