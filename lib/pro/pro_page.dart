import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../providers/pro_provider.dart';
import '../analytics_service.dart';

class ProPage extends StatefulWidget {
  const ProPage({super.key});

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> {
  bool _isLoading = false;
  String? _errorMessage;
  String? _statusMessage;
  Offering? _offering;

  String get _storeName {
    if (kIsWeb) return '商店';
    return defaultTargetPlatform == TargetPlatform.iOS
        ? 'App Store'
        : 'Google Play';
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('pro_page');
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() {
      _errorMessage = null;
      _statusMessage = null;
    });

    if (!isRevenueCatConfigured) {
      try {
        await initializeRevenueCat();
      } catch (_) {
        // The actionable initialization error is shown below.
      }
    }

    if (!isRevenueCatConfigured) {
      if (!mounted) return;
      setState(() {
        final detail = revenueCatInitializationError;
        _errorMessage =
            detail == null ? '目前為訂閱畫面預覽，尚未連接商店方案。' : '商店連線初始化失敗：$detail';
      });
      return;
    }

    try {
      final offerings = await Purchases.getOfferings();
      if (!mounted) return;
      setState(() {
        _offering = offerings.current;
      });

      if (_offering == null) {
        setState(() {
          _errorMessage = '目前找不到可用訂閱方案。請到 RevenueCat 檢查 Offering / Package 設定。';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '載入訂閱方案失敗：$e';
      });
    }
  }

  Future<void> _buyPackage(Package package) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final purchaseResult = await Purchases.purchase(
        PurchaseParams.package(package),
      );
      final isActive = purchaseResult.customerInfo.entitlements
              .all[kRevenueCatEntitlementId]?.isActive ??
          false;

      if (!mounted) return;
      await context.read<ProProvider>().refreshFromRevenueCat();

      if (!mounted) return;

      if (isActive) {
        setState(() {
          _statusMessage = '升級成功！歡迎加入 Pro 會員';
        });
      } else {
        setState(() {
          _errorMessage =
              '購買已完成，但未拿到 premium entitlement，請檢查 RevenueCat entitlement id。';
        });
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        setState(() {
          _statusMessage = '已取消購買';
        });
      } else {
        setState(() {
          _errorMessage = '購買失敗：${e.message ?? e.code}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '購買失敗：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _restorePurchase() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      await Purchases.restorePurchases();
      if (!mounted) return;
      await context.read<ProProvider>().refreshFromRevenueCat();
      if (!mounted) return;

      setState(() {
        _statusMessage = '已送出恢復購買，若有有效訂閱會自動解鎖。';
      });
    } catch (e) {
      setState(() {
        _errorMessage = '恢復購買失敗：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final proProvider = context.watch<ProProvider>();
    final packages = _offering?.availablePackages ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('升級至心域 Pro'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber[300]!, Colors.amber[600]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Pro 會員版本',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  '解鎖心域 AI，協助整理與回顧你授權的紀錄。',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '功能對比',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _buildFeatureComparison(
            context,
            Icons.chat_bubble_outline_rounded,
            '心域 AI 對話',
            free: '無法使用',
            pro: '可使用',
          ),
          _buildFeatureComparison(
            context,
            Icons.auto_graph_rounded,
            '近期紀錄回顧',
            free: '自行查看紀錄',
            pro: 'AI 協助整理脈絡',
          ),
          _buildFeatureComparison(
            context,
            Icons.edit_note_rounded,
            '每日紀錄整理',
            free: '手動輸入',
            pro: 'AI 協助建立草稿',
          ),
          _buildFeatureComparison(
            context,
            Icons.medical_information_outlined,
            '回診專區 Beta',
            free: '免費使用',
            pro: '免費使用',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '重要提醒：心域 AI 僅提供自我覺察與紀錄整理輔助，可能產生不完整或不正確的內容。它不能診斷疾病、判定病因、調整藥物，也不取代醫師、心理師或其他專業人員的評估與治療。',
              style: TextStyle(fontSize: 13, height: 1.55),
            ),
          ),
          const SizedBox(height: 20),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: Colors.red[200]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            ),
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green[200]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(color: Colors.green[800]),
                ),
              ),
            ),
          if (packages.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _loadOfferings,
                child: const Text('重新載入訂閱方案'),
              ),
            ),
          for (final package in packages)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton(
                onPressed: (proProvider.isPro || _isLoading)
                    ? null
                    : () => _buyPackage(package),
                child: Text(
                  proProvider.isPro
                      ? '已解鎖 Pro（無需再次購買）'
                      : '透過 $_storeName 訂閱：${package.storeProduct.title} - ${package.storeProduct.priceString}',
                ),
              ),
            ),
          OutlinedButton(
            onPressed: _isLoading ? null : _restorePurchase,
            child: const Text('恢復購買'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('先不用，返回'),
          ),
          const SizedBox(height: 20),
          Text(
            '提示\n• 完成購買後可立即使用心域 AI\n• 訂閱會依商店顯示的週期自動續訂，除非你在目前週期結束前取消\n• 可在 $_storeName 帳戶設定中管理或取消訂閱\n• 回診專區 Beta 目前免費；回診摘要仍在開發中，未列入本次付費權益',
            style:
                const TextStyle(color: Colors.grey, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureComparison(
    BuildContext context,
    IconData icon,
    String title, {
    required String free,
    required String pro,
  }) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '免費版',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(free, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pro 版',
                        style: TextStyle(fontSize: 12, color: Colors.amber),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pro,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
