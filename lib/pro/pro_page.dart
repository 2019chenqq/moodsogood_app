import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/pro_provider.dart';
import '../service/iap_service.dart';

class ProPage extends StatefulWidget {
  const ProPage({super.key});

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late Stream<List<PurchaseDetails>> _purchaseStream;
  bool _isLoading = false;
  bool _debugForceLocked = false;
  String? _errorMessage;

  // 與 IAPService 保持一致，iOS/Android 都使用同一個商品 ID 字串。
  static const String _productId = IAPService.proMonthlyProductId;

  String get _storeName {
    return defaultTargetPlatform == TargetPlatform.iOS
        ? 'App Store'
        : 'Google Play';
  }

  @override
  void initState() {
    super.initState();
    _purchaseStream = _inAppPurchase.purchaseStream;
    _setupPurchaseListener();
  }

  void _setupPurchaseListener() {
    _purchaseStream.listen(
      (List<PurchaseDetails> purchaseDetailsList) {
        _handlePurchase(purchaseDetailsList);
      },
      onError: (error) {
        setState(() => _errorMessage = '購買出錯：$error');
      },
    );
  }

  Future<void> _handlePurchase(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchase in purchaseDetailsList) {
      if (purchase.status == PurchaseStatus.purchased) {
        // 驗證並完成購買
        await _verifyAndProcessPurchase(purchase);
        // 標記購買已完成
        if (purchase.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchase);
        }
      } else if (purchase.status == PurchaseStatus.error) {
        setState(() => _errorMessage = '購買失敗');
      }
    }
  }

  Future<void> _verifyAndProcessPurchase(PurchaseDetails purchase) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _errorMessage = '未登入，無法完成購買');
        return;
      }

      // 保存購買信息到 Firebase
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isPro': true,
        'proStartDate': DateTime.now(),
        'purchaseId': purchase.purchaseID,
        'purchaseVerificationData': purchase.verificationData.serverVerificationData,
      });

      // 更新本地 Pro 狀態
      if (mounted) {
        final proProvider = context.read<ProProvider>();
        // 使用 debugUnlock 來設置 Pro 狀態
        await proProvider.debugUnlock();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('升級成功！歡迎加入 Pro 會員')),
              ],
            ),
          ),
        );

        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() => _errorMessage = '驗證購買失敗：$e');
    }
  }

  Future<void> _buyPro() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _errorMessage = '請先登入');
        return;
      }

      // 確認產品可用
      final response = await _inAppPurchase.queryProductDetails({_productId});
      if (response.notFoundIDs.contains(_productId)) {
        setState(() => _errorMessage = '產品不可用，請稍後重試');
        return;
      }

      // 購買
      final productDetails = response.productDetails.first;
      await _inAppPurchase.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: productDetails),
      );
    } catch (e) {
      setState(() => _errorMessage = '購買失敗：$e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final proProvider = context.watch<ProProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('升級至心域 Pro'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Pro 會員狀態卡片
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
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
                const SizedBox(height: 12),
                const Text(
                  '升級到 Pro 以解鎖所有功能。',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 功能對比
          const Text(
            '功能對比',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          _buildFeatureComparison(
            context,
            Icons.cloud,
            '資料存儲',
            free: '本地存儲',
            pro: 'Firebase 雲端',
          ),
          _buildFeatureComparison(
            context,
            Icons.calendar_today,
            '資料保留期',
            free: '最近 2 年',
            pro: '永久保存',
          ),
          _buildFeatureComparison(
            context,
            Icons.sync_alt,
            '多設備同步',
            free: '不支持',
            pro: '支持',
          ),
          _buildFeatureComparison(
            context,
            Icons.bar_chart,
            '查看歷程',
            free: '最近 30 天',
            pro: '全部歷程',
          ),
          _buildFeatureComparison(
            context,
            Icons.trending_up,
            '情緒趨勢圖',
            free: '最近 30 天',
            pro: '全部趨勢',
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

          FilledButton(
            onPressed: (proProvider.isPro || _isLoading) ? null : _buyPro,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    proProvider.isPro
                        ? '已解鎖 Pro（無需再次購買）'
                        : '透過 $_storeName 購買',
                  ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('先不用，返回'),
          ),

          const SizedBox(height: 20),
          Text(
            '提示\n• 首次購買後可立即使用所有 Pro 功能\n• 可在 $_storeName 帳戶設定中管理訂閱\n• 取消訂閱後，您仍可使用已同步到雲端的數據',
            style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.6),
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
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
                      Text(pro, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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
