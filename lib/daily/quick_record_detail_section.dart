import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../models/health_event.dart';
import '../utils/date_helper.dart';
import 'daily_state_dimensions.dart';

class QuickRecordDetailSection extends StatelessWidget {
  const QuickRecordDetailSection({
    super.key,
    required this.events,
    required this.onEdit,
    required this.onDelete,
  });

  final List<HealthEvent> events;
  final ValueChanged<HealthEvent> onEdit;
  final ValueChanged<HealthEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('quick-record-detail-section'),
      children: events.map((event) => _card(context, event)).toList(),
    );
  }

  Widget _card(BuildContext context, HealthEvent event) {
    final stateLabels = <String>[];
    for (final dimension in kDailyStateDimensions) {
      final value = event.stateChanges[dimension.id];
      if (value != null) stateLabels.add('${dimension.displayName} $value');
    }
    final details = <String>[
      if (event.emotions.isNotEmpty)
        '情緒：${event.emotions.map((item) => '${item.name} ${item.intensity}').join('、')}',
      if (event.symptoms.isNotEmpty)
        '症狀：${event.symptoms.map((item) => '${item.name} ${item.severity}').join('、')}',
      if (stateLabels.isNotEmpty) '狀態：${stateLabels.join('、')}',
      if (event.context?.trim().isNotEmpty == true)
        '情境：${event.context!.trim()}',
      if (event.note?.trim().isNotEmpty == true) '備註：${event.note!.trim()}',
    ];
    final time = DateHelper.formatTime(TimeOfDay.fromDateTime(event.timestamp));

    return Container(
      key: Key('quick-record-${event.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: ListTile(
        title: Text(time),
        subtitle: details.isEmpty ? null : Text(details.join('\n')),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'edit') onEdit(event);
            if (action == 'delete') onDelete(event);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('編輯')),
            PopupMenuItem(value: 'delete', child: Text('刪除')),
          ],
        ),
      ),
    );
  }
}
