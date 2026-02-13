import 'package:flutter/material.dart';
import '../providers/room_feed_provider.dart';

class EmpathyBar extends StatelessWidget {
  final int hug, listen, hope, heart;
  final void Function(ReactType type) onReact;

  const EmpathyBar({
    super.key,
    required this.hug,
    required this.listen,
    required this.hope,
    required this.heart,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _chip(context, '🫂 $hug', () => onReact(ReactType.hug)),
        _chip(context, '👂 $listen', () => onReact(ReactType.listen)),
        _chip(context, '🌱 $hope', () => onReact(ReactType.hope)),
        _chip(context, '💙 $heart', () => onReact(ReactType.heart)),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label),
      ),
    );
  }
}
