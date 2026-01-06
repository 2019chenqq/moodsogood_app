import 'package:flutter/material.dart';

class ProPage extends StatelessWidget {
  const ProPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('升級 Pro'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroCard(),
          const SizedBox(height: 16),

          const Text(
            '解鎖內容',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),

          const _FeatureItem(
            title: '記錄歷程：30 天 / 全部',
            subtitle: '查看更長時間範圍的每日紀錄卡片清單。',
            icon: Icons.history,
          ),
          const _FeatureItem(
            title: '情緒趨勢圖：30 天 / 全部',
            subtitle: '長期趨勢更有助於回顧與覺察。',
            icon: Icons.show_chart,
          ),
          const _FeatureItem(
            title: '更多進階功能（規劃中）',
            subtitle: '例如匯出、進階洞察、備份等。',
            icon: Icons.auto_awesome,
          ),

          const SizedBox(height: 20),

          const Text(
            '方案與價格',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),

          _PlanCard(
            title: 'Pro（即將上線）',
            priceText: '尚未串接付款',
            bullets: const [
              '解鎖 30 天 / 全部範圍',
              '長期趨勢分析',
              '持續更新更多功能',
            ],
          ),

          const SizedBox(height: 20),

          FilledButton(
            onPressed: () {
              // 目前先不做購買，避免上架前流程不完整
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('付款功能尚未上線，敬請期待。')),
              );
            },
            child: const Text('立即升級（即將上線）'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('先不用，返回'),
          ),

          const SizedBox(height: 12),
          const Text(
            '提示：你可以先把 ProPage 做成說明頁，上架後再更新版本串接 Google Play 付款。',
            style: TextStyle(color: Colors.grey, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '用更長的視角\n看見自己的變化',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2),
          ),
          SizedBox(height: 8),
          Text(
            'Pro 會解鎖長期範圍的歷程與趨勢，\n幫你更完整地回顧與整理。',
            style: TextStyle(color: Colors.grey, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _FeatureItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String priceText;
  final List<String> bullets;

  const _PlanCard({
    required this.title,
    required this.priceText,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(priceText, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ...bullets.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(t)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
