import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/healing_design_system.dart';
import '../pro/pro_page.dart';
import '../providers/pro_provider.dart';
import '../widgets/main_drawer.dart';
import 'innera_ai_chat_page.dart';
import 'innera_ai_mode.dart';

class InneraAiHomePage extends StatelessWidget {
  const InneraAiHomePage({super.key});

  void _openChat(BuildContext context, InneraAiMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InneraAiChatPage(initialMode: mode)),
    );
  }

  void _openSubscription(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProPage(source: 'ai_limit_reached'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final proProvider = context.watch<ProProvider>();
    final isPro = proProvider.isPro;

    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        title: const Text('心域 AI'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: '開啟選單',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
                HealingDesignSystem.adaptiveBackground(context),
              ],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _HeroHeader(
                onStart: () =>
                    _openChat(context, InneraAiMode.emotionalSupport),
              ),
              const SizedBox(height: 16),
              if (proProvider.loading)
                const Center(child: CircularProgressIndicator())
              else if (!isPro)
                _ProRequiredCard(
                  onUpgrade: () => _openSubscription(context),
                ),
              const SizedBox(height: 10),
              const _AiScopeCard(),
              const SizedBox(height: 18),
              Text(
                '心域 AI 可協助整理與回顧紀錄，但無法診斷疾病、取代醫師或提供緊急醫療服務。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: HealingDesignSystem.adaptiveSecondaryText(context),
                      height: 1.5,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: HealingDesignSystem.adaptiveCardDecoration(
        context,
        radius: 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: HealingDesignSystem.primaryGradient(),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(
            '有什麼想說的？',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '不用先選模式，從你現在最想說的開始就好。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('跟 Innera 說說'),
          ),
        ],
      ),
    );
  }
}

class _ProRequiredCard extends StatelessWidget {
  const _ProRequiredCard({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveSurface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '每天各模式免費 3 則訊息',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          const Text('登入即可使用四個模式，各模式額度分開計算，台灣時間每日 00:00 重置。Pro 會員維持原有使用權益。'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onUpgrade,
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('查看訂閱方案'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiScopeCard extends StatelessWidget {
  const _AiScopeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          '心域 AI 能做什麼',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
        ),
        children: const [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '陪你整理當下感受、回顧授權的近期紀錄，並協助整理狀態紀錄。\n\nAI 內容僅供自我覺察與紀錄參考，不能診斷、調整藥物或取代專業評估與緊急服務。',
              style: TextStyle(height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}
