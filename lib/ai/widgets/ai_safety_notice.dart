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
    if (level != AiSafetyLevel.possibleSelfHarm &&
        level != AiSafetyLevel.imminentDanger &&
        level != AiSafetyLevel.medicalUrgency) {
      return const SizedBox.shrink();
    }

    final isMedical = level == AiSafetyLevel.medicalUrgency;
    final isUrgent = level == AiSafetyLevel.imminentDanger || isMedical;
    final color = isUrgent
        ? Theme.of(context).colorScheme.tertiary
        : HealingDesignSystem.primaryBlue;
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
              Icon(
                isUrgent
                    ? Icons.emergency_rounded
                    : Icons.health_and_safety_outlined,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMedical
                      ? '可能需要立即醫療評估'
                      : isUrgent
                          ? '請優先確認目前安全'
                          : '你不需要獨自承受',
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
                : isUrgent
                    ? InneraAiSafetyService.imminentSelfHarmReply
                    : InneraAiSafetyService.concernSelfHarmReply,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                  height: 1.55,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _CallButton(
              label: isUrgent ? '撥打 119 緊急救護' : '撥打 1925 安心專線',
              phone: isUrgent ? '119' : '1925',
              primary: true,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _CallButton(label: '119 緊急救護', phone: '119'),
              _CallButton(label: '110 警察', phone: '110'),
              _CallButton(label: '1925 安心專線', phone: '1925'),
              _CallButton(label: '1995 生命線', phone: '1995'),
              _CallButton(label: '1980 張老師', phone: '1980'),
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
  const _CallButton({
    required this.label,
    required this.phone,
    this.primary = false,
  });

  final String label;
  final String phone;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    Future<void> onPressed() async {
      final uri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    if (!primary) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.phone_outlined, size: 18),
        label: Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.phone_rounded, size: 18),
      label: Text(label),
    );
  }
}
