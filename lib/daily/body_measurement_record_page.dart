import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import 'widgets/body_measurement_page.dart';

/// Standalone entry backed by BodyMeasurementRecord, not DailyRecord.
class BodyMeasurementRecordPage extends StatelessWidget {
  const BodyMeasurementRecordPage({super.key});

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
      body: BodyMeasurementPage(
        value: null,
        onChanged: (_) {},
        date: DateTime.now(),
      ),
    );
  }
}
