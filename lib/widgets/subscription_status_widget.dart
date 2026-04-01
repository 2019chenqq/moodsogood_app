import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pro_provider.dart';
import '../utils/firebase_sync_config.dart';
import '../pages/upgrade_page.dart';

/// 訂閱狀態卡片 - 可在多個頁面中使用
class SubscriptionStatusCard extends StatelessWidget {
  final bool compact;
  final VoidCallback? onTapUpgrade;

  const SubscriptionStatusCard({
    super.key,
    this.compact = false,
    this.onTapUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final proProvider = context.watch<ProProvider>();
    final isPro = proProvider.isPro;

    if (compact) {
      // 緊湊版本（用於頂部或列表中）
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isPro
                ? [Colors.amber[300]!, Colors.amber[600]!]
                : [Colors.grey[300]!, Colors.grey[500]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPro ? Icons.auto_awesome : Icons.phone_android,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  isPro ? 'Pro 會員' : '免費版',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            if (!isPro)
              GestureDetector(
                onTap: onTapUpgrade,
                child: Text(
                  '升級',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // 完整版本
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPro
              ? [Colors.amber[300]!, Colors.amber[600]!]
              : [Colors.grey[300]!, Colors.grey[500]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPro ? Icons.auto_awesome : Icons.phone_android,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isPro ? 'Pro 會員' : '免費版',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    FirebaseSyncConfig.getStorageType(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  FirebaseSyncConfig.getDataRetention(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                isPro ? Icons.cloud : Icons.storage,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isPro
                      ? '✅ 雲端備份 + 多設備同步'
                      : '✅ 本地存儲（本機隱私）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (!isPro) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upgrade),
                label: const Text('升級到 Pro'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const UpgradePage(),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 免費版本限制提示
class FreePlanLimitationBanner extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback? onLearnMore;

  const FreePlanLimitationBanner({
    super.key,
    required this.title,
    required this.description,
    this.onLearnMore,
  });

  @override
  Widget build(BuildContext context) {
    final proProvider = context.watch<ProProvider>();

    // Pro 用戶不顯示
    if (proProvider.isPro) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blue[700],
                    height: 1.4,
                  ),
                ),
                if (onLearnMore != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onLearnMore,
                    child: Text(
                      '了解更多',
                      style: TextStyle(
                        color: Colors.blue[600],
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 數據保留期限警告
class DataRetentionWarning extends StatelessWidget {
  final int daysRemaining;

  const DataRetentionWarning({
    super.key,
    this.daysRemaining = 7,
  });

  @override
  Widget build(BuildContext context) {
    final proProvider = context.watch<ProProvider>();

    // Pro 用戶不顯示
    if (proProvider.isPro || daysRemaining > 14) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: Colors.orange[700], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '數據即將過期',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[900],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '您的 $daysRemaining 天內的數據將被刪除。升級到 Pro 保留所有數據。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.orange[700],
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
