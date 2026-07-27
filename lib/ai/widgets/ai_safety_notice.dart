import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/healing_design_system.dart';
import '../innera_ai_safety_service.dart';

class AiSafetyNotice extends StatelessWidget {
  const AiSafetyNotice({
    super.key,
    required this.level,
    required this.onTemporarilySafe,
  });

  final AiSafetyLevel level;
  final VoidCallback onTemporarilySafe;

  @override
  Widget build(BuildContext context) {
    if (level != AiSafetyLevel.imminentDanger &&
        level != AiSafetyLevel.medicalUrgency) {
      return const SizedBox.shrink();
    }

    final isMedical = level == AiSafetyLevel.medicalUrgency;
    final color = Theme.of(context).colorScheme.error;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emergency_rounded, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMedical ? '可能需要立即醫療評估' : '請先確認目前安全',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isMedical
                ? InneraAiSafetyService.medicalUrgencyReply
                : InneraAiSafetyService.imminentSelfHarmReply,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                  height: 1.55,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CallButton(label: '撥打 119', phone: '119'),
              if (!isMedical) ...const [
                _CallButton(label: '撥打 1925', phone: '1925'),
                _CallButton(label: '撥打 1995', phone: '1995'),
                _CallButton(label: '撥打 1980', phone: '1980'),
              ],
            ],
          ),
          if (!isMedical) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onTemporarilySafe,
              child: const Text('我目前暫時安全'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.label, required this.phone});

  final String label;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () async {
        final uri = Uri.parse('tel:$phone');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      },
      icon: const Icon(Icons.phone_rounded, size: 18),
      label: Text(label),
    );
  }
}
