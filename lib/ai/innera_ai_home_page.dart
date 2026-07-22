import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
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

  @override
  Widget build(BuildContext context) {
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
              ...InneraAiMode.values.map(
                (mode) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AiModeCard(
                    mode: mode,
                    onTap: () => _openChat(context, mode),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '近期可以問',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
              ),
              const SizedBox(height: 10),
              const _QuestionChip(text: '我最近為什麼特別疲倦？'),
              const _QuestionChip(text: '最近睡眠和情緒有什麼變化？'),
              const _QuestionChip(text: '幫我整理下次回診可以說的重點'),
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
            icon: const Icon(Icons.chat_rounded),
            label: const Text('開始對話'),
          ),
        ],
      ),
    );
  }
}

class _QuestionChip extends StatelessWidget {
  const _QuestionChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveSurface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: HealingDesignSystem.adaptivePrimaryText(context),
            ),
      ),
    );
  }
}
