import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../utils/firebase_sync_config.dart';

class HealthStorageChoicePage extends StatefulWidget {
  const HealthStorageChoicePage({
    super.key,
    required this.onConfirm,
    this.initialMode,
    this.allowBack = false,
  });

  final HealthStorageMode? initialMode;
  final Future<void> Function(HealthStorageMode mode) onConfirm;
  final bool allowBack;

  @override
  State<HealthStorageChoicePage> createState() =>
      _HealthStorageChoicePageState();
}

class _HealthStorageChoicePageState extends State<HealthStorageChoicePage> {
  HealthStorageMode? _selectedMode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
  }

  Future<void> _confirm() async {
    final selected = _selectedMode;
    if (selected == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onConfirm(selected);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFD),
      appBar: AppBar(
        automaticallyImplyLeading: widget.allowBack,
        title: const Text('健康資料儲存方式'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const Icon(
              Icons.health_and_safety_outlined,
              size: 50,
              color: HealingDesignSystem.primaryBlue,
            ),
            const SizedBox(height: 14),
            const Text(
              '你希望健康資料存在哪裡？',
              textAlign: TextAlign.center,
              style: HealingDesignSystem.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              '這會影響換手機時能否恢復資料，以及資料是否會離開目前裝置。你之後仍可在設定中變更。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: HealingDesignSystem.mutedText,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),
            _StorageModeCard(
              key: const Key('local_storage_option'),
              selected: _selectedMode == HealthStorageMode.localOnly,
              icon: Icons.smartphone_rounded,
              title: '只存本機',
              subtitle: '健康資料只保留在目前裝置',
              points: const [
                '不會同步至 Firestore，也無法跨裝置查看',
                '換手機、刪除 App 或裝置損壞時，資料可能無法恢復',
                '未來可以改用加密雲端同步，再將本機資料加密上傳',
                '使用 AI 前會另外詢問，單次同意不會開啟雲端同步',
              ],
              onTap: () => setState(
                () => _selectedMode = HealthStorageMode.localOnly,
              ),
            ),
            const SizedBox(height: 14),
            _StorageModeCard(
              key: const Key('encrypted_cloud_option'),
              selected: _selectedMode == HealthStorageMode.encryptedCloudSync,
              icon: Icons.cloud_done_outlined,
              title: '加密雲端同步',
              subtitle: '在裝置端加密後，再將密文同步至雲端',
              points: const [
                '可在其他裝置透過 PIN 與復原金鑰恢復資料',
                '情緒、症狀、藥物及醫囑等內容不以明文上傳',
                '日期與同步時間等必要索引仍可能保留為查詢資訊',
                '之後可停止同步，並選擇是否刪除既有雲端密文',
              ],
              onTap: () => setState(
                () => _selectedMode = HealthStorageMode.encryptedCloudSync,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(HealingDesignSystem.radiusM),
                border: Border.all(color: HealingDesignSystem.lineColor),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: HealingDesignSystem.primaryBlue,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '兩種模式都會在裝置端加密健康內容。差別在於密文是否會同步至雲端，而不是資料是否受到保護。',
                      style: TextStyle(
                        color: HealingDesignSystem.deepText,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('confirm_storage_mode'),
              onPressed: _selectedMode == null || _saving ? null : _confirm,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: HealingDesignSystem.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(HealingDesignSystem.radiusM),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '確認儲存方式',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageModeCard extends StatelessWidget {
  const _StorageModeCard({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
        child: AnimatedContainer(
          duration: HealingDesignSystem.animationFast,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected
                ? HealingDesignSystem.softBlue
                : HealingDesignSystem.cardBg,
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
            border: Border.all(
              color: selected
                  ? HealingDesignSystem.primaryBlue
                  : HealingDesignSystem.lineColor,
              width: selected ? 2 : 1,
            ),
            boxShadow: [HealingDesignSystem.shadowLight()],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color: HealingDesignSystem.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: HealingDesignSystem.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: HealingDesignSystem.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected
                        ? HealingDesignSystem.primaryBlue
                        : HealingDesignSystem.mutedText,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final point in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 17,
                          color: HealingDesignSystem.primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          point,
                          style: const TextStyle(
                            color: HealingDesignSystem.deepText,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
