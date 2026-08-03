import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../daily/daily_record_history.dart';
import '../meds/med_symptom_compare_page.dart';

class TrendReviewHubPage extends StatelessWidget {
  const TrendReviewHubPage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('趨勢回顧'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            '把不同時間留下的紀錄整理成變化，幫助你回顧，也方便回診時說明。',
            style: HealingDesignSystem.bodyMedium.copyWith(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _TrendEntryCard(
            icon: Icons.bedtime_outlined,
            title: '睡眠洞察',
            subtitle: '查看睡眠品質、時數與常見睡眠狀況',
            color: const Color(0xFF7986CB),
            onTap: () => _push(
              context,
              const DailyRecordHistory(initialTab: 1),
            ),
          ),
          const SizedBox(height: 12),
          _TrendEntryCard(
            icon: Icons.show_chart_rounded,
            title: '情緒趨勢',
            subtitle: '比較不同時間範圍的整體情緒與主要情緒',
            color: const Color(0xFF7DB7D8),
            onTap: () => _push(
              context,
              const DailyRecordHistory(initialTab: 2),
            ),
          ),
          const SizedBox(height: 12),
          _TrendEntryCard(
            icon: Icons.compare_arrows_rounded,
            title: '症狀比對',
            subtitle: '比較調藥前後的症狀與情緒變化',
            color: const Color(0xFF26A69A),
            onTap: () => _push(context, const MedSymptomComparePage()),
          ),
        ],
      ),
    );
  }
}

class _TrendEntryCard extends StatelessWidget {
  const _TrendEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: HealingDesignSystem.adaptiveSecondaryText(
                                context),
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
