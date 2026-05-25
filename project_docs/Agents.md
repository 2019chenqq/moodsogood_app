# 心晴 Heart Shine 專案規則

## 產品定位

心晴 Heart Shine 是一款情緒、日記、睡眠、症狀與藥物紀錄 App。

核心目標不是診斷，而是協助使用者把零散的主觀感受整理成可回顧、可溝通、可理解的紀錄。

請避免把功能寫得像醫療診斷工具。

## UI 風格

整體風格是：
- 療癒
- 柔和
- 乾淨
- 淺藍色系
- 卡片式 UI
- 圓角
- 適度留白

請優先使用：

```dart
HealingDesignSystem

# 心晴 Heart Shine 專案總整理

## 專案定位

心晴 Heart Shine（品牌：心域 Innera）是一款以心理健康、自我覺察與情緒整理為核心的 Flutter App。

產品目標：

* 協助使用者記錄情緒、日記、症狀、睡眠與藥物
* 將零散的主觀感受整理成可回顧、可理解的資料
* 提供溫柔、安全、非診斷性的 AI 陪伴與整理
* 建立療癒、低壓力的使用體驗

產品不是醫療診斷工具。

AI 不可：

* 診斷疾病
* 判斷病情嚴重度
* 推論不存在的資訊
* 把相關性說成因果

---

# 技術架構

## 技術堆疊

* Flutter
* Firebase

  * Auth
  * Firestore
  * Storage
  * Analytics（GA4）
* Provider
* fl_chart
* flutter_local_notifications
* image_picker
* Firebase Storage

---

# 專案核心功能

## 1. 每日紀錄

包含：

* 情緒
* 症狀
* 睡眠
* 整體情緒分數
* 整體健康分數
* 整體睡眠品質

功能：

* 可新增與刪除情緒
* 整體情緒不可刪除
* 歷程頁可編輯舊紀錄
* 支援趨勢圖

---

## 2. 日記功能

日記欄位：

* title
* content
* themeSong
* highlight
* metaphor
* conceited
* proudOf
* selfCare

日記目前支援：

* Firebase 儲存
* 加密
* AI 回饋
* 圖片上傳（開發中）

---

## 3. 日記圖片功能（新增）

目前規劃：

* 每篇日記最多 3 張圖片
* Firebase Storage 儲存
* Firestore 存 imageUrls
* 支援縮圖預覽
* 可刪除圖片
* 可點擊放大（未來）

圖片儲存路徑：

```text
users/{uid}/diary_images/{yyyy-MM-dd}/{timestamp}.jpg
```

Firestore 欄位：

```json
{
  "imageUrls": [
    "https://..."
  ]
}
```

目前已完成：

* image_picker
* Firebase Storage
* Android 權限
* iOS 權限
* 上傳 UI

待優化：

* 圖片放大檢視
* lazy loading
* 圖片排序
* 圖片壓縮

---

# AI 功能規則

## AI 兩種模式

### 基礎版 AI（免費）

定位：

* 陪伴
* 整理
* 溫柔回饋

只允許讀取：

* 今日日記文字
* 整體情緒分數
* 日期

不可讀取：

* 睡眠
* 症狀
* 藥物
* 長期趨勢
* recentRecords
* 回診資料

基礎版只顯示：

1. AI 今日摘要
2. AI 可能主題
3. AI 溫柔回饋
4. 今日小建議

不可顯示：

* AI 情緒觀察
* 情緒分數解讀
* 睡眠觀察
* 症狀觀察
* 藥物觀察
* 風險提示
* 長期趨勢

---

### 深入分析版 AI（Pro）

定位：

* 長期觀察
* 回顧分析
* 結構整理

可讀取：

* 日記
* 情緒
* 睡眠
* 症狀
* 藥物
* 近期紀錄
* 長期趨勢

但仍不可：

* 診斷
* 判斷疾病嚴重度
* 把相關性說成因果

深入版目前：

* 不開放完整 UX
* 只做 Pro 預告頁
* 用來測試點擊率與付費興趣

---

# AI Prompt 原則

AI 不可：

* 自行補充使用者沒寫的資訊
* 說「你可能睡不好」除非日記明確提到
* 說「藥物影響了你」除非有資料
* 生成心理診斷語氣

優先：

* 溫柔
* 陪伴
* 可理解
* 低推論

產品原則：

```text
可理解 > 看起來很 AI
```

---

# Pro 功能規劃

## 免費版

目前開放：

* 近 7 天
* 近 30 天
* 基礎 AI 回饋
* 基本情緒趨勢

---

## Pro 版

目前規劃：

* AI 深入分析
* 近 90 天
* 全部歷程
* 自訂日期區間
* 長期趨勢
* 回診摘要

目前使用假 Pro：

```dart
const bool kDemoUnlockPro = false;
final bool isPro = kDemoUnlockPro;
```

false：

* 一般使用者
* 顯示鎖定 UI

true：

* 測試 Pro 解鎖

---

# UI 設計風格

## 整體風格

* 療癒
* 柔和
* 卡片式
* 淺藍色系
* 留白
* 圓角
* 非社群感

避免：

* 過度科技感
* 過度醫療感
* 過度分析感
* 九宮格社群風

---

## 深色模式

目前深色模式方向：

背景：

```text
0xFF0F1720
```

卡片：

```text
0xFF1A2632
```

主文字：

```text
0xFFF2F7FA
```

副文字：

```text
0xFFB8C7D3
```

---

# Firebase 資料結構

## 日記

```text
users/{uid}/diary/{yyyy-MM-dd}
```

欄位：

* title
* content
* themeSong
* highlight
* metaphor
* conceited
* proudOf
* selfCare
* overallMood
* overallHealth
* overallSleepQuality
* imageUrls
* updatedAt
* isEncrypted

---

## 每日紀錄

```text
users/{uid}/dailyRecords/{yyyy-MM-dd}
```

---

## 圖片 Storage

```text
users/{uid}/diary_images/{yyyy-MM-dd}/{timestamp}.jpg
```

---

# 程式碼規則

## Flutter alias 規則

如果檔案使用：

```dart
import 'package:flutter/material.dart' as m;
```

所有 Flutter 型別都要加：

```dart
m.
```

例如：

* m.Widget
* m.BuildContext
* m.Text
* m.IconData
* m.VoidCallback
* m.Colors

不可混用。

---

# UX 原則

## 目前優先級

高優先：

* 基礎 AI 準確度
* 深色模式
* 日記體驗
* 情緒趨勢圖
* App 穩定度
* 圖片日記

中優先：

* Pro 預告頁
* 假訂閱
* GA4 追蹤

低優先：

* 深入分析完整 UX
* AI 診斷感功能
* 過度複雜動畫
* 超長 AI 報告

---

# 開發原則

* 優先小範圍修改
* 不重寫整個檔案
* 修改前先理解資料流
* 修 UI 不要破壞 Firebase / 加密 / AI / Pro 邏輯
* 優先維持穩定

目前專案狀態已接近正式產品，不再只是 side project。
