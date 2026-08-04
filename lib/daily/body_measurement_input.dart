import 'package:flutter/services.dart';

/// Accepts an empty value, any number of integer digits, and at most one
/// decimal digit. Invalid edits are rejected as a whole instead of filtering
/// individual characters, which avoids truncating multi-digit measurements.
class OneDecimalTextInputFormatter extends TextInputFormatter {
  const OneDecimalTextInputFormatter();

  static final RegExp _pattern = RegExp(r'^(?:\d+(?:\.\d?)?)?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalizedText = _normalizeDecimalSeparator(newValue.text);
    if (!_pattern.hasMatch(normalizedText)) return oldValue;
    return newValue.copyWith(text: normalizedText);
  }
}

double? parseBodyMeasurementNumber(String raw) {
  final text = _normalizeDecimalSeparator(raw.trim());
  if (text.isEmpty) return null;
  if (!RegExp(r'^\d+(?:\.\d?)?$').hasMatch(text)) return null;
  return double.tryParse(text);
}

String _normalizeDecimalSeparator(String value) =>
    value.replaceAll(RegExp(r'[,，。]'), '.');

String formatBodyMeasurementNumber(double? value) {
  if (value == null) return '';
  final rounded = (value * 10).roundToDouble() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
}

String? validateBodyMeasurementNumber(
  String? raw, {
  required double min,
  required double max,
  required String unit,
}) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final value = parseBodyMeasurementNumber(text);
  if (value == null) return '請輸入整數或小數點後一位';
  if (value < min || value > max) return '請輸入 $min～$max $unit';
  return null;
}
