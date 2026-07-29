import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class AiEvaluationFileActionService {
  const AiEvaluationFileActionService._();

  static Future<void> shareFiles(
    BuildContext context,
    List<String> paths,
  ) async {
    final existing = <XFile>[];
    for (final path in paths) {
      if (await File(path).exists()) existing.add(XFile(path));
    }
    if (!context.mounted) return;
    if (existing.isEmpty) {
      _snack(context, '找不到可分享的 JSON 檔案');
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      existing,
      subject: '心域 AI 評測資料',
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  static Future<void> copyPath(BuildContext context, String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (context.mounted) _snack(context, '已複製路徑');
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
