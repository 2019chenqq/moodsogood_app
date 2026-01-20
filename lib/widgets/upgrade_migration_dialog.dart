import 'package:flutter/material.dart';

/// 升級進度顯示 Dialog
class UpgradeMigrationDialog extends StatelessWidget {
  final bool isComplete;
  final bool success;
  final String message;
  final int recordsCount;

  const UpgradeMigrationDialog({
    super.key,
    this.isComplete = false,
    this.success = true,
    this.message = '正在遷移數據...',
    this.recordsCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: isComplete,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 圖標
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: success ? Colors.green[100] : Colors.orange[100],
                ),
                child: Center(
                  child: isComplete
                      ? Icon(
                          success ? Icons.check_circle : Icons.warning,
                          size: 48,
                          color: success ? Colors.green : Colors.orange,
                        )
                      : SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.amber[600]!,
                            ),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // 標題
              Text(
                isComplete
                    ? (success ? '升級成功！' : '升級完成')
                    : '正在升級...',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // 消息
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),

              // 記錄計數（如果有的話）
              if (recordsCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '已遷移 $recordsCount 條記錄',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // 按鈕
              if (isComplete)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('確認'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: null,
                    child: const Text('處理中...'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> show(
    BuildContext context, {
    required Future<MigrationResult> migrationFuture,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const UpgradeMigrationDialog(),
    );

    try {
      final result = await migrationFuture;

      if (!context.mounted) return;

      // 顯示結果
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => UpgradeMigrationDialog(
          isComplete: true,
          success: result.success,
          message: result.message,
          recordsCount: result.recordsCount,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => UpgradeMigrationDialog(
          isComplete: true,
          success: false,
          message: '遷移失敗：$e',
        ),
      );
    }
  }
}

/// 遷移結果（與 data_migration.dart 中的 MigrationResult 相同）
class MigrationResult {
  final bool success;
  final int recordsCount;
  final String message;

  MigrationResult({
    required this.success,
    required this.recordsCount,
    required this.message,
  });
}
