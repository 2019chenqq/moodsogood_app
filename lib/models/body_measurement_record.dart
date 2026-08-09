import 'package:cloud_firestore/cloud_firestore.dart';

import 'daily_record.dart';

class BodyMeasurementRecord {
  const BodyMeasurementRecord({
    required this.id,
    required this.timestamp,
    this.weightKg,
    this.bodyFatPercent,
    this.waistCm,
    this.measurementTiming,
    this.otherTimingText,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final DateTime timestamp;
  final double? weightKg;
  final double? bodyFatPercent;
  final double? waistCm;
  final MeasurementTiming? measurementTiming;
  final String? otherTimingText;
  final String? note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasMeasurements =>
      weightKg != null || bodyFatPercent != null || waistCm != null;

  bool get isValid =>
      _valid(weightKg, 20, 300) &&
      _valid(bodyFatPercent, 1, 70) &&
      _valid(waistCm, 30, 250) &&
      (measurementTiming != MeasurementTiming.other ||
          otherTimingText?.trim().isNotEmpty == true);

  Map<String, dynamic> toMap() => {
        'timestamp': Timestamp.fromDate(timestamp),
        'weightKg': weightKg,
        'bodyFatPercent': bodyFatPercent,
        'waistCm': waistCm,
        'measurementTiming': measurementTiming?.name,
        'otherTimingText': measurementTiming == MeasurementTiming.other
            ? otherTimingText?.trim()
            : null,
        'note': note?.trim() ?? '',
      };

  factory BodyMeasurementRecord.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final timingName = map['measurementTiming']?.toString();
    return BodyMeasurementRecord(
      id: id,
      timestamp: _asDate(map['timestamp']) ??
          (throw const FormatException(
            'BodyMeasurementRecord requires a valid timestamp.',
          )),
      weightKg: _number(map['weightKg']),
      bodyFatPercent: _number(map['bodyFatPercent']),
      waistCm: _number(map['waistCm']),
      measurementTiming: MeasurementTiming.values
          .where((value) => value.name == timingName)
          .firstOrNull,
      otherTimingText:
          (map['otherTimingText'] ?? map['customMeasurementTime'])?.toString(),
      note: map['note']?.toString(),
      createdAt: _asDate(map['createdAt']),
      updatedAt: _asDate(map['updatedAt']),
    );
  }

  BodyMeasurement toLegacyValue() => BodyMeasurement(
        weightKg: weightKg,
        bodyFatPercent: bodyFatPercent,
        waistCm: waistCm,
        measuredAt: timestamp,
        measurementTiming: measurementTiming,
        customMeasurementTime: otherTimingText,
      );

  static bool _valid(double? value, double min, double max) =>
      value == null ||
      (value >= min &&
          value <= max &&
          ((value * 10) - (value * 10).round()).abs() < 0.000000001);

  static double? _number(dynamic value) {
    final number = value is num ? value.toDouble() : null;
    return number == null ? null : (number * 10).roundToDouble() / 10;
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
