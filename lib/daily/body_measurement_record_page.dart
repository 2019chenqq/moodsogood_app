import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import 'widgets/body_measurement_page.dart';
import 'widgets/record_date_time_picker.dart';

/// Standalone entry backed by BodyMeasurementRecord, not DailyRecord.
class BodyMeasurementRecordPage extends StatefulWidget {
  const BodyMeasurementRecordPage({super.key});

  @override
  State<BodyMeasurementRecordPage> createState() =>
      _BodyMeasurementRecordPageState();
}

class _BodyMeasurementRecordPageState extends State<BodyMeasurementRecordPage> {
  DateTime _recordedAt = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        title: const Text('身體測量'),
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: RecordDateTimePicker(
              value: _recordedAt,
              onChanged: (value) => setState(() => _recordedAt = value),
            ),
          ),
          Expanded(
            child: BodyMeasurementPage(
              value: null,
              onChanged: (_) {},
              date: _recordedAt,
            ),
          ),
        ],
      ),
    );
  }
}
