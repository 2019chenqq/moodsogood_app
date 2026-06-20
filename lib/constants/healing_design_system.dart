import 'package:flutter/material.dart';

/// 療癒系設計系統 - 統一配色、間距、陰影、邊框等所有視覺元素
/// 用於: 藥物時間線、每日紀錄、情緒、症狀、睡眠等所有主要UI頁面
class HealingDesignSystem {
  static const String fontFamily = 'Iansui';

  // ========================================
  // 🎨 色彩系統
  // ========================================

  /// 主藍色 - 品牌主色，用於重要元素、按鈕、焦點
  static const Color primaryBlue = Color(0xFF7DB7D8);

  /// 淺藍色背景 - 頁面背景、卡片背景、柔和區域
  static const Color softBlue = Color(0xFFEAF6FC);

  /// 卡片背景 - 純白/微藍，用於信息卡片
  static const Color cardBg = Color(0xFFFBFEFF);

  /// 時間軸線色 - 用於線條、分隔線
  static const Color lineColor = Color(0xFFD6EAF4);

  /// 深色文字 - 主要文字、標題
  static const Color deepText = Color(0xFF2F4858);

  /// 淡灰文字 - 輔助文字、說明
  static const Color mutedText = Color(0xFF7B8B96);

  /// 成功綠 - 用於完成、積極反饋
  static const Color successGreen = Color(0xFF4CAF50);

  /// 警示橙 - 用於提醒、需要注意
  static const Color warningOrange = Color(0xFFFFA726);

  /// 危險紅 - 用於停用、風險提示
  static const Color dangerRed = Color(0xFFEF5350);

  /// 淺紫色 - 用於情緒相關強調
  static const Color accentPurple = Color(0xFFC5A3D8);

  // ========================================
  // 📐 間距系統
  // ========================================

  static const double paddingXS = 4;
  static const double paddingS = 8;
  static const double paddingM = 12;
  static const double paddingL = 16;
  static const double paddingXL = 20;
  static const double paddingXXL = 24;

  /// 時間軸軸線寬度（左側）
  static const double timelineAxisWidth = 34;

  // ========================================
  // 🔲 邊角系統
  // ========================================

  /// 小邊角 - 小元件、Chip 等
  static const double radiusS = 8;

  /// 中邊角 - 按鈕、小卡片
  static const double radiusM = 12;

  /// 大邊角 - 主卡片（時間線、紀錄卡）
  static const double radiusL = 24;

  // ========================================
  // 👥 陰影系統
  // ========================================

  /// 輕陰影 - 用於卡片、浮起元素
  static BoxShadow shadowLight(
      {Color? color, double blurRadius = 12, double spreadRadius = 0}) {
    return BoxShadow(
      color: (color ?? primaryBlue).withOpacity(0.08),
      blurRadius: blurRadius,
      spreadRadius: spreadRadius,
    );
  }

  /// 標準陰影 - 用於主要卡片、彈窗
  static BoxShadow shadowMedium(
      {Color? color, double blurRadius = 18, double spreadRadius = 0}) {
    return BoxShadow(
      color: (color ?? primaryBlue).withOpacity(0.10),
      blurRadius: blurRadius,
      spreadRadius: spreadRadius,
    );
  }

  /// 深陰影 - 用於浮動按鈕、重要浮層
  static BoxShadow shadowHeavy(
      {Color? color, double blurRadius = 24, double spreadRadius = 2}) {
    return BoxShadow(
      color: (color ?? primaryBlue).withOpacity(0.15),
      blurRadius: blurRadius,
      spreadRadius: spreadRadius,
    );
  }

  // ========================================
  // 📦 預設裝飾
  // ========================================

  /// 標準卡片裝飾 - 用於時間線卡片、紀錄卡片
  static BoxDecoration cardDecoration({
    Color? bgColor,
    Color? shadowColor,
    double? radius,
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      color: bgColor ?? cardBg,
      borderRadius: BorderRadius.circular(radius ?? radiusL),
      boxShadow: shadows ?? [shadowMedium(color: shadowColor)],
    );
  }

  /// 時間軸軸線裝飾
  static BoxDecoration timelineAxisDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? softBlue.withOpacity(0.5),
      border: Border(
        left: BorderSide(
          color: lineColor,
          width: 2,
        ),
      ),
    );
  }

  // ========================================
  // 🎯 節點圓圈（時間軸圓形節點）
  // ========================================

  /// 時間軸節點直徑
  static const double timelineNodeDiameter = 12;

  /// 時間軸節點裝飾
  static BoxDecoration timelineNodeDecoration({
    Color? color,
    bool isActive = true,
  }) {
    return BoxDecoration(
      shape: BoxShape.circle,
      color: isActive ? (color ?? primaryBlue) : mutedText.withOpacity(0.3),
      boxShadow: [
        BoxShadow(
          color: (color ?? primaryBlue).withOpacity(isActive ? 0.3 : 0),
          blurRadius: 8,
          spreadRadius: 2,
        ),
      ],
    );
  }

  // ========================================
  // 🌈 漸層預設
  // ========================================

  /// 淺藍漸層背景 - 用於頁面背景、柔和區域
  static LinearGradient softBlueGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        softBlue,
        softBlue.withOpacity(0.8),
      ],
    );
  }

  /// 主題漸層 - 用於突出元素、按鈕
  static LinearGradient primaryGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        primaryBlue,
        primaryBlue.withOpacity(0.8),
      ],
    );
  }

  // ========================================
  // ⏱️ 動畫時間常量
  // ========================================

  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // ========================================
  // 📝 文字風格預設
  // ========================================

  /// 標題樣式 - 大標題（如頁面主標題）
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: deepText,
    height: 1.2,
  );

  /// 標題樣式 - 中標題（如卡片標題）
  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: deepText,
    height: 1.3,
  );

  /// 標題樣式 - 小標題（如分類標題）
  static const TextStyle titleSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: deepText,
    height: 1.4,
  );

  /// 本文樣式 - 大（主要內容）
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: deepText,
    height: 1.5,
  );

  /// 本文樣式 - 中（次要內容）
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: deepText,
    height: 1.5,
  );

  /// 本文樣式 - 小（輔助文字）
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: mutedText,
    height: 1.4,
  );

  /// 標籤樣式（Chip、Badge）
  static const TextStyle labelMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: deepText,
    height: 1.3,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: mutedText,
    height: 1.2,
  );

// ========================================
// 🌓 主題自適應工具
// ========================================

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color adaptiveBackground(BuildContext context) {
    return isDark(context) ? const Color(0xFF0F1720) : softBlue;
  }

  static Color adaptiveAppBarBackground(BuildContext context) {
    return isDark(context) ? const Color(0xFF16222D) : primaryBlue;
  }

  static Color adaptiveAppBarForeground(BuildContext context) {
    return isDark(context) ? const Color(0xFFF4FAFF) : Colors.white;
  }

  static Color adaptiveSurface(BuildContext context) {
    return isDark(context) ? const Color(0xFF1A2632) : cardBg;
  }

  static Color adaptiveCardBorder(BuildContext context) {
    return isDark(context)
        ? const Color(0xFF324657)
        : lineColor.withOpacity(0.8);
  }

  static Color adaptiveAccent(BuildContext context) {
    return isDark(context) ? const Color(0xFF8FC7E6) : primaryBlue;
  }

  static Color adaptivePrimaryText(BuildContext context) {
    return isDark(context) ? const Color(0xFFF2F7FA) : deepText;
  }

  static Color adaptiveSecondaryText(BuildContext context) {
    return isDark(context) ? const Color(0xFFB8C7D3) : mutedText;
  }

  static Color adaptiveMutedText(BuildContext context) {
    return isDark(context) ? const Color(0xFF93A4B2) : mutedText;
  }

  static Color adaptiveFill(BuildContext context) {
    return isDark(context)
        ? const Color(0xFF243443)
        : softBlue.withOpacity(0.35);
  }

  static BoxDecoration adaptiveCardDecoration(
    BuildContext context, {
    Color? bgColor,
    Color? shadowColor,
    double? radius,
    List<BoxShadow>? shadows,
  }) {
    final dark = isDark(context);

    return BoxDecoration(
      color: bgColor ?? adaptiveSurface(context),
      borderRadius: BorderRadius.circular(radius ?? radiusL),
      border: Border.all(
        color: adaptiveCardBorder(context),
        width: dark ? 1.1 : 1,
      ),
      boxShadow: dark
          ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ]
          : shadows ?? [shadowMedium(color: shadowColor)],
    );
  }

  // Additional methods or classes can be added here if needed.
}
