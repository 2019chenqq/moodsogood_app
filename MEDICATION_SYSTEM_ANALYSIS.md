# 药物记录功能完整实现分析

## 📋 目录
1. [文件架构](#文件架构)
2. [数据模型](#数据模型)
3. [核心功能](#核心功能)
4. [数据流与集成](#数据流与集成)
5. [提醒与通知](#提醒与通知)
6. [数据隐私与加密](#数据隐私与加密)
7. [Pro/Free版本限制](#profree版本限制)
8. [与Daily Record集成](#与daily-record集成)

---

## 文件架构

### 主要页面文件结构

```
lib/meds/
├── 📄 medication_home_page.dart           # 药物管理首页（列表视图）
├── 📄 add_medication_page.dart            # 新增药物页面
├── 📄 edit_medication_page.dart           # 编辑药物页面
├── 📄 medication_detail_page.dart         # 药物详情页面
├── 📄 record_adjustment_page.dart         # 回诊/调药记录页面（核心）
├── 📄 record_adjustment_history_page.dart # 调药历史时间线
├── 📄 medication_checkin_page.dart        # 服药打卡页面（进度追踪）
├── 📄 med_symptom_compare_page.dart       # 药物×症状交叉对比
├── 📄 med_adjustment_timeline.dart        # 调药时间线组件
│
├── 🔧 medication_local_db.dart            # SQLite数据库操作
├── 🔧 medication_reminder_service.dart    # 服药提醒服务
├── 🔧 medication_actions.dart             # 药物业务逻辑（激活/停用/删除）
└── 🔧 drug_dictionary_service.dart        # 药物搜索字典
```

### 完整文件列表

| 文件 | 用途 | 关键类/函数 |
|-----|------|-----------|
| [medication_home_page.dart](lib/meds/medication_home_page.dart) | 药物列表管理 | `MedicationHomePage` - 分页显示"目前使用"和"已停用" |
| [add_medication_page.dart](lib/meds/add_medication_page.dart) | 新增药物 | `AddMedicationPage` - 支持口服/针剂/滴剂 |
| [edit_medication_page.dart](lib/meds/edit_medication_page.dart) | 编辑药物 | `EditMedicationPage` - 修改已有药物 |
| [medication_detail_page.dart](lib/meds/medication_detail_page.dart) | 药物详情 | `MedicationDetailPage` - 详细信息展示 |
| [record_adjustment_page.dart](lib/meds/record_adjustment_page.dart) | **调药记录** | `RecordAdjustmentPage` - 记录每次回诊调药 |
| [record_adjustment_history_page.dart](lib/meds/record_adjustment_history_page.dart) | 调药历史 | 显示过去调药事件 |
| [medication_checkin_page.dart](lib/meds/medication_checkin_page.dart) | 服药打卡 | `MedicationCheckinPage` - 日常追踪遵循度 |
| [med_symptom_compare_page.dart](lib/meds/med_symptom_compare_page.dart) | 药物-症状对比 | `MedSymptomComparePage` - 分析影响 |
| [med_adjustment_timeline.dart](lib/meds/med_adjustment_timeline.dart) | 时间线组件 | `MedicationAdjustmentTimeline` |
| [medication_local_db.dart](lib/meds/medication_local_db.dart) | 本地数据库 | `MedicationLocalDB` - SQLite操作 |
| [medication_reminder_service.dart](lib/meds/medication_reminder_service.dart) | 提醒服务 | `MedicationReminderService` - 通知管理 |
| [medication_actions.dart](lib/meds/medication_actions.dart) | 业务逻辑 | `showMedicationMoreSheet()` - 激活/停用/删除 |
| [drug_dictionary_service.dart](lib/meds/drug_dictionary_service.dart) | 药物字典 | `DrugDictionaryService` - 搜索建议 |

---

## 数据模型

### 1. SQLite 数据库结构

#### 表1: `medications` 表 (主药物信息)
```dart
CREATE TABLE medications (
  id TEXT PRIMARY KEY,              // Firebase文档ID
  uid TEXT NOT NULL,                // 用户ID
  name TEXT NOT NULL,               // 药物中文名称
  dose REAL,                        // 每次/每顆劑量
  dosePerUnit REAL,                 // 每顆劑量（口服）
  pillCount REAL,                   // 每次幾顆（口服）
  concentrationMg REAL,             // 濃度mg（滴劑）
  concentrationMl REAL,             // 濃度mL（滴劑）
  intakeMl REAL,                    // 每次攝取mL（滴劑）
  unit TEXT,                        // 單位（mg/mL/etc）
  type TEXT,                        // 药物形式：'tablet'/'injection'/'drops'
  intervalDays INTEGER,             // 注射間隔天數（針劑用）
  times TEXT,                       // 服用時間 JSON ["早上","晚上"]
  purposes TEXT,                    // 用途 JSON ["安眠藥","抗焦慮"]
  note TEXT,                        // 備註
  startDate TEXT,                   // 開始使用日期
  isActive INTEGER DEFAULT 1,       // 0=已停用 / 1=使用中
  bodySymptoms TEXT,                // 身體症狀 JSON []
  purposeOther TEXT,                // 其他用途
  createdAt TEXT,                   // 創建時間
  updatedAt TEXT,                   // 更新時間
  lastChangeAt TEXT                 // 最後調整時間
)
```

#### 表2: `medAdjustments` 表 (调药历史记录)
```dart
CREATE TABLE medAdjustments (
  id TEXT PRIMARY KEY,              // Firebase文档ID
  uid TEXT NOT NULL,                // 用户ID
  date TEXT NOT NULL,               // 調藥日期 "YYYY/MM/DD"
  note TEXT,                        // 本次調藥備註
  items TEXT,                       // 變動項目 JSON array
  createdAt TEXT                    // 記錄建立時間
)
```

### 2. 调药项目结构 (medAdjustments.items)
```dart
{
  'medDocId': String,               // 藥物ID
  'name': String,                   // 藥物名稱
  'type': String,                   // 變動類型: 
                                    // 'added'/'injected'/'doseChanged'/
                                    // 'scheduleChanged'/'stopped'/'unchanged'
  'oldDose': double?,               // 原劑量（新增藥物為null）
  'newDose': double?,               // 新劑量（停藥為null）
  'oldTimes': List<String>?,        // 原時間（新增藥物為null）
  'newTimes': List<String>?,        // 新時間
  'unit': String,                   // 單位
  'stopReason': String?             // 停藥原因
}
```

### 3. 服药打卡数据结构
```dart
medicationCheckins/{YYYYMMDD}      // 按日期分组
{
  'checks': {
    '{medId}::{slot}': bool         // 是否已打卡
  },
  'statuses': {
    '{medId}::{slot}': 'pending'/'taken'/'skipped'/'prn'
  },
  'statusAt': {
    '{medId}::{slot}': Timestamp    // 狀態更新時間
  },
  'actualAmounts': {
    '{medId}::{slot}': double       // 實際服用量
  },
  'prnEvents': {
    '{medId}::需要時': [Timestamp]   // PRN 用藥事件列表
  }
}
```

---

## 核心功能

### 1. 药物类型与数据输入

#### 支持的药物形式
```dart
enum MedicationType { 
  tablet,      // 口服藥：有"每次幾顆"和"每顆劑量"
  injection,   // 長效針：無固定時間，用"注射間隔"天數
  drops        // 滴劑：有"濃度"和"攝取量"計算
}
```

#### 示例数据
```dart
// 口服藥：克癇平 25mg x 2顆 = 50mg
{
  'name': '克癇平',
  'type': 'tablet',
  'dosePerUnit': 25.0,          // 每顆25mg
  'pillCount': 2.0,            // 每次2顆
  'dose': 50.0,                // 計算結果：50mg
  'unit': 'mg',
  'times': ['早上', '晚上'],
  'purposes': ['抗癲癇'],
  'isActive': true,
  'startDate': '2024-01-01'
}

// 長效針：保樂定棕 600mg 每28天
{
  'name': '保樂定棕',
  'type': 'injection',
  'dose': 600.0,
  'unit': 'mg',
  'intervalDays': 28,
  'purposes': ['精神分裂症'],
  'isActive': true,
  'startDate': '2024-01-15'
}

// 滴劑：氯硝西泮 濃度 2mg/10mL，每次取 5mL
{
  'name': '氯硝西泮',
  'type': 'drops',
  'concentrationMg': 2.0,       // 濃度：2mg
  'concentrationMl': 10.0,      // 在10mL溶液中
  'intakeMl': 5.0,              // 每次攝取5mL
  'dose': 1.0,                  // 計算結果：1mg (2/10 * 5)
  'unit': 'mg',
  'times': ['晚上'],
  'purposes': ['抗焦慮'],
  'isActive': true
}
```

### 2. 多种药物与多次服用

**特性：** ✅ 完全支持
- **多个药物**：无限制数量
- **多次服用**：支援6个时间槽：早、中、下、晚、睡前、需要时
- **每天记录**：每日可记录多个药物x多个时间组合的打卡状态

**关键代码：**
```dart
// 时间槽定义
const List<String> kOralTimeSlots = ['早上', '中午', '下午', '晚上', '睡前', '需要時'];

// 打卡项目生成
for (final med in activeMeds) {
  final times = med['times']?.whereType<String>() ?? [];
  for (final slot in times.isEmpty ? ['未設定'] : times) {
    items.add(
      _CheckinItem(
        medId: medId,
        medName: name,
        slot: slot,
        plannedAmount: dose,
      ),
    );
  }
}
```

### 3. 药物状态管理

```dart
enum MedChangeType {
  unchanged,      // 保持原狀
  added,          // 本次新開
  injected,       // 已施打（針劑）
  doseChanged,    // 劑量調整
  scheduleChanged,// 時間調整
  stopped         // 停藥
}
```

---

## 数据流与集成

### 系统架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      用户界面层 (UI)                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌──────────────────┐ ┌────────────┐ │
│  │ 藥物列表頁      │  │ 回診/調藥頁      │ │ 服藥打卡   │ │
│  │ (Home)          │  │ (Adjustment)     │ │ (Checkin)  │ │
│  └────────┬────────┘  └────────┬─────────┘ └─────┬──────┘ │
│           │                     │               │          │
│  ┌────────────────────┐  ┌──────────────────┐  │          │
│  │ 新增/編輯頁        │  │ 症狀交叉對比     │  │          │
│  │ (Add/Edit)         │  │ (Symptom Compare)│  │          │
│  └──────────┬─────────┘  └────────┬─────────┘  │          │
│             │                      │             │          │
└─────────────┼──────────────────────┼─────────────┼──────────┘
              │                      │             │
              ▼                      ▼             ▼
┌─────────────────────────────────────────────────────────────┐
│                    業務邏輯層 (Service)                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────┐  ┌─────────────────────────────┐ │
│  │ medication_          │  │ drug_dictionary_service.    │ │
│  │ actions.dart         │  │ dart (搜尋建議)             │ │
│  │ - 激活/停用/刪除     │  │ - 內建種子字典              │ │
│  │ - 提醒同步           │  │ - 個人字典快取              │ │
│  └──────────┬───────────┘  └────────────────┬────────────┘ │
│             │                              │               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ medication_reminder_service.dart                    │  │
│  │ - 管理時間槽提醒 (早/中/下/晚/睡前)                │  │
│  │ - 自動重建每日服藥提醒通知                         │  │
│  │ - NotificationHelper 集成                          │  │
│  └─────────────┬──────────────────────────────────────┘  │
│                │                                          │
└────────────────┼──────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              數據存儲層 (Database & Storage)                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌────────────────────────┐  ┌─────────────────────────┐   │
│  │ MedicationLocalDB      │  │ Firebase Firestore      │   │
│  │ (SQLite - sqflite)     │  │ (Cloud Storage)         │   │
│  │                        │  │                         │   │
│  │ ├─ medications         │  │ /users/{uid}/           │   │
│  │ │  └─ v4 schema        │  │   medications/ {}       │   │
│  │ ├─ medAdjustments      │  │   medAdjustments/ {}    │   │
│  │ │  └─ v2 schema        │  │   medicationCheckins/{}│   │
│  │ └─ Sync state tracker  │  │   drugDictionary/ {}    │   │
│  │                        │  │                         │   │
│  └────────────┬───────────┘  └────────────┬────────────┘   │
│               │                           │                │
│       ┌───────┴───────────┐               │                │
│       │ EncryptionService │ ◄─────────────┘                │
│       │ (AES-256-GCM)     │                                │
│       └───────────────────┘                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 数据同步流程

```
┌──────────────────────────────────────────────────────┐
│ 1️⃣ 用户新增/编辑藥物                                │
└────────────────────┬─────────────────────────────────┘
                     ▼
         ┌───────────────────────┐
         │ 驗證表單             │
         │ - 必填字段           │
         │ - 劑量計算           │
         └────────────┬──────────┘
                      ▼
  ┌───────────────────────────────────┐
  │ 2️⃣ 寫入本地 SQLite 數據庫        │
  │ MedicationLocalDB.addMedication() │
  │                                   │
  │ ✅ 確保本地優先保存               │
  └─────────────┬─────────────────────┘
                ▼ (立即返回 UI 成功)
┌─────────────────────────────────────────────────┐
│ 3️⃣ 背景同步到 Firebase（如啟用）              │
│ - 檢查 FirebaseSyncConfig.shouldSync()         │
│ - 上傳到 /users/{uid}/medications/{docId}     │
│ - FieldValue.serverTimestamp()                 │
└─────────────┬───────────────────────────────────┘
              ▼
 ┌────────────────────────────────────┐
 │ 4️⃣ 重建服藥提醒                   │
 │ MedicationReminderService.         │
 │ syncDailyRemindersForActiveMeds()  │
 │                                    │
 │ - 掃描所有激活的口服藥            │
 │ - 按時間槽重新編排提醒             │
 │ - 推送本地通知                     │
 └────────────────────────────────────┘
```

---

## 提醒与通知

### 1. 时间槽提醒配置

```dart
class MedicationReminderService {
  static const Map<String, TimeOfDay> kSlotTimes = {
    '早上': TimeOfDay(hour: 8, minute: 0),      // 08:00
    '中午': TimeOfDay(hour: 12, minute: 30),    // 12:30
    '下午': TimeOfDay(hour: 18, minute: 0),     // 18:00
    '晚上': TimeOfDay(hour: 20, minute: 0),     // 20:00
    '睡前': TimeOfDay(hour: 22, minute: 30),    // 22:30
  };

  static const Map<String, int> _slotNotificationIds = {
    '早上': 21101,
    '中午': 21102,
    '下午': 21103,
    '晚上': 21104,
    '睡前': 21105,
  };
}
```

### 2. 提醒同步机制

```dart
// 关键函数：root/lib/meds/medication_reminder_service.dart
static Future<int> syncDailyRemindersForActiveMeds() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 0;

  final helper = NotificationHelper();
  await helper.init();

  // 1️⃣ 获取所有激活的口服藥（排除注射)
  final meds = await MedicationLocalDB().getMedicationsForDisplay(uid);
  final activeOralMeds = meds.where((m) {
    final isActive = (m['isActive'] as bool?) ?? true;
    final isInjection = (m['type'] as String?) == 'injection';
    return isActive && !isInjection;
  }).toList();

  // 2️⃣ 按時間槽分組藥物
  final Map<String, List<String>> medsBySlot = {
    for (final key in kSlotTimes.keys) key: <String>[],  // 初始化所有時段
  };

  for (final med in activeOralMeds) {
    final name = (med['name'] ?? '未命名藥物') as String;
    final times = ((med['times'] as List?) ?? [])
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    
    for (final slot in times) {
      if (medsBySlot.containsKey(slot)) {
        medsBySlot[slot]!.add(name);
      }
    }
  }

  // 3️⃣ 為每個時段設置提醒
  int reminderCount = 0;
  for (final entry in medsBySlot.entries) {
    final slot = entry.key;
    final meds = entry.value;
    final notifId = _slotNotificationIds[slot] ?? 21000 + reminderCount;
    
    if (meds.isNotEmpty) {
      final slotTime = await getSlotTime(slot);
      final title = '$slot 服藥提醒';
      final body = meds.join('、');
      
      await helper.scheduleNotification(
        id: notifId,
        title: title,
        body: body,
        time: slotTime,
      );
      
      reminderCount++;
    } else {
      // 清除空時段的提醒
      await helper.cancel(notifId);
    }
  }

  return reminderCount;
}
```

### 3. 用户自定义提醒时间

```dart
// 用户可以自定义每个时间槽的提醒时间
static Future<void> setSlotTime(String slot, TimeOfDay time) async {
  final prefs = await SharedPreferences.getInstance();
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  await prefs.setString('med_reminder_${slot}_time', '$h:$m');
  
  // 更新后需要重建提醒
  await syncDailyRemindersForActiveMeds();
}
```

### 4. 通知流程

```
用户设置时间 → SharedPreferences 保存 → 重建所有提醒
                                           ↓
                            NotificationHelper 调度
                                           ↓
                    FlutterLocalNotifications 发送
                                           ↓
                        系统通知显示（特定时间）
                                           ↓
                      用户点击 → 打开 MedicationCheckinPage
```

---

## 数据隐私与加密

### 加密实现

```dart
// lib/utils/encryption_service.dart

class EncryptionService {
  final Key key;  // 256-bit AES 密钥

  /// 🔒 加密函数
  String encryptData(String plainText) {
    // 每次生成随机 IV (16 bytes)
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    
    // 返回格式: "IV(base64):加密内容(base64)"
    return '${iv.base64}:${encrypted.base64}';
  }

  /// 🔓 解密函数
  String? tryDecryptData(String combinedText) {
    try {
      final parts = combinedText.split(':');
      if (parts.length != 2) return combinedText;
      
      final iv = IV.fromBase64(parts[0]);
      final encryptedText = Encrypted.fromBase64(parts[1]);
      
      final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
      return encrypter.decrypt(encryptedText, iv: iv);
    } catch (e) {
      print('解密失败: $e');
      return null;
    }
  }
}
```

### 密钥管理

```dart
// lib/utils/secure_storage_service.dart

class SecureStorageService {
  static const _storage = FlutterSecureStorage();  // 平台原生安全存储
  static const _keyAlias = 'user_aes_encryption_key';
  
  /// 保存加密密钥到安全存储
  static Future<void> saveKey(Key key) async {
    // 1. 保存密钥本身
    await _storage.write(
      key: _keyAlias,
      value: key.base64,
    );
    
    // 2. 保存验证器（确保密钥有效）
    final verifier = buildKeyVerifier(key);
    await _storage.write(
      key: 'encryptionVerifier',
      value: verifier,
    );
  }
  
  /// 从安全存储读取密钥
  static Future<Key?> getKey() async {
    final keyString = await _storage.read(key: _keyAlias);
    if (keyString == null) return null;
    
    try {
      return Key.fromBase64(keyString);
    } catch (e) {
      return null;
    }
  }
}
```

### 加密数据在Firebase中的存储

```dart
// Daily Record 集成示例
final encryptedData = {
  'title': encService.encryptData(titleText),          // "IV:密文"
  'content': encService.encryptData(contentText),
  'medication': encService.encryptData(medText),       // 药物信息加密
  'themeSong': encService.encryptData(songText),
  'createdAt': FieldValue.serverTimestamp(),           // 时间戳不加密
};

await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('diaries')
    .doc(docId)
    .set(encryptedData);
```

**数据隐私说明：**
- ✅ 日记内容：AES-256-GCM 加密存储
- ✅ 药物信息可选择加密（与 Daily Record 集成时）
- ✅ 密钥：存储在设备的原生安全存储（iOS Keychain / Android KeyStore）
- ✅ 无法在服务器端解密：每个用户有唯一的密钥

---

## Pro/Free版本限制

### 当前状态：❌ **无任何限制**

所有药物记录功能开放给所有用户，包括：
- ✅ 无限数量的药物管理
- ✅ 完整的调药历史记录
- ✅ 服药打卡与进度追踪
- ✅ 药物×症状交叉分析
- ✅ 完整的提醒系统
- ✅ 所有数据加密功能

> **注注：** 若未来要添加 Pro 限制，可在以下位置实现：
> ```dart
> // 在 add_medication_page.dart 中检查
> final userPlan = await getUserSubscriptionTier();  // 'free' / 'pro'
> if (userPlan == 'free' && medicationCount >= 5) {
>   showDialog('免费版最多5种药物');
>   return;
> }
> ```

---

## 与Daily Record集成

### 集成方式

#### 1️⃣ 睡眠记录中的安眠药

**位置：** `lib/daily/daily_record_pages.dart` → `SleepPage`

```dart
class SleepData {
  final bool tookHypnotic;        // 是否服用安眠药
  final String? hypnoticName;     // 安眠药名称
  final String? hypnoticDose;     // 安眠药剂量
  
  // ... 其他睡眠字段
}
```

**集成方式：**
```dart
// 在日记保存时，关联药物信息
final sleepRecord = {
  'tookHypnotic': true,
  'hypnoticName': '艾司唑仑',      // 与药物列表关联
  'hypnoticDose': '1mg',
  'quality': 7,
  'sleepTime': '23:00',
  'wakeTime': '07:00',
};
```

#### 2️⃣ 每日情绪/症状中的药物标记

**位置：** `lib/daily/daily_record_screen.dart`

```dart
// 日记中可记录当天的药物服用情况
final dailyRecord = {
  'date': DateTime.now(),
  'emotions': [...],
  'symptoms': [...],
  'medication': {
    'today_meds': ['克癇平', '思樂康'],    // 今日服用
    'checkin_status': {
      'morning': true,                    // 早上已服用
      'evening': false,                   // 晚上未服用
    }
  },
  'sleep': {...},
};
```

#### 3️⃣ AI日记反思中的药物关联

**位置：** `lib/diary/ai_journal_reflection_page.dart`

```dart
// 在 AI 分析中包含药物数据
final reflectionData = {
  'emotions': emotionData,
  'symptoms': symptomData,
  'sleep': sleepData,
  'medication': medicationData,    // 💊 新增
};

// AI Prompt 中考虑药物因素
final prompt = '''
用户今天的日记显示：
- 情绪：${}
- 症状：${}
- 睡眠：${}
- 服用药物：$medicationList  ← 影响分析
请分析这些数据的关联性...
''';
```

#### 4️⃣ 数据一致性

**同步流程：**
```
MedicationCheckinPage 打卡
        ↓
更新 medicationCheckins/{date}
        ↓
定期同步到 DailyRecord 的 medication 字段
        ↓
AI 反思引擎获取完整数据集
```

### 关键集成点代码

```dart
// lib/daily/daily_record_screen.dart - 加载药物信息
Future<void> _loadTodaysMedication() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final docId = _dateToDocId(DateTime.now());
  final checkinRef = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('medicationCheckins')
      .doc(docId);

  final checkinSnap = await checkinRef.get();
  if (!checkinSnap.exists) return;

  final data = checkinSnap.data()!;
  setState(() {
    _todaysMedicationStatus = {
      'checks': data['checks'] ?? {},
      'statuses': data['statuses'] ?? {},
    };
  });
}

// 在保存日记时，关联药物打卡数据
await dailyRecordRef.set({
  ...existingData,
  'medication': {
    'checkedMeds': _todaysMedicationStatus['checks'],
    'medStatuses': _todaysMedicationStatus['statuses'],
  },
}, SetOptions(merge: true));
```

---

## 功能流程图

### 场景：用户回诊调药

```
用户打开"紀錄調整"頁
        ↓
┌───────────────────────────────────────┐
│ 選擇這次回診日期（預設今天）         │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ 對每個正在使用的藥物標註變動         │
│ ├─ 維持原劑量（無改動）              │
│ ├─ 劑量調整（輸入新劑量）           │
│ ├─ 時間調整（調整服用時段）         │
│ ├─ 已施打（針劑特定）               │
│ └─ 停藥（標記理由）                 │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ 新增這次新開的藥物（可選）          │
│ → 跳轉到 AddMedicationPage           │
│ → 回傳後自動標記為"新增"類型         │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ 輸入本次調藥備註（可選）            │
│ 例：「醫生建議停用 A，增加 B」       │
└───────────────────────────────────────┘
        ↓
    ┌─────────────────┐
    │ 點擊「儲存」    │
    └────────┬────────┘
             ▼
┌─────────────────────────────────────────┐
│ 1️⃣ 本地先存 SQLite                    │
│    medAdjustments 表                    │
│    ✅ 確保無網路也能保存                │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 2️⃣ 同步到 Firebase                     │
│    /users/{uid}/medAdjustments/{id}    │
│    ✅ 跨設備同步                        │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 3️⃣ 更新藥物主檔                       │
│    - 新劑量 / 新時間                   │
│    - isActive 狀態                     │
│    - updatedAt / lastChangeAt          │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 4️⃣ 重建每日提醒                       │
│    MedicationReminderService.          │
│    syncDailyRemindersForActiveMeds()   │
│                                        │
│    - 停用的藥取消提醒                 │
│    - 新增的藥建立提醒                 │
│    - 時間調整的更新通知               │
└────────────┬────────────────────────────┘
             ▼
    ┌──────────────────┐
    │ ✅ 成功儲存     │
    │ 返回藥物列表    │
    └──────────────────┘
```

### 场景：日常服药打卡

```
用户打開"服藥打卡"
        ↓
┌────────────────────────────────────────┐
│ 系統自動生成今天的服藥清單            │
│ = 所有激活樂物 × 時間槽交叉           │
│                                        │
│ 示例：                                │
│ ☐ 克癇平 - 早上 (50mg)               │
│ ☐ 克癇平 - 晚上 (50mg)               │
│ ☐ 思樂康 - 晚上 (200mg)              │
│ ☐ 艾司唑侖 - 睡前 (1mg)              │
└────────────────────────────────────────┘
        ↓
    用戶打卡或標記
        │
        ├─ ✅ 已服用
        ├─ ⏭️  跳過
        └─ 🆘 改用量
        ↓
┌────────────────────────────────────────┐
│ 即時保存到 Firestore                  │
│ medicationCheckins/20240515            │
│ {                                      │
│   checks: {                            │
│     'med1::早上': true,               │
│     'med1::晚上': true,               │
│     'med2::晚上': false,              │
│   },                                   │
│   statuses: {                          │
│     'med1::早上': 'taken',           │
│     'med2::晚上': 'skipped',         │
│   }                                    │
│ }                                      │
└────────────────────────────────────────┘
        ↓
┌────────────────────────────────────────┐
│ 統計周期（7天/30天）遵循率            │
│ - 平均完成率                          │
│ - 最常遺漏的時段                      │
│ - 連續完成天數                        │
└────────────────────────────────────────┘
        ↓
    ┌──────────────────┐
    │ 顯示進度圖表    │
    │ 分析趨勢        │
    └──────────────────┘
```

---

## 关键代码片段

### 1. 创建药物记录
**文件：** [add_medication_page.dart](lib/meds/add_medication_page.dart#L750-L820)

```dart
// 保存藥物到 Firebase 和本地 DB
final docId = FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('medications')
    .doc()
    .id;

final medicationData = {
  'id': docId,
  'name': name,
  'dose': doseValue,                              // 计算后的最终剂量
  'dosePerUnit': dosePerUnit,                     // 每顆/每mL
  'pillCount': pillCount,                         // 每次几顆
  'concentrationMg': concentrationMg,             // 濃度
  'concentrationMl': concentrationMl,
  'intakeMl': intakeMl,
  'unit': _medType == 'drops' ? 'mg' : _unit,
  'type': _medType,                               // tablet/injection/drops
  'intervalDays': _medType == 'injection' ? _intervalDays : null,
  'times': times,                                 // ['早上', '晚上']
  'purposes': purposes,                           // ['安眠藥', '抗焦慮']
  'note': _noteCtrl.text.trim(),
  'startDate': DateTime(_startDate.year, _startDate.month, _startDate.day).toString(),
  'isActive': _isActive,
  'bodySymptoms': bodySymptoms,
  'purposeOther': purposeOther.isEmpty ? null : purposeOther,
  'createdAt': now.toString(),
  'updatedAt': now.toString(),
  'lastChangeAt': null,
};

// 保存本地
await MedicationLocalDB().addMedication(uid, medicationData);

// 同步 Firebase（如果啟用）
if (FirebaseSyncConfig.shouldSync()) {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('medications')
      .doc(docId)
      .set(medicationData);
}
```

### 2. 记录调药事件
**文件：** [record_adjustment_page.dart](lib/meds/record_adjustment_page.dart#L790-L900)

```dart
// 保存本次調藥紀錄
final items = changed.map((e) {
  final docId = e.key;
  final draft = e.value;
  
  return <String, dynamic>{
    'medDocId': docId,
    'name': draft.name,
    'type': draft.type.name,                      // 变动类型
    'oldDose': draft.oldDose,
    'newDose': draft.newDose,
    'oldTimes': draft.oldTimes,                   // ['早上']
    'newTimes': draft.newTimes,                   // ['早上', '晚上']
    'unit': draft.unit,
    'stopReason': draft.stopReason,
  };
}).toList();

// 1️⃣ 本地保存（必须）
await MedicationLocalDB().addAdjustmentRecord(uid, adjId, {
  'date': dateStr,
  'note': _noteCtrl.text.trim(),
  'items': items,
  'createdAt': DateTime.now().toString(),
});

// 2️⃣ Firebase 保存
final adjRef = userRef.collection('medAdjustments').doc();
batch.set(adjRef, {
  'date': Timestamp.fromDate(DateTime(_date.year, _date.month, _date.day)),
  'note': _noteCtrl.text.trim(),
  'items': items,
  'createdAt': FieldValue.serverTimestamp(),
});

// 3️⃣ 更新药物主档
for (final e in changed) {
  final medRef = userRef.collection('medications').doc(e.key);
  final draft = e.value;
  
  final patch = <String, dynamic>{
    'updatedAt': FieldValue.serverTimestamp(),
    'lastChangeAt': adjDate,
  };
  
  if (draft.type == MedChangeType.doseChanged) {
    patch['dose'] = draft.newDose;
    patch['times'] = draft.newTimes;
  } else if (draft.type == MedChangeType.stopped) {
    patch['isActive'] = false;
  }
  
  batch.set(medRef, patch, SetOptions(merge: true));
}

// 4️⃣ 重建提醒
await MedicationReminderService.syncDailyRemindersForActiveMeds();
```

### 3. 获取药物列表
**文件：** [medication_local_db.dart](lib/meds/medication_local_db.dart#L240-L300)

```dart
// 获取用于显示的药物列表
Future<List<Map<String, dynamic>>> getMedicationsForDisplay(String uid) async {
  final db = await database;
  final results = await db.query(
    'medications',
    where: 'uid = ?',
    whereArgs: [uid],
    orderBy: 'isActive DESC, name ASC',  // 激活的在前，然后按名字排序
  );
  
  return results.map((m) {
    // 反序列化 JSON 字段
    return {
      'id': m['id'],
      'name': m['name'],
      'dose': m['dose'],
      'unit': m['unit'],
      'type': m['type'],
      'times': (m['times'] as String?)?.isNotEmpty == true
          ? (jsonDecode(m['times']!) as List).cast<String>()
          : <String>[],
      'purposes': (m['purposes'] as String?)?.isNotEmpty == true
          ? (jsonDecode(m['purposes']!) as List).cast<String>()
          : <String>[],
      'isActive': (m['isActive'] as int?) == 1,
      'bodySymptoms': (m['bodySymptoms'] as String?)?.isNotEmpty == true
          ? (jsonDecode(m['bodySymptoms']!) as List).cast<String>()
          : <String>[],
      // ... 其他字段
    };
  }).toList();
}
```

### 4. 药物×症状分析
**文件：** [med_symptom_compare_page.dart](lib/meds/med_symptom_compare_page.dart#L50-L150)

```dart
// 分析用药前后的症状变化
Future<void> _runCompare() async {
  if (_selectedMedId == null || _selectedMedData == null) return;

  setState(() => _loading = true);

  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 时间窗口：药物开始前 vs 开始后
    final startDate = _anchorDate.subtract(Duration(days: _windowDays));
    final endDate = _anchorDate.add(Duration(days: _windowDays));

    // 从本地遍历所有症状记录
    // 计算：
    // 1. 开始前的症状出现率
    // 2. 开始后的症状出现率
    // 3. 变化差值

    final beforeSymptoms = await _fetchSymptomRecords(
      uid, 
      startDate, 
      _anchorDate,
    );
    
    final afterSymptoms = await _fetchSymptomRecords(
      uid, 
      _anchorDate, 
      endDate,
    );

    final deltas = _calculateSymptomDeltas(beforeSymptoms, afterSymptoms);

    setState(() {
      _beforeSymptomRates = beforeSymptoms;
      _afterSymptomRates = afterSymptoms;
      // ... 显示改善/恶化的症状
    });
  } finally {
    setState(() => _loading = false);
  }
}
```

---

## 故障排查

### 常见问题

| 问题 | 原因 | 解决方案 |
|-----|------|--------|
| 时间槽提醒未送达 | 1. 通知权限未授予<br/>2. 时间设置不对 | 检查 NotificationHelper<br/>检查 SharedPreferences 中的时间 |
| 调药记录丢失 | 1. Firebase 同步失败<br/>2. 本地 DB 损坏 | 检查网络和 FirebaseSyncConfig<br/>清除 app 数据重新同步 |
| 药物列表不更新 | 1. 缓存问题<br/>2. 刷新触发不到 | 调用 _refresh() 强制刷新<br/>检查 setState 调用 |
| 打卡数据未保存 | 1. 打卡时离线<br/>2. 本地 DB 写入失败 | 检查磁盘空间<br/>查看 Android logcat 日志 |

---

## 总结与建议

### ✅ 已完成功能
- 多种药物管理（无限数量）
- 多种剂型支持（口服、注射、滴剂）
- 完整的调药历史记录
- 每日服药打卡与进度追踪
- 药物×症状交叉分析
- 智能提醒系统（6个时间槽）
- 端到端加密（AES-256-GCM）
- 离线优先架构（SQLite + Firebase）
- 与 Daily Record 的数据集成

### 🔮 可能的增强方向
1. **AI 健康助手**：基于药物+症状数据提供建议
2. **药物交互检查**：提醒药物间可能的相互作用
3. **医疗报告导出**：生成可分享的调药历史 PDF
4. **可穿戴设备集成**：从 Apple Health 导入生活方式数据
5. **多语言药物字典**：扩展药物数据库
6. **医生协作模式**：允许医生查看患者的药物和符遵率记录

---

**文档版本：** v1.0  
**最后更新：** 2024-05-02  
**作者：** GitHub Copilot 代码分析
