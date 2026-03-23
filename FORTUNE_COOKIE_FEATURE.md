# 🥠 幸運餅乾與籤詩功能

## 功能概述

將原本的心情小語改成互動式的「幸運餅乾」體驗：
- 每次打開 APP 時，頁面頂部自動顯示一個幸運餅乾動畫
- 用戶點擊幸運餅乾後，会展開展示一張籤詩
- 籤詩上隨機展示 quotes 中的勵志小語
- 用戶可以點擊「再試一次」按鈕來重新獲得新的籤詩

## 文件結構

### 新增檔案
- **[lib/widgets/fortune_cookie_widget.dart](lib/widgets/fortune_cookie_widget.dart)**
  - 主要 Widget，包含幸運餅乾的動畫和籤詩卡片
  - `FortuneCookieWidget`: 主容器，管理動畫狀態
  - `FortuneFaceCard`: 籤詩卡片展示組件

### 修改檔案
- **[lib/quotes.dart](lib/quotes.dart)**
  - 新增 `getRandomQuote()` 函數用於隨機選擇籤詩
  - 保留原有的 `_pickQuoteForToday()` 函數以供其他頁面使用

- **[lib/daily/daily_record_screen.dart](lib/daily/daily_record_screen.dart)**
  - 將 `title: const QuotesTitle()` 改為 `title: const FortuneCookieWidget()`
  - 將 `toolbarHeight: 120` 改為 `toolbarHeight: 200` 以容納更大的餅乾動畫

- **[lib/daily/daily_record_history.dart](lib/daily/daily_record_history.dart)**
  - 同上，替換為 FortuneCookieWidget

- **[lib/diary/diary_home_page.dart](lib/diary/diary_home_page.dart)**
  - 同上，替換為 FortuneCookieWidget

## 使用的圖文件

位置: `assets/UI/`
- `幸運餅乾.png` - 靜態餅乾圖像（150x150px）
- `幸運餅乾動畫.mp4` - 動畫參考（當前實作使用 Dart 動畫）

## 動畫效果

### 1. 餅乾進入動畫
- **類型**: ScaleTransition
- **曲線**: elasticOut（彈跳效果）
- **時長**: 600ms
- **效果**: 餅乾從 0 放大到正常大小，帶有彈跳感

### 2. 籤詩展開動畫
- **旋轉**: -0.5 轉到 0（展開效果）
- **滑動**: 從下方滑動到中心
- **時長**: 800ms
- **曲線**: easeOut

## 籤詩卡片設計

使用橙黃色漸變背景，帶有：
- 标題: "✨ 籤詩 ✨"
- 居中顯示的勵志文字
- 「再試一次」按鈕用於重新抽籤

## 核心功能代碼

### 獲取隨機籤詩
```dart
/// quotes.dart 中的新函數
String getRandomQuote() {
  final random = Random();
  final index = random.nextInt(_quotes.length);
  return _quotes[index];
}
```

### 點擊幸運餅乾
```dart
void _handleCookieClick() {
  if (_cookieClicked) return;

  setState(() {
    _cookieClicked = true;
    _selectedQuote = getRandomQuote();
  });

  // 播放籤展開動畫
  _fortuneController.forward();
}
```

### 重新開始
```dart
void _resetCookie() {
  setState(() {
    _cookieClicked = false;
    _selectedQuote = null;
  });
  _cookieController.reset();
  _fortuneController.reset();
  _cookieController.forward();
}
```

## 使用情境

該功能已集成到以下三個主要頁面：
1. 📊 **每日記錄頁** (DailyRecordScreen) - 首頁
2. 📈 **統計頁面** (DailyRecordHistory) - 查看趨勢
3. 📓 **日記頁面** (DiaryHomePage) - 日記

## 未來改進建議

- [ ] 集成 `幸運餅乾動畫.mp4` 影片動畫（使用 video_player 套件）
- [ ] 添加聲音效果（點擊音、展開音）
- [ ] 保存用戶已經看過的籤詩，避免重複
- [ ] 添加分享籤詩功能
- [ ] 根據時間動態選擇籤詩（每日不同的籤）
- [ ] 添加籤詩搖晃和翻轉動畫
