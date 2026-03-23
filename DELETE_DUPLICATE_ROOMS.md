# 刪除重複看板指南

## 重複看板的原因

可能的原因：
1. 批准看板申請時意外執行多次
2. Firestore 重複寫入
3. 申請被多次批准

## 刪除方法

### 方法 1: Firebase Console（推薦快速方案）

1. 打開 [Firebase Console](https://console.firebase.google.com/)
2. 選擇 `moodsogood-9e45b` 項目
3. 進入 **Firestore Database**
4. 找到 `community_rooms` 集合
5. 選擇重複的看板文檔
6. 點擊刪除按鈕（垃圾桶圖標）

### 方法 2: 代碼刪除（需要修改規則）

如果想在 App 中提供刪除功能，需要：

1. **修改 `firestore.rules`** 允許創建者或管理員刪除：

```diff
match /community_rooms/{roomId} {
  allow read: if request.auth != null;
  allow create: if request.auth != null;
- allow update, delete: if false;
+ allow delete: if request.auth != null 
+               && resource.data.createdBy == request.auth.uid;
}
```

2. **在 Admin 頁面添加刪除按鈕**

```dart
// 在 room_requests_admin_page.dart 中添加
IconButton(
  icon: const Icon(Icons.delete_outline, color: Colors.red),
  onPressed: () => _deleteRoom(doc.id),
)

Future<void> _deleteRoom(String roomId) async {
  try {
    await FirebaseFirestore.instance
        .collection('community_rooms')
        .doc(roomId)
        .delete();
    
    // 顯示成功訊息
  } catch (e) {
    // 顯示錯誤訊息
  }
}
```

3. **部署規則**
```bash
firebase deploy --only firestore:rules
```

## 臨時快速方案

如果只需要立即清理，建議：

1. 用 **方法 1** 直接在 Firebase Console 刪除重複的文檔
2. 重新啟動 App，Firestore 會自動重新加載看板列表

## 查看當前看板

App 中的看板列表 = 硬編碼的 5 個基礎看板 + `community_rooms` 中的所有文檔

**基礎看板**（不能刪除）：
- 情緒低落
- 焦慮恐慌  
- 睡眠問題
- 藥物與副作用
- 想被聽見

**用戶建立的看板**（可刪除）：
- 所有通過申請系統建立的看板

如果看到某個看板出現多次，說明 `community_rooms` 中有重複的文檔。
