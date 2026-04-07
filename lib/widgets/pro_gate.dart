import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pro_provider.dart';

/// 🔐 ProGate：包住任何「付費功能」
/// - Pro：顯示 child
/// - 非 Pro：顯示升級提示（或跳 UpgradePage）
class ProGate extends StatelessWidget {
  final Widget child;
  final bool replacePage; // 是否直接跳轉頁面

  const ProGate({
    super.key,
    required this.child,
    this.replacePage = false,
  });

  @override
  Widget build(BuildContext context) {
    final proProvider = context.watch<ProProvider>();

    // 已是 Pro（包含全域解鎖）→ 優先直接顯示
    if (proProvider.isPro) {
      return child;
    }

    // 還在載入訂閱狀態（App 剛啟動）
    if (proProvider.loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // 非 Pro → 顯示鎖定畫面
    if (replacePage) {
      // Pro 頁面已下架，先顯示鎖定提示卡
      return const Center(child: _UpgradeCard());
    }

    // 預設：半透明遮罩 + 解鎖按鈕
    return Stack(
      children: [
        // 原內容（模糊 / 半透明）
        Opacity(
          opacity: 0.25,
          child: AbsorbPointer(
            absorbing: true,
            child: child,
          ),
        ),

        // 鎖定提示
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.2),
            alignment: Alignment.center,
            child: _UpgradeCard(),
          ),
        ),
      ],
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '解鎖 心域 Pro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '此功能為 Pro 專屬\n升級即可使用完整分析與報表',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: null,
              child: const Text('暫停開放升級入口'),
            ),
          ],
        ),
      ),
    );
  }
}
