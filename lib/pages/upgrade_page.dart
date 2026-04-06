import 'package:flutter/material.dart';

/// 保留舊入口，避免舊路由失效。
class UpgradePage extends StatelessWidget {
  const UpgradePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('訂閱頁面')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Pro 頁面目前已暫時下架。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
