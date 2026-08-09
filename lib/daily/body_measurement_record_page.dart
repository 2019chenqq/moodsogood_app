import 'package:flutter/material.dart';

import 'widgets/body_measurement_page.dart';

/// Standalone entry backed by BodyMeasurementRecord, not DailyRecord.
class BodyMeasurementRecordPage extends StatelessWidget {
  const BodyMeasurementRecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('身體測量')),
      body: BodyMeasurementPage(
        value: null,
        onChanged: (_) {},
        date: DateTime.now(),
      ),
    );
  }
}
