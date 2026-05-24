import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class ProPreviewPage extends StatelessWidget {
  const ProPreviewPage({super.key});

  Future<void> _logInterested() async {
    await FirebaseAnalytics.instance.logEvent(
      name: 'pro_interest_click',
      parameters: {
        'source': 'deep_ai_analysis',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('心域 Pro'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [
                    color.primaryContainer,
                    color.secondaryContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome, size: 42),
                  const SizedBox(height: 16),
                  Text(
                    '深入 AI 分析',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '不只是回饋今天，而是幫你整理一段時間內的情緒、睡眠、症狀與日記脈絡。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _FeatureCard(
              icon: Icons.timeline,
              title: '近 7 天情緒變化整理',
              description: '協助你看見最近情緒是否有明顯波動、低落或壓力累積。',
            ),
            _FeatureCard(
              icon: Icons.bedtime_outlined,
              title: '睡眠與情緒交叉觀察',
              description: '整理睡眠狀態、症狀與情緒分數之間可能出現的關聯。',
            ),
            _FeatureCard(
              icon: Icons.psychology_alt_outlined,
              title: '日記主題分析',
              description: '從文字中整理反覆出現的情緒主題，例如壓力、人際、疲憊或自責。',
            ),
            _FeatureCard(
              icon: Icons.medical_information_outlined,
              title: '回診前重點摘要',
              description: '幫你把近期狀態整理成比較容易和醫師、心理師討論的重點。',
            ),

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: color.surfaceContainerHighest.withOpacity(0.7),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                '提醒：AI 分析僅作為自我覺察與紀錄整理輔助，不取代醫師、心理師或其他專業人員的判斷。',
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.6,
                  color: color.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(height: 28),

            FilledButton.icon(
              onPressed: () async {
                await _logInterested();

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已記錄你的興趣，正式 Pro 功能開放後會優先優化這項功能。'),
                  ),
                );
              },
              icon: const Icon(Icons.favorite_outline),
              label: const Text('我想使用這個功能'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),

            const SizedBox(height: 12),

            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('先回到日記'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: color.outlineVariant.withOpacity(0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.primaryContainer,
            child: Icon(icon, color: color.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: color.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}