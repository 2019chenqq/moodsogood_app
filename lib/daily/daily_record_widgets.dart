import 'package:flutter/material.dart';

// ============================================================
// UI Widgets
// ============================================================

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.trailing, Key? key}) : super(key: key);
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class RecordHeader extends StatelessWidget {
  const RecordHeader({
    super.key,
    required this.dateText,
    required this.timeText,
    required this.onPickDate,
    required this.onPickTime,
  });

  final String dateText;
  final String timeText;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickTime;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.calendar_today),
                title: const Text('日期', style: TextStyle(fontSize: 12)),
                subtitle: Text(dateText),
                onTap: () async => await onPickDate(),
              ),
            ),
            Expanded(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.access_time),
                title: const Text('時間', style: TextStyle(fontSize: 12)),
                subtitle: Text(timeText),
                onTap: () async => await onPickTime(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {Key? key}) : super(key: key);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

class TimeTile extends StatelessWidget {
  const TimeTile({
    Key? key,
    required this.label,
    required this.timeText,
    required this.onTap,
  }) : super(key: key);

  final String label;
  final String timeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(timeText),
      onTap: onTap,
    );
  }
}

class ListTileButton extends StatelessWidget {
  const ListTileButton(
      {super.key,
      required this.label,
      required this.valueText,
      required this.onTap});

  final String label;
  final String valueText;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        title: Text(label),
        subtitle: Text(valueText),
        trailing: const Icon(Icons.keyboard_arrow_down),
        onTap: onTap,
      ),
    );
  }
}

class SaveHintButton extends StatelessWidget {
  const SaveHintButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.save_outlined),
      label: const Text('儲存'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: const StadiumBorder(),
      ),
      onPressed: onPressed,
    );
  }
}
