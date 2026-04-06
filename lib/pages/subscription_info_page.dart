import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pro_provider.dart';

/// 訂閱狀態和存儲管理頁面
class SubscriptionInfoPage extends StatelessWidget {
  const SubscriptionInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final proProvider = context.watch<ProProvider>();
    final isPro = proProvider.isPro;

    return Scaffold(
      appBar: AppBar(
        title: const Text('訂閱信息'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 當前訂閱狀態
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isPro
                      ? [Colors.amber[300]!, Colors.amber[600]!]
                      : [Colors.grey[300]!, Colors.grey[500]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPro ? Icons.auto_awesome : Icons.phone_android,
                        size: 22,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPro ? 'Pro 會員' : '免費版',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isPro
                        ? '感謝您的支持！享受所有高級功能。'
                        : '升級到 Pro 以解鎖所有功能。',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 功能對比
            Text(
              '功能對比',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            _buildFeatureComparison(
              context,
              Icons.cloud,
              '資料存儲',
              free: '本地存儲',
              pro: 'Firebase 雲端',
              freeColor: Colors.blue,
              proColor: Colors.amber,
            ),

            _buildFeatureComparison(
              context,
              Icons.calendar_today,
              '資料保留期',
              free: '最近 2 年',
              pro: '永久保存',
              freeColor: Colors.blue,
              proColor: Colors.amber,
            ),

            _buildFeatureComparison(
              context,
              Icons.sync_alt,
              '多設備同步',
              free: '不支持',
              pro: '支持',
              freeColor: Colors.blue,
              proColor: Colors.amber,
            ),

            _buildFeatureComparison(
              context,
              Icons.backup,
              '自動備份',
              free: '無備份',
              pro: '自動備份',
              freeColor: Colors.blue,
              proColor: Colors.amber,
            ),

            _buildFeatureComparison(
              context,
              Icons.bar_chart,
              '高級統計',
              free: '基礎功能',
              pro: '完整功能',
              freeColor: Colors.blue,
              proColor: Colors.amber,
            ),

            _buildFeatureComparison(
              context,
              Icons.lock,
              '隱私保護',
              free: '本地加密',
              pro: '雲端加密',
              freeColor: Colors.blue,
              proColor: Colors.amber,
            ),

            const SizedBox(height: 32),

            // 升級按鈕或優惠信息
            if (!isPro)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  border: Border.all(color: Colors.amber[200]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.celebration, size: 20, color: Colors.amber[900]),
                        const SizedBox(width: 6),
                        Text(
                          '升級到 Pro',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '享受無限的資料保存、多設備同步以及所有高級功能。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.amber[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '目前已暫時移除 Pro 訂閱頁面入口。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),

            if (isPro)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green[200]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '✅ Pro 會員已激活',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '感謝您支持我們！您的所有資料已保存到 Firebase 雲端。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.cloud_done, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '資料自動同步到多個設備',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.green[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // 存儲信息詳情
            Text(
              '存儲信息',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            _buildInfoCard(
              context,
              title: isPro ? '☁️ 雲端存儲' : '💾 本地存儲',
              description: isPro
                  ? '您的資料存儲在 Firebase 雲端，可在任何設備上訪問。'
                  : '您的資料存儲在設備本地，在卸載應用時會丟失。',
              icon: isPro ? Icons.cloud : Icons.storage,
              backgroundColor: (isPro ? Colors.amber[50] : Colors.blue[50]) ?? Colors.white,
              iconColor: isPro ? Colors.amber : Colors.blue,
            ),

            _buildInfoCard(
              context,
              title: '📅 資料保留',
              description: isPro
                  ? '您的資料無限期保存，永不過期。'
                  : '免費版本只保存最近 2 年的資料。超過 2 年的資料將被自動清除。',
              icon: Icons.calendar_today,
              backgroundColor: Colors.green[50] ?? Colors.white,
              iconColor: Colors.green,
            ),

            _buildInfoCard(
              context,
              title: '🔐 隱私與安全',
              description: '您的所有資料都被加密保存。只有您可以訪問您的個人資料。',
              icon: Icons.lock,
              backgroundColor: Colors.purple[50] ?? Colors.white,
              iconColor: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureComparison(
    BuildContext context,
    IconData icon,
    String feature, {
    required String free,
    required String pro,
    required Color freeColor,
    required Color proColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    feature,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: freeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                free,
                style: TextStyle(
                  fontSize: 12,
                  color: freeColor,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: proColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                pro,
                style: TextStyle(
                  fontSize: 12,
                  color: proColor,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color backgroundColor,
    required Color iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: iconColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                    height: 1.5,
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
