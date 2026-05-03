# 药物记录功能 - 快速参考指南

## 📑 文件位置快速索引

### 核心页面
- **[medication_home_page.dart](lib/meds/medication_home_page.dart)** - 药物列表首页
- **[add_medication_page.dart](lib/meds/add_medication_page.dart)** - 新增药物（700+行，最复杂）
- **[edit_medication_page.dart](lib/meds/edit_medication_page.dart)** - 编辑药物
- **[record_adjustment_page.dart](lib/meds/record_adjustment_page.dart)** - 回诊调药（最重要的功能）
- **[medication_checkin_page.dart](lib/meds/medication_checkin_page.dart)** - 日常打卡追踪

### 数据与服务
- **[medication_local_db.dart](lib/meds/medication_local_db.dart)** - SQLite 数据库（v4架构）
- **[medication_reminder_service.dart](lib/meds/medication_reminder_service.dart)** - 通知提醒系统
- **[medication_actions.dart](lib/meds/medication_actions.dart)** - 业务逻辑操作
- **[drug_dictionary_service.dart](lib/meds/drug_dictionary_service.dart)** - 药物搜索字典

### 分析工具
- **[med_symptom_compare_page.dart](lib/meds/med_symptom_compare_page.dart)** - 药物×症状交叉分析
- **[med_adjustment_timeline.dart](lib/meds/med_adjustment_timeline.dart)** - 调药历史时间线
- **[record_adjustment_history_page.dart](lib/meds/record_adjustment_history_page.dart)** - 调药历史详情

---

## 🔑 关键数据结构

### 药物对象 (Medication)
```dart
{
  'id': String,                    // Firebase doc ID
  'uid': String,                   // User ID
  'name': String,                  // 中文名
  'dose': double,                  // 最终剂量（计算得出）
  'unit': String,                  // mg / mL / 等
  'type': String,                  // 'tablet' / 'injection' / 'drops'
  'times': List<String>,           // ['早上', '晚上', ...]
  'purposes': List<String>,        // ['安眠药', '抗焦虑', ...]
  'isActive': bool,                // true 使用中 / false 已停用
  'startDate': String,             // 'YYYY-MM-DD'
  'bodySymptoms': List<String>,    // 身体症状
  'note': String,                  // 备注
  'createdAt': String,
  'updatedAt': String,
  'lastChangeAt': String,          // 最后调整日期
  
  // 口服药特定
  'dosePerUnit': double,           // 每颗/mL的剂量
  'pillCount': double,             // 每次几颗
  
  // 滴剂特定
  'concentrationMg': double,
  'concentrationMl': double,
  'intakeMl': double,
  
  // 针剂特定
  'intervalDays': int              // 间隔天数
}
```

### 调药记录单项 (MedAdjustment Item)
```dart
{
  'medDocId': String,              // 药物ID
  'name': String,
  'type': String,                  // 'added', 'doseChanged', 'scheduleChanged', 
                                   // 'stopped', 'injected', 'unchanged'
  'oldDose': double?,
  'newDose': double?,
  'oldTimes': List<String>?,
  'newTimes': List<String>?,
  'unit': String,
  'stopReason': String?
}
```

---

## 🎯 常用操作代码片段

### 1. 获取用户的所有药物
```dart
final uid = FirebaseAuth.instance.currentUser?.uid;
final meds = await MedicationLocalDB().getMedicationsForDisplay(uid);
// meds 是 List<Map<String, dynamic>>
```

### 2. 获取激活的口服药（用于生成打卡列表）
```dart
final activeOralMeds = meds.where((m) {
  final isActive = (m['isActive'] as bool?) ?? true;
  final isInjection = (m['type'] as String?) == 'injection';
  return isActive && !isInjection;
}).toList();
```

### 3. 计算最终剂量（口服药）
```dart
final dosePerUnit = _dosePerUnit;  // 每颗 mg
final pillCount = _pillCount;      // 每次几颗
final dose = dosePerUnit * pillCount;  // 最终: 25 * 2 = 50mg
```

### 4. 计算最终剂量（滴剂）
```dart
final concentrationMg = _dropMg;   // 浓度 2mg
final concentrationMl = _dropMlBase; // 在 10mL 中
final intakeMl = _intakeMl;        // 每次取 5mL
final dose = (concentrationMg / concentrationMl) * intakeMl;  // 1mg
```

### 5. 重建服药提醒
```dart
await MedicationReminderService.syncDailyRemindersForActiveMeds();
// 返回建立的提醒数量
```

### 6. 激活/停用药物
```dart
// 停用
await MedicationLocalDB().updateMedicationStatus(
  uid, medId,
  isActive: false,
  updatedAt: DateTime.now().toString(),
);

// 同时更新 Firebase（如启用同步）
if (FirebaseSyncConfig.shouldSync()) {
  await FirebaseFirestore.instance
      .collection('users').doc(uid)
      .collection('medications').doc(medId)
      .set({'isActive': false, 'updatedAt': FieldValue.serverTimestamp()}, 
            SetOptions(merge: true));
}

// 重建提醒
await MedicationReminderService.syncDailyRemindersForActiveMeds();
```

### 7. 保存调药记录
```dart
final adjData = {
  'date': Timestamp.fromDate(adjDateTime),
  'note': userNote,
  'items': [
    {
      'medDocId': medId,
      'type': 'doseChanged',
      'oldDose': 50,
      'newDose': 75,
      'newTimes': ['早上', '晚上'],
    }
  ],
  'createdAt': FieldValue.serverTimestamp(),
};

// 1. 保存到本地
await MedicationLocalDB().addAdjustmentRecord(uid, adjId, adjData);

// 2. 保存到 Firebase
await FirebaseFirestore.instance
    .collection('users').doc(uid)
    .collection('medAdjustments').doc(adjId)
    .set(adjData);

// 3. 更新药物主档
batch.set(medRef, {...}, SetOptions(merge: true));
await batch.commit();

// 4. 重建提醒
await MedicationReminderService.syncDailyRemindersForActiveMeds();
```

---

## 📊 时间槽配置

```dart
// 默认提醒时间
final kSlotTimes = {
  '早上': TimeOfDay(hour: 8, minute: 0),              // 08:00
  '中午': TimeOfDay(hour: 12, minute: 30),            // 12:30
  '下午': TimeOfDay(hour: 18, minute: 0),             // 18:00
  '晚上': TimeOfDay(hour: 20, minute: 0),             // 20:00
  '睡前': TimeOfDay(hour: 22, minute: 30),            // 22:30
  // '需要時' 无固定时间
};

// 通知 ID（用于取消/更新）
final _slotNotificationIds = {
  '早上': 21101,
  '中午': 21102,
  '下午': 21103,
  '晚上': 21104,
  '睡前': 21105,
};
```

---

## 🔍 查询示例

### 查询用户的所有调药记录
```dart
final snap = await FirebaseFirestore.instance
    .collection('users').doc(uid)
    .collection('medAdjustments')
    .orderBy('date', descending: true)
    .limit(50)
    .get();

for (var doc in snap.docs) {
  final date = doc['date'];  // Timestamp
  final items = doc['items'];  // List
  final note = doc['note'];    // String
}
```

### 查询特定日期的打卡记录
```dart
final docId = '20240502';  // YYYYMMDD
final snap = await FirebaseFirestore.instance
    .collection('users').doc(uid)
    .collection('medicationCheckins')
    .doc(docId)
    .get();

if (snap.exists) {
  final checks = snap['checks'];  // Map<String, bool>
  final statuses = snap['statuses'];  // Map<String, String>
}
```

---

## ⚙️ 配置关键点

### Firebase 同步开关
```dart
// lib/utils/firebase_sync_config.dart
if (FirebaseSyncConfig.shouldSync()) {
  // 进行 Firebase 同步和加密
} else {
  // 纯本地离线模式
}
```

### 加密密钥管理
```dart
// 获取或生成密钥
final key = await SecureStorageService.getOrRecoverKey();
if (key != null) {
  final encService = EncryptionService(key);
  final encrypted = encService.encryptData(plainText);
}
```

---

## 🚨 常见陷阱

### 1. 忘记更新本地数据库后再上传 Firebase
❌ 错误：
```dart
// 只上传 Firebase
await firestore.set(data);
// UI 读本地 DB，数据未更新！
```

✅ 正确：
```dart
// 1. 本地优先
await MedicationLocalDB().addMedication(uid, data);

// 2. 后台 Firebase（失败不阻滞）
if (FirebaseSyncConfig.shouldSync()) {
  firestore.set(data);
}
```

### 2. 调整药物后忘记重建提醒
❌ 错误：
```dart
// 修改了药物时间或停用
await db.updateMedication(...);
// 但提醒没更新，用户还收到旧提醒
```

✅ 正确：
```dart
await db.updateMedication(...);
// 必须
await MedicationReminderService.syncDailyRemindersForActiveMeds();
```

### 3. 打卡记录用错 key 格式
❌ 错误：
```dart
final key = 'med-abc-123_morning';  // 随意格式
_checks[key] = true;
```

✅ 正确：
```dart
final key = '$medId::早上';  // 固定格式: medId::slot
_checks[key] = true;
```

### 4. 调药记录没有保存到本地 DB
❌ 错误：
```dart
// 只保存到 Firebase
batch.set(adjRef, adjData);
await batch.commit();
// 离线时读计历史无数据
```

✅ 正确：
```dart
// 1. 本地先存
await MedicationLocalDB().addAdjustmentRecord(uid, adjId, adjData);

// 2. 再 Firebase
if (FirebaseSyncConfig.shouldSync()) {
  batch.set(adjRef, adjData);
  await batch.commit();
}
```

---

## 📋 测试检查清单

### 新增药物测试
- [ ] 口服药：输入每颗剂量和数量，验证计算正确
- [ ] 滴剂：输入浓度和摄取量，验证计算正确
- [ ] 针剂：输入间隔天数，无时间槽
- [ ] 设置多个时间槽（早/晚）
- [ ] 添加用途和身体症状
- [ ] 本地保存（断网情况）
- [ ] Firebase 同步（有网情况）
- [ ] 药物字典搜索建议工作

### 调药记录测试
- [ ] 选择有效的回诊日期
- [ ] 标记劑量調整并输入新值
- [ ] 标记時間調整并选择新时段
- [ ] 标记停藥并输入原因
- [ ] 新增本次新开的药物
- [ ] 输入调药备注
- [ ] 验证本地 DB 记录
- [ ] 验证 Firebase 同步
- [ ] 验证药物列表已更新
- [ ] 验证提醒已重建

### 服药打卡测试
- [ ] 日常生成正确的打卡项目
- [ ] 状态切换（待打卡/已服用/跳过）
- [ ] 修改药物用量
- [ ] PRN 药物多次记录
- [ ] 7天和30天统计准确
- [ ] 图表显示趋势

### 提醒测试
- [ ] 激活药物时自动生成提醒
- [ ] 停用药物时提醒被移除
- [ ] 自定义时间槽时提醒更新
- [ ] 时间槽提醒在正确的时刻发送
- [ ] 通知内容列出该时段的所有药物

### 加密测试
- [ ] 如果启用加密，数据在 Firebase 中应为密文
- [ ] 解密后能正确显示
- [ ] 密钥丢失时有恢复流程
- [ ] 其他用户无法看到加密数据

---

## 📞 常见问题排除

### 问题：提醒没有发送
1. 检查 NotificationHelper 是否初始化
2. 检查系统通知权限
3. 检查 SharedPreferences 中的时间设置
4. 调用 `syncDailyRemindersForActiveMeds()` 重建
5. 查看 logcat 日志

### 问题：调药记录丢失
1. 检查网络和 Firebase 连接
2. 查看本地 SQLite 数据库是否存在
3. 确认 uid 正确
4. 检查 Firebase 规则（collection 权限）
5. 手动调用刷新：`_refresh()` 或 `setState()`

### 问题：药物列表不更新
1. 调用 `setState(() {})` 或 `_refresh()`
2. 检查 FutureBuilder/StreamBuilder 是否正确绑定
3. 查看是否有异常捕获的错误
4. 清除本地缓存重试

### 问题：打卡数据保存失败
1. 检查磁盘空间（SQLite）
2. 验证 UID 有效
3. 检查 Firebase 写入权限
4. 查看离线/网络状态
5. 查看 logcat 的具体错误信息

---

## 🔗 与其他模块的集成

### Daily Record 集成
- 药物信息存储在 `dailyRecord.medication` 字段
- 睡眠记录中有 `tookHypnotic` / `hypnoticName` / `hypnoticDose`
- AI 反思会考虑药物数据进行分析

### 症状模块集成
- `med_symptom_compare_page.dart` 关联症状数据
- 分析一段时间内的症状变化并与药物相关联
- 可视化显示改善/恶化的症状

### 通知模块集成
- 使用 `NotificationHelper` 推送本地通知
- notification IDs: 21101-21105 以及 21000+ 范围

---

## 📚 参考资源

### 核心依赖
- `sqflite` - SQLite 数据库
- `cloud_firestore` - Firebase 数据存储
- `firebase_auth` - 用户认证
- `flutter_local_notifications` - 本地通知
- `shared_preferences` - 轻量级存储
- `fl_chart` - 统计图表
- `encrypt` - 数据加密

### 关键类
- `MedicationLocalDB` - 数据库操作单例
- `MedicationReminderService` - 提醒管理单例
- `DrugDictionaryService` - 药物字典单例
- `EncryptionService` - 加密服务
- `SecureStorageService` - 安全存储
- `FirebaseSyncConfig` - 同步配置

---

**快速参考版本：** v1.0  
**最后更新：** 2024-05-02  
**用途：** IDE 旁边快速查看
