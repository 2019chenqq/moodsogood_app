import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'test_data_generator.dart';
import '../constants/healing_design_system.dart';
import '../daily/daily_record_history.dart';

/// ============================================================
/// 測試資料管理頁面
/// 只在 debug 模式顯示入口，正式 release 版不可見。
/// ============================================================
class TestDataManagementPage extends StatefulWidget {
  const TestDataManagementPage({super.key});

  @override
  State<TestDataManagementPage> createState() => _TestDataManagementPageState();
}

class _TestDataManagementPageState extends State<TestDataManagementPage> {
  bool _isLoading = false;
  bool _hasTestData = false;
  String _statusText = '';
  double _progress = 0.0;
  bool _showProgress = false;
  Map<String, dynamic>? _stats;
  int _selectedTotalDays = 365;

  String get _selectedRangeLabel {
    switch (_selectedTotalDays) {
      case 120:
        return '120 天';
      case 180:
        return '半年';
      case 365:
        return '一年';
      default:
        return '$_selectedTotalDays 天';
    }
  }

  @override
  void initState() {
    super.initState();
    _checkTestData();
  }

  Future<void> _checkTestData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _isLoading = true;
      _statusText = '檢查中...';
    });

    try {
      final hasData = await TestDataGenerator.hasTestData(userId: uid);
      if (hasData) {
        _stats = await TestDataGenerator.getTestDataStats(userId: uid);
      }
      if (mounted) {
        setState(() {
          _hasTestData = hasData;
          _isLoading = false;
          _statusText =
              hasData ? '✅ 已有 ${_stats?['count'] ?? '?'} 筆測試資料' : '目前無測試資料';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = '檢查失敗：$e';
        });
      }
    }
  }

  Future<void> _generateTestData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnackBar('請先登入');
      return;
    }

    // 二次確認
    final confirmed = await _showConfirmDialog(
      title: '產生測試情緒資料',
      message: '這將在您的帳號中產生最近 $_selectedRangeLabel 的測試情緒資料。\n\n'
          '包含：\n'
          '• 6 種正向感受、8 種負向感受\n'
          '• 穩定期、壓力上升期、低落期、恢復期、高能量期\n'
          '• 5 分制與 10 分制相容\n'
          '• 故意保留缺漏日\n'
          '• 極少量自殺意念（僅 2 筆）\n\n'
          '⚠️ 遇到既有真實紀錄的日期會自動跳過，不會覆蓋\n'
          '⚠️ 新測試資料會標記為 isDevSeedOwned = true\n'
          '⚠️ 此操作不可復原，但可透過「刪除測試資料」移除',
      confirmText: '確認產生',
      isDangerous: false,
    );
    if (confirmed != true) return;

    // 再次確認
    final confirmed2 = await _showConfirmDialog(
      title: '再次確認',
      message: '請確認您了解：\n'
          '1. 這是測試資料，不是真實情緒紀錄\n'
          '2. 產生後可在設定頁刪除\n'
          '3. 正式版不會顯示此功能',
      confirmText: '我了解，開始產生',
      isDangerous: false,
    );
    if (confirmed2 != true) return;

    setState(() {
      _isLoading = true;
      _showProgress = true;
      _progress = 0.0;
      _statusText = '正在產生測試資料...';
    });

    try {
      final count = await TestDataGenerator.generateTestData(
        userId: uid,
        totalDays: _selectedTotalDays,
        progressCallback: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _statusText = '正在產生測試資料... ${(progress * 100).toInt()}%';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _showProgress = false;
          _hasTestData = true;
          _statusText = '✅ 成功產生 $_selectedRangeLabel、$count 筆測試資料！';
        });
        _stats = await TestDataGenerator.getTestDataStats(userId: uid);
        _showSnackBar('成功產生 $_selectedRangeLabel、$count 筆測試資料');
        // 自動導向圖表頁
        _navigateToChart();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showProgress = false;
          _statusText = '❌ 產生失敗：$e';
        });
        _showSnackBar('產生失敗：$e');
      }
    }
  }

  Future<void> _deleteTestData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnackBar('請先登入');
      return;
    }

    // 二次確認
    final confirmed = await _showConfirmDialog(
      title: '刪除測試資料',
      message: '確定要刪除所有測試資料嗎？\n\n'
          '只會刪除新版產生器標記為 isDevSeedOwned = true 的資料，\n'
          '不會影響您的真實紀錄。',
      confirmText: '確認刪除',
      isDangerous: true,
    );
    if (confirmed != true) return;

    // 再次確認
    final confirmed2 = await _showConfirmDialog(
      title: '再次確認刪除',
      message: '此操作無法復原。\n'
          '所有測試資料將被永久刪除。',
      confirmText: '確認永久刪除',
      isDangerous: true,
    );
    if (confirmed2 != true) return;

    setState(() {
      _isLoading = true;
      _showProgress = true;
      _progress = 0.0;
      _statusText = '正在刪除測試資料...';
    });

    try {
      final count = await TestDataGenerator.deleteTestData(
        userId: uid,
        progressCallback: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _statusText = '正在刪除測試資料... ${(progress * 100).toInt()}%';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _showProgress = false;
          _hasTestData = false;
          _stats = null;
          _statusText = '✅ 已刪除 $count 筆測試資料';
        });
        _showSnackBar('已刪除 $count 筆測試資料');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showProgress = false;
          _statusText = '❌ 刪除失敗：$e';
        });
        _showSnackBar('刪除失敗：$e');
      }
    }
  }

  Future<void> _regenerateTestData() async {
    // 先刪除再產生
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnackBar('請先登入');
      return;
    }

    final confirmed = await _showConfirmDialog(
      title: '重新產生測試資料',
      message: '這將先刪除現有測試資料，再重新產生一份新的。\n\n'
          '⚠️ 此操作無法復原',
      confirmText: '確認重新產生',
      isDangerous: true,
    );
    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _showProgress = true;
      _progress = 0.0;
      _statusText = '正在刪除舊資料...';
    });

    try {
      await TestDataGenerator.deleteTestData(userId: uid);

      if (mounted) {
        setState(() {
          _progress = 0.0;
          _statusText = '正在重新產生...';
        });
      }

      final count = await TestDataGenerator.generateTestData(
        userId: uid,
        totalDays: _selectedTotalDays,
        progressCallback: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _statusText = '正在重新產生測試資料... ${(progress * 100).toInt()}%';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _showProgress = false;
          _hasTestData = true;
          _statusText = '✅ 已重新產生 $_selectedRangeLabel、$count 筆測試資料';
        });
        _stats = await TestDataGenerator.getTestDataStats(userId: uid);
        _showSnackBar('已重新產生 $_selectedRangeLabel、$count 筆測試資料');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showProgress = false;
          _statusText = '❌ 重新產生失敗：$e';
        });
        _showSnackBar('重新產生失敗：$e');
      }
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required bool isDangerous,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HealingDesignSystem.adaptiveSurface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDangerous
                ? HealingDesignSystem.dangerRed
                : HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: HealingDesignSystem.adaptiveSecondaryText(context),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '取消',
              style: TextStyle(
                color: HealingDesignSystem.adaptiveSecondaryText(context),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDangerous
                  ? HealingDesignSystem.dangerRed
                  : HealingDesignSystem.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(HealingDesignSystem.radiusM),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: message.startsWith('❌')
            ? HealingDesignSystem.dangerRed
            : Colors.green,
      ),
    );
  }

  /// 導航到情緒趨勢圖頁（預設開啟第二分頁 = 趨勢圖）
  void _navigateToChart() {
    if (!mounted) return;
    // 使用 pushReplacement 避免按返回鍵回到測試頁
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DailyRecordHistory(initialTab: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        elevation: 0,
        title: Text(
          '測試資料管理',
          style: TextStyle(
            color: HealingDesignSystem.adaptiveAppBarForeground(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 開發者提示 ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(HealingDesignSystem.radiusL),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.developer_mode, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔧 開發者工具',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.orange[800],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '此功能僅在 Debug 模式可用，\n正式 Release 版不會顯示。',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 狀態卡片 ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: HealingDesignSystem.adaptiveCardDecoration(
                context,
                bgColor: HealingDesignSystem.adaptiveSurface(context),
                radius: HealingDesignSystem.radiusL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '資料狀態',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isLoading && !_showProgress)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    Text(
                      _statusText,
                      style: TextStyle(
                        color: _statusText.startsWith('✅')
                            ? Colors.green
                            : _statusText.startsWith('❌')
                                ? HealingDesignSystem.dangerRed
                                : HealingDesignSystem.adaptiveSecondaryText(
                                    context),
                      ),
                    ),
                    if (_showProgress) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _progress,
                        backgroundColor:
                            HealingDesignSystem.adaptiveFill(context),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          HealingDesignSystem.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: HealingDesignSystem.adaptiveSecondaryText(
                              context),
                        ),
                      ),
                    ],
                    if (_stats != null) ...[
                      const SizedBox(height: 12),
                      _buildStatRow('資料筆數', '${_stats!['count']}'),
                      if (_stats!['earliest'] != null)
                        _buildStatRow(
                          '最早日期',
                          '${(_stats!['earliest'] as DateTime).year}/'
                              '${(_stats!['earliest'] as DateTime).month.toString().padLeft(2, '0')}/'
                              '${(_stats!['earliest'] as DateTime).day.toString().padLeft(2, '0')}',
                        ),
                      if (_stats!['latest'] != null)
                        _buildStatRow(
                          '最晚日期',
                          '${(_stats!['latest'] as DateTime).year}/'
                              '${(_stats!['latest'] as DateTime).month.toString().padLeft(2, '0')}/'
                              '${(_stats!['latest'] as DateTime).day.toString().padLeft(2, '0')}',
                        ),
                      _buildStatRow('量表範圍', '${_stats!['scaleRange']}'),
                    ],
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 操作按鈕 ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: HealingDesignSystem.adaptiveCardDecoration(
                context,
                bgColor: HealingDesignSystem.adaptiveSurface(context),
                radius: HealingDesignSystem.radiusL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '產生範圍',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildRangeChip(120, '120 天'),
                      _buildRangeChip(180, '半年'),
                      _buildRangeChip(365, '一年'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '情境比例會依選擇範圍拉長，趨勢資料仍走正式每日紀錄儲存流程。',
                    style: TextStyle(
                      fontSize: 12,
                      color: HealingDesignSystem.adaptiveSecondaryText(context),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _buildActionButton(
              icon: Icons.add_chart,
              label: '產生最近 $_selectedRangeLabel 測試資料',
              subtitle: '包含 6 種情境、5/10 分制、缺漏日',
              color: HealingDesignSystem.primaryBlue,
              onTap: _isLoading ? null : _generateTestData,
            ),

            const SizedBox(height: 12),

            _buildActionButton(
              icon: Icons.delete_sweep,
              label: '刪除測試資料',
              subtitle: '只刪除 isDevSeedOwned = true 的資料',
              color: HealingDesignSystem.dangerRed,
              onTap: (_isLoading || !_hasTestData) ? null : _deleteTestData,
            ),

            const SizedBox(height: 12),

            _buildActionButton(
              icon: Icons.refresh,
              label: '重新產生測試資料',
              subtitle: '先刪除舊資料，再產生新資料',
              color: Colors.orange,
              onTap: _isLoading ? null : _regenerateTestData,
            ),

            // ── 前往檢視圖表（有測試資料才顯示）──
            if (_hasTestData) ...[
              const SizedBox(height: 12),
              _buildActionButton(
                icon: Icons.bar_chart,
                label: '前往檢視情緒趨勢圖',
                subtitle: '查看測試資料的圖表呈現',
                color: Colors.teal,
                onTap: _navigateToChart,
              ),
            ],

            const SizedBox(height: 24),

            // ── 情境說明 ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: HealingDesignSystem.adaptiveCardDecoration(
                context,
                bgColor: HealingDesignSystem.adaptiveSurface(context),
                radius: HealingDesignSystem.radiusL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📋 產生的測試情境',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildScenarioItem(
                    '穩定期',
                    '正向 3~4 分，負向 1~2 分',
                    Icons.sentiment_satisfied,
                  ),
                  _buildScenarioItem(
                    '壓力上升期',
                    '負向從 2 分逐漸上升到 4~5 分',
                    Icons.trending_up,
                  ),
                  _buildScenarioItem(
                    '低落期',
                    '低落、疲憊、空虛、無助較多，正向很少',
                    Icons.cloud,
                  ),
                  _buildScenarioItem(
                    '恢復期',
                    '負向下降，正向逐漸回升',
                    Icons.trending_up,
                  ),
                  _buildScenarioItem(
                    '高能量正向期',
                    '快樂、興奮、有希望高分',
                    Icons.whatshot,
                  ),
                  _buildScenarioItem(
                    '10 點量表舊資料',
                    '較舊日期使用 10 點量表格式',
                    Icons.history,
                  ),
                  const Divider(height: 24),
                  Text(
                    '⚠️ 危險警訊測試',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: HealingDesignSystem.dangerRed,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '依選擇範圍加入極少量自殺意念資料，\n'
                    '不會造成進入歷史頁就一直彈窗。',
                    style: TextStyle(
                      fontSize: 12,
                      color: HealingDesignSystem.adaptiveSecondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeChip(int days, String label) {
    final selected = _selectedTotalDays == days;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected:
          _isLoading ? null : (_) => setState(() => _selectedTotalDays = days),
      selectedColor: HealingDesignSystem.primaryBlue.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        color: selected
            ? HealingDesignSystem.primaryBlue
            : HealingDesignSystem.adaptivePrimaryText(context),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected
            ? HealingDesignSystem.primaryBlue
            : HealingDesignSystem.adaptiveCardBorder(context),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: HealingDesignSystem.adaptivePrimaryText(context),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1.0,
      child: Container(
        decoration: HealingDesignSystem.adaptiveCardDecoration(
          context,
          bgColor: HealingDesignSystem.adaptiveSurface(context),
          radius: HealingDesignSystem.radiusL,
        ),
        child: ListTile(
          leading: Icon(icon, color: color, size: 28),
          title: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: HealingDesignSystem.adaptivePrimaryText(context),
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: HealingDesignSystem.adaptiveSecondaryText(context),
            ),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: color,
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildScenarioItem(String title, String description, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: HealingDesignSystem.primaryBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                    fontSize: 13,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
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
