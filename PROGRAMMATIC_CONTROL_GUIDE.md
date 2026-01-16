# Firebase Sync Control - 程序控制版本

## 📌 关键变更

从**用户可控的toggle**改为**程序控制**。

## 🔧 使用方法

### 1️⃣ 控制同步行为

文件: `lib/utils/firebase_sync_config.dart`

```dart
// 改变这个常数来控制全局Firebase同步
static const bool kEnableFirebaseSync = true;   // 生产环境：true
                                                 // 开发环境：false
```

### 2️⃣ 在代码中检查

```dart
import '../utils/firebase_sync_config.dart';

// 任何Firebase写操作前面加上：
if (FirebaseSyncConfig.shouldSync()) {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .set({...});  // 只在启用时执行
}
```

### 3️⃣ 现有实现

已保护的操作：
- ✅ `lib/diary/diary_page_demo.dart` - 日记保存
- ✅ `lib/meds/medication_actions.dart` - 药物操作（所有）

## 🎯 没有用户界面

Settings页面**不会显示** Firebase同步toggle。

这完全由程序控制，用户看不到也改不了。

## 🔄 工作流程

```
kEnableFirebaseSync = true
    ↓
Firebase写操作 → shouldSync() = true → 执行写入 → Firebase ✅

kEnableFirebaseSync = false  
    ↓
Firebase写操作 → shouldSync() = false → 跳过 → 仅本地存储 ⚠️
```

## 💡 何时修改

| 场景 | 设置 |
|------|------|
| 生产环境 | `true` |
| 开发/测试 | `false` |
| 测试无网络 | `false` |
| 避免Firebase配额 | `false` |

## ✨ 优势

- ✅ 清晰的代码控制
- ✅ 不会被用户意外改动
- ✅ 易于通过build config分环境配置
- ✅ 本地存储始终工作
- ✅ Firebase写操作可选

## 🚀 扩展到新代码

添加sync检查到任何Firebase操作：

```dart
if (FirebaseSyncConfig.shouldSync()) {
  // 你的Firebase操作
  await firestore.write();
}
```

就这样！🎉
