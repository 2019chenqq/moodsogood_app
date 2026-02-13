import 'package:flutter/material.dart';

class WarmMessageCard extends StatelessWidget {
  const WarmMessageCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.favorite_border),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '你已經很努力了。今天也先照顧好你自己。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
