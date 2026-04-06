import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../service/iap_service.dart';
import '../providers/pro_provider.dart';

class UpgradePage extends StatefulWidget {
  const UpgradePage({super.key});

  @override
  State<UpgradePage> createState() => _UpgradePageState();
}

class _UpgradePageState extends State<UpgradePage> {
  bool _working = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _prepareProducts();
  }

  Future<void> _prepareProducts() async {
    try {
      await IAPService.instance.init();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = '商品初始化失敗：$e';
      });
    }
  }

  Future<void> _buyProduct() async {
    final proProduct = IAPService.instance.products
        .where((p) => p.id == IAPService.proMonthlyProductId)
        .toList();

    if (proProduct.isEmpty) {
      setState(() {
        _statusMessage = '找不到 Pro 訂閱商品，請確認 App Store Connect 產品 ID。';
      });
      return;
    }

    setState(() {
      _working = true;
      _statusMessage = null;
    });

    try {
      await IAPService.instance.buy(proProduct.first);
      if (!mounted) return;
      setState(() {
        _statusMessage = '已開啟購買流程，請在商店完成付款。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = '購買失敗：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() {
      _working = true;
      _statusMessage = null;
    });

    try {
      await IAPService.instance.restorePurchases();
      await context.read<ProProvider>().refreshFromServer();
      if (!mounted) return;
      setState(() {
        _statusMessage = '已送出恢復購買，若有有效訂閱會自動解鎖。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = '恢復購買失敗：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final proProvider = context.watch<ProProvider>();
    final proProducts = IAPService.instance.products
        .where((p) => p.id == IAPService.proMonthlyProductId)
        .toList();

    Widget content;
    if (proProducts.isEmpty) {
      // 商品還沒載入好
      content = const Center(
        child: Text('Pro 訂閱商品載入中，請稍候…'),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '解鎖心域 Pro 功能',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            '· 30 / 90 天趨勢圖\n'
            '· 匯出 PDF 報表\n'
            '· 更多主題與插畫\n',
          ),
          const SizedBox(height: 24),
          if (proProvider.isPro)
            const Text(
              '你目前已是 Pro 會員。',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ElevatedButton(
              onPressed: (_working || proProvider.isPro) ? null : _buyProduct,
              child: Text(
                proProvider.isPro
                    ? '已啟用 Pro（無需再次購買）'
                    : '訂閱：${proProducts.first.title} - ${proProducts.first.price}',
              ),
            ),
          ),
          OutlinedButton(
            onPressed: _working ? null : _restorePurchases,
            child: const Text('恢復購買'),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _statusMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('升級至心域 Pro'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      ),
    );
  }
}
