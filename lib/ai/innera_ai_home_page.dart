import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/healing_design_system.dart';
import '../pro/pro_page.dart';
import '../providers/pro_provider.dart';
import '../widgets/main_drawer.dart';
import 'innera_ai_chat_page.dart';
import 'innera_ai_mode.dart';
import 'widgets/ai_mode_card.dart';

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
                isPro: isPro,
                onStart: () => isPro
                    ? _openChat(context, InneraAiMode.emotionalSupport)
                    : _openSubscription(context),
              ),
              const SizedBox(height: 16),
              if (proProvider.loading)
                const Center(child: CircularProgressIndicator())
              else if (isPro)
                ...InneraAiMode.values.map(
                  (mode) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AiModeCard(
                      mode: mode,
                      onTap: () => _openChat(context, mode),
                    ),
                  ),
                )
              else
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
  const _HeroHeader({required this.isPro, required this.onStart});

  final bool isPro;
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
            '心域 AI',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '根據你授權的紀錄，協助整理現在與近期的狀態',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onStart,
            icon: Icon(
                isPro ? Icons.chat_rounded : Icons.workspace_premium_rounded),
            label: Text(isPro ? '開始對話' : '查看 Pro 方案'),
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
            '心域 AI 為 Pro 功能',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          const Text('訂閱後可使用 AI 對話、近期紀錄回顧與每日紀錄整理。'),
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
      padding: const EdgeInsets.all(16),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '心域 AI 能做什麼',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          SizedBox(height: 10),
          Text('• 陪你整理當下的感受與想法'),
          Text('• 回顧你授權的情緒、睡眠、症狀與日記紀錄'),
          Text('• 協助建立每日紀錄草稿與整理可討論的重點'),
          SizedBox(height: 12),
          Text(
            '能力限制與重要提醒',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 6),
          Text(
            'AI 可能產生不完整或不正確的內容，僅供自我覺察與紀錄整理參考；不能診斷疾病、判定病因、調整藥物或取代醫師、心理師及其他專業人員的評估與治療，也不提供緊急醫療服務。',
            style: TextStyle(height: 1.55),
          ),
        ],
      ),
    );
  }
}
