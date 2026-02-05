# 🔍 PDF 報告文件位置查找指南

## 📍 默認存放位置

現已改為使用 **應用程式文件夾**（更安全、更容易找到）：

```
應用文件夾/PDF/
├── 心晴_醫師摘要_20240101-20240128.pdf
├── 心晴_醫師摘要_20240128-20240225.pdf
└── ...
```

### 完整路徑（Android）

```
/data/data/com.example.moodsogood_app/app_documents/PDF/
```

或簡化為：

```
應用程式文件 > PDF 文件夾
```

---

## 📱 如何在手機上找到文件

### 方法 1：使用應用內檔案管理器（推薦）

1. 打開檔案管理器 App
2. 進入 **應用程式** 或 **內部存儲**
3. 尋找 **moodsogood_app** 文件夾
4. 進入 **app_documents** > **PDF**
5. 找到你的 PDF 文件 ✅

### 方法 2：使用 Android 文件瀏覽器

1. 打開 **Files** 或 **檔案管理器**
2. 啟用 **顯示隱藏文件**（通常在設定中）
3. 進入：`內部存儲 > Android > data > com.example.moodsogood_app > files > app_documents > PDF`
4. 找到 PDF 文件 ✅

### 方法 3：通過電腦連接（最簡單）

1. 用 USB 線連接手機到電腦
2. 打開手機 USB 調試模式
3. 在電腦上進入手機存儲
4. 導航到：`Android\data\com.example.moodsogood_app\files\app_documents\PDF`
5. 看到你的 PDF 文件 ✅

---

## 🔧 備選位置

如果應用無法寫入應用文件夾，會自動改用以下位置（按優先級）：

### 1️⃣ Documents 文件夾（備選）
```
/storage/emulated/0/Documents/
```
**位置**：檔案管理器 > Documents 文件夾

### 2️⃣ 根目錄（最後備選）
```
/storage/emulated/0/
```

---

## 📋 文件名格式

所有 PDF 文件都遵循統一的命名格式：

```
心晴_醫師摘要_YYYYMMDD-YYYYMMDD.pdf
```

### 例子

- `心晴_醫師摘要_20240101-20240128.pdf` → 1月1日至1月28日
- `心晴_醫師摘要_20240315-20240411.pdf` → 3月15日至4月11日
- `心晴_醫師摘要_20241201-20241228.pdf` → 12月1日至12月28日

**提示**：按照文件名中的日期找到你需要的報告 📅

---

## 🆘 找不到文件的解決方案

### ✅ 解決步驟

1. **確認導出成功**
   - 檢查手機上是否看到「✅ PDF 已保存」的提示
   - 如果看到，說明導出成功，只是位置不對

2. **檢查權限**
   ```
   設定 > 應用程式 > 心晴 > 權限 > 存儲空間 > 允許
   ```
   確保應用有讀寫權限

3. **檢查所有可能的位置**
   - ✅ 應用程式文件夾（默認）
   - ✅ Documents 文件夾
   - ✅ Downloads 文件夾
   - ✅ 根目錄 `/storage/emulated/0`

4. **搜索文件**
   - 使用檔案管理器的搜索功能
   - 搜索關鍵詞：`心晴` 或 `.pdf`
   - 應該能找到最近導出的文件

5. **查看導出日誌**
   - 連接到 Android Studio 或使用 adb
   - 運行：`adb logcat | grep 心晴`
   - 查看詳細的路徑信息

---

## 🛠️ Android Studio 調試

如果在 Android Studio 中運行應用，可以查看 Logcat：

```
篩選器 → 搜索 "PDF"
```

你會看到類似的日誌：

```
📂 PDF 將保存到: /data/data/com.example.moodsogood_app/app_documents/PDF
✅ PDF 導出成功: /data/data/com.example.moodsogood_app/app_documents/PDF/心晴_醫師摘要_20240101-20240128.pdf
```

這會告訴你確切的文件路徑 📍

---

## 📞 常見問題

### Q: PDF 文件很大嗎？
**A**: 
- 基礎報告：500KB - 1MB
- 含詳細摘要：1MB - 2MB
- 含完整日記：2MB - 5MB

### Q: 我可以改變存放位置嗎？
**A**: 可以，但不推薦。應用文件夾最安全。

### Q: 可以在應用內預覽 PDF 嗎？
**A**: 可以，需要添加 `open_file` 套件來打開 PDF。

### Q: 導出失敗了怎麼辦？
**A**: 
1. 確認有足夠的存儲空間
2. 檢查應用權限
3. 查看 Logcat 日誌找到具體錯誤

### Q: 文件會被備份嗎？
**A**: 應用文件夾中的文件通常會被 Google One 備份。

---

## 🎯 快速總結

✅ **默認位置**：應用程式文件夾 > PDF  
✅ **文件名格式**：`心晴_醫師摘要_YYYYMMDD-YYYYMMDD.pdf`  
✅ **最簡單方法**：用電腦連接手機，進入 Android > data 文件夾  
✅ **調試方法**：查看 Logcat 日誌確認路徑  

現在應該能找到你的 PDF 報告了！🎉
