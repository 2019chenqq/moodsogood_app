# 看板管理 - 管理員權限設置

## 功能完成 ✅

已經為看板刪除功能添加了管理員權限檢查。

## 系統架構

### 1. 管理員身份驗證

**在代碼中定義管理員列表：**

- 文件 1: [rooms_management_page.dart](lib/community/pages/rooms_management_page.dart#L8-L10)
```dart
const List<String> _adminUids = [
  'admin-user-id-1',
  'admin-user-id-2',
];
```

- 文件 2: [community_home_page.dart](lib/community/community_home_page.dart#L468-L471)
```dart
bool _isAdmin() {
  const adminUids = ['admin-user-id-1', 'admin-user-id-2'];
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return uid != null && adminUids.contains(uid);
}
```

- 文件 3: [firestore.rules](firestore.rules#L51-L53)
```
allow delete: if request.auth != null 
              && request.auth.uid in ['admin-user-id-1', 'admin-user-id-2'];
```

### 2. 訪問控制

| 功能 | 普通用戶 | 管理員 |
|------|---------|--------|
| 看到管理員按鈕 | ❌ 隱藏 | ✅ 顯示 |
| 進入看板管理頁面 | ⚠️ 顯示無權限 | ✅ 完全訪問 |
| 刪除看板 | ❌ Firestore 拒絕 | ✅ 允許 |

## 設置管理員

### 步驟 1: 獲取管理員的 UID

1. 管理員登入 App
2. 查看 Logcat 或調試輸出，搜索該用戶的 Firebase UID
   或者在 Firebase Console 中查看：Settings > Users

### 步驟 2: 添加 UID 到代碼

修改以下文件，將管理員 UID 添加到列表中：

**文件 1: `lib/community/pages/rooms_management_page.dart`**
```dart
const List<String> _adminUids = [
  'admin-user-id-1',   // 第一個管理員
  'admin-user-id-2',   // 第二個管理員
  'fiona-uid-here',    // 添加新管理員
];
```

**文件 2: `lib/community/community_home_page.dart`（第 468 行）**
```dart
bool _isAdmin() {
  const adminUids = ['admin-user-id-1', 'admin-user-id-2', 'fiona-uid-here'];
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return uid != null && adminUids.contains(uid);
}
```

**文件 3: `firestore.rules`（第 51 行）**
```
allow delete: if request.auth != null 
              && request.auth.uid in ['admin-user-id-1', 'admin-user-id-2', 'fiona-uid-here'];
```

### 步驟 3: 部署

修改 Firestore 規則後，需要部署：
```bash
firebase deploy --only firestore:rules
```

## 使用流程

### 普通用戶
1. 打開社區首頁
2. **看不到** AppBar 右上角的管理員按鈕 ❌

### 管理員
1. 打開社區首頁
2. 看到 AppBar 右上角的 ⚙️ 管理員按鈕 ✅
3. 點擊進入看板申請審核頁面
4. 在審核頁面的 AppBar 看到 📁 看板管理按鈕
5. 進入看板管理頁面
6. 看到所有看板的列表
7. 點擊垃圾桶圖標刪除重複的看板

## 刪除按鈕的可見性

- ✅ **管理員**: 看到刪除按鈕
- ❌ **普通用戶**: 即使進入頁面也看到"無權限訪問"訊息

## 故障排查

### 問題 1: 看不到管理員按鈕
**原因**: 當前登入用戶的 UID 不在管理員列表中
**解決**:
1. 確認用戶 UID
2. 添加到所有三個文件中
3. 重新編譯 App
4. 重新啟動 App

### 問題 2: 進入看板管理頁面但看到"無權限訪問"
**原因**: 同上
**解決**: 同上

### 問題 3: 點擊刪除按鈕但失敗
**可能原因**:
- Firebase 規則還未部署
- 用戶 UID 不在 Firestore 規則的管理員列表中

**解決**:
1. 檢查終端 logcat 中的錯誤訊息
2. 運行 `firebase deploy --only firestore:rules` 重新部署
3. 等待 30 秒後重新嘗試

## 代碼同步

⚠️ **重要**: 修改代碼時需要在三個地方同時更新管理員 UID：

```
lib/community/pages/rooms_management_page.dart (第 8-10 行)
         ↓
lib/community/community_home_page.dart (第 468-471 行)
         ↓
firestore.rules (第 51-53 行)
```

保持三處一致，否則會出現權限不匹配的問題。

## 後續改進建議

1. **從 Firestore 讀取管理員列表** - 不需要每次都改代碼
2. **添加管理員管理面板** - 動態添加/移除管理員
3. **記錄操作日誌** - 誰在何時刪除了哪個看板
4. **批量操作** - 一次刪除多個重複看板
