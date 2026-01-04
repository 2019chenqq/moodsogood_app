import 'package:flutter/material.dart';
import '../service/iap_service.dart';

class UpgradePage extends StatefulWidget {
  const UpgradePage({super.key});

  @override
  State<UpgradePage> createState() => _UpgradePageState();
}

class _UpgradePageState extends State<UpgradePage> {
  @override
  Widget build(BuildContext context) {
    final products = IAPService.instance.products;

    Widget content;
    if (products.isEmpty) {
      // 商品還沒載入好
      content = const Center(
        child: Text('商品載入中，請稍候…'),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '解鎖心晴 Pro 功能',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            '· 30 / 90 天趨勢圖\n'
            '· 匯出 PDF 報表\n'
            '· 更多主題與插畫\n',
          ),
          const SizedBox(height: 24),
          for (var p in products)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton(
                onPressed: () => IAPService.instance.buy(p),
                child: Text('購買：${p.title} - ${p.price}'),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('升級至心晴 Pro'),
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
