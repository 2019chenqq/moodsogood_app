import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../innera_ai_mode.dart';

class AiModeCard extends StatelessWidget {
  const AiModeCard({super.key, required this.mode, required this.onTap});

  final InneraAiMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _accentForMode(mode);
    return Card(
      elevation: 0,
      color: HealingDesignSystem.adaptiveSurface(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(mode.icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: HealingDesignSystem.adaptivePrimaryText(
                                context),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mode.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: HealingDesignSystem.adaptiveSecondaryText(
                              context,
                            ),
                            height: 1.45,
                          ),
                    ),
                    if (mode == InneraAiMode.physicalHealth) ...[
                      const SizedBox(height: 8),
                      Text(
                        '若有立即危險或嚴重身體不適，請直接尋求醫療協助。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: HealingDesignSystem.adaptiveSecondaryText(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _accentForMode(InneraAiMode mode) {
    switch (mode) {
      case InneraAiMode.dailyRecord:
        return HealingDesignSystem.primaryBlue;
      case InneraAiMode.emotionalSupport:
        return HealingDesignSystem.accentPurple;
      case InneraAiMode.physicalHealth:
        return HealingDesignSystem.warningOrange;
      case InneraAiMode.recentReview:
        return HealingDesignSystem.successGreen;
    }
  }
}
