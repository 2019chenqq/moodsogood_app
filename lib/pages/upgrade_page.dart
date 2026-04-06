import 'package:flutter/material.dart';

import '../pro/pro_page.dart';

/// 保留舊入口，統一轉到 RevenueCat 版本的 ProPage。
class UpgradePage extends StatelessWidget {
  const UpgradePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProPage();
  }
}
