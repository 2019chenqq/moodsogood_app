# 身體測量隱私功能實作說明

## 功能概述

使用者現在可以選擇是否要在回診摘要中包含敏感的身體測量資料（體重、體脂率、腰圍）。這項功能讓注重隱私的使用者能夠完全控制哪些健康資訊會分享給醫師。

## 實作內容

### 1. 資料模型更新 (`lib/models/follow_up_ai_summary.dart`)

#### FollowUpSummaryShareOptions 類別
- 新增 `bodyMeasurements` 欄位（boolean）
- 更新 `none` 和 `all` 常數以包含新欄位
- 更新 `hasSelection` getter
- 更新 `copyWith` 方法

#### FollowUpSummaryDisplayModel 類別
- 將原本的 `symptomAndBodyChanges` 拆分為兩個獨立欄位：
  - `symptoms` - 身體症狀（最多 5 個）
  - `bodyMeasurements` - 身體測量（體重、體脂率、腰圍）
- 修改 `_symptomAndBodyItems` 方法，拆分為：
  - `_symptomItems` - 只處理症狀資料
  - `_bodyMeasurementItems` - 只處理身體測量資料
- 更新 `fromRecord` factory：
  - `symptoms` 根據 `options.emotionsAndSymptoms` 決定是否包含
  - `bodyMeasurements` 根據 `options.bodyMeasurements` 決定是否包含
  - `includedSections` 根據 `options.bodyMeasurements` 添加或省略 'bodyMeasurements'

- 更新 `toDeidentifiedSnapshot` 方法：
  - `bodyMeasurements` 現在獨立於 `emotionsAndSymptoms` 選項
  - 只有當 `options.bodyMeasurements` 為 true 時才包含身體測量資料

### 2. UI 更新 (`lib/pages/follow_up_share_preview_page.dart`)

在「分享給醫師」頁面的選擇清單中新增：
```
☑ 身體測量（體重、體脂率、腰圍）
```

這個選項：
- 位於「情緒症狀」和「藥物調整」之間
- 使用明確的標籤說明包含的內容
- 可以獨立開關，不影響其他選項

### 3. 測試覆蓋 (`test/follow_up_body_measurements_privacy_test.dart`)

建立了 6 個測試案例：
1. ✅ 當 `bodyMeasurements` 為 true 時包含身體測量
2. ✅ 當 `bodyMeasurements` 為 false 時排除身體測量（但保留症狀）
3. ✅ 去識別化快照在啟用時包含身體測量
4. ✅ 去識別化快照在停用時排除身體測量
5. ✅ `includedSections` 在啟用時包含 'bodyMeasurements'
6. ✅ `includedSections` 在停用時不包含 'bodyMeasurements'

## 使用者體驗

### 分享流程
1. 使用者點擊「分享給醫師」
2. 在分享預覽頁面，使用者看到所有可分享的內容選項
3. 使用者可以：
   - 只分享討論主題和症狀（不含身體測量）
   - 或選擇包含身體測量
4. 預覽區域即時反映使用者的選擇
5. 使用者確認後匯出 PDF 或產生 QR Code

### 隱私保護
- 身體測量資料（體重、體脂率、腰圍）完全由使用者控制
- 即使選擇了「情緒症狀」選項，身體測量也不會自動包含
- 去識別化處理確保只有使用者明確選擇的內容才會被分享
- **實際數值不會顯示**：只顯示變化趨勢（增加/減少）和變化量，不顯示起始值、目前值或絕對數值
  - 例如：顯示「體重：減少 1.5kg」而非「體重：60kg → 58.5kg」
  - 例如：顯示「體脂率：無明顯變化」而非「體脂率：25% → 24%」

## 技術細節

### 向後相容性
- `bodyMeasurements` 參數在所有相關方法中都有預設值 `true`
- 舊程式碼不需要修改就能正常運作
- 現有的分享連結和 PDF 產生邏輯保持不變

### 資料流
```
使用者選擇 → FollowUpSummaryShareOptions 
           → FollowUpSummaryDisplayModel.fromRecord()
           → 條件式包含身體測量
           → PDF/QR Code 生成
```

## 測試結果

```
✅ includes body measurements when bodyMeasurements option is true
✅ excludes body measurements when bodyMeasurements option is false
✅ includes body measurements in deidentified snapshot when enabled
✅ excludes body measurements from deidentified snapshot when disabled
✅ bodyMeasurements option is included in includedSections when true
✅ bodyMeasurements option is not in includedSections when false

All 6 tests passed!
```

## 相關檔案

### 修改的檔案
- `lib/models/follow_up_ai_summary.dart` - 資料模型和邏輯
- `lib/pages/follow_up_share_preview_page.dart` - 使用者介面

### 新增的檔案
- `test/follow_up_body_measurements_privacy_test.dart` - 測試案例

## 未來改進建議

1. 可以考慮記住使用者的隱私偏好，下次分享時自動套用
2. 可以針對不同的身體測量類型（體重、體脂率、腰圍）提供更細緻的控制
3. 可以在摘要編輯頁面中也提供隱私控制選項