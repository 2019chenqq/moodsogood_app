# 药物记录功能 - 架构图与流程图

## 📊 系统架构图

### 系统全景图

```
┌─────────────────────────────────────────────────────────────────────┐
│                        MoodsOGood 应用 (Flutter)                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  🎨 表现层 (Presentation Layer)                                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │                                                            │   │
│  │  medication_home_page.dart                                │   │
│  │  ├─ 显示药物列表（按状态分页）                           │   │
│  │  ├─ 激活状态切换                                         │   │
│  │  ├─ 浮点按钮 → 新增/调整等操作                          │   │
│  │  │                                                        │   │
│  │  add_medication_page.dart                                 │   │
│  │  ├─ 多步骤表单（药名、剂量、用途等）                    │   │
│  │  ├─ 动态字段（根据药物形式）                            │   │
│  │  ├─ 实时药物搜索建议                                    │   │
│  │  │                                                        │   │
│  │  record_adjustment_page.dart                              │   │
│  │  ├─ 选择回诊日期                                        │   │
│  │  ├─ 逐个药物标注变动类型                                │   │
│  │  ├─ 劇量/时间/停药编辑器                                │   │
│  │  │                                                        │   │
│  │  medication_checkin_page.dart                             │   │
│  │  ├─ 生成日记录表格（药物 × 时间槽）                    │   │
│  │  ├─ 打卡状态管理（已服/跳过/改用量）                   │   │
│  │  ├─ 周期统计（7/30天遵循率）                            │   │
│  │  │                                                        │   │
│  │  med_symptom_compare_page.dart                            │   │
│  │  └─ 药物前后症状对比分析                                │   │
│  │                                                            │   │
│  └────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│  🔧 业务逻辑层 (Business Logic Layer)                             │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │                                                            │   │
│  │  medication_actions.dart                                   │   │
│  │  ├─ showMedicationMoreSheet()             [编辑/停用/删除] │   │
│  │  ├─ _deactivateMedication()               [停用逻辑]      │   │
│  │  ├─ _activateMedication()                 [恢复逻辑]      │   │
│  │  ├─ _deleteMedication()                   [删除逻辑]      │   │
│  │                                                            │   │
│  │  medication_reminder_service.dart                          │   │
│  │  ├─ syncDailyRemindersForActiveMeds()     [重建所有提醒]  │   │
│  │  ├─ getSlotTime(slot)                     [获取通知时间]  │   │
│  │  ├─ setSlotTime(slot, time)               [保存用户时间]  │   │
│  │  │   └─> NotificationHelper.scheduleNotification()        │   │
│  │  │                                                         │   │
│  │  drug_dictionary_service.dart                              │   │
│  │  ├─ suggest(input)                        [搜索建议]      │   │
│  │  ├─ _loadUserDictionary()                 [加载个人字典]  │   │
│  │  ├─ saveUserMapping(zh, en)               [保存映射]      │   │
│  │  │                                                         │   │
│  └────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│  💾 数据访问层 (Data Access Layer)                                │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │                                                            │   │
│  │  MedicationLocalDB (SQLite 数据库)                         │   │
│  │  ├─ addMedication()                       [新增药物]      │   │
│  │  ├─ getMedication(uid, docId)             [获取单个]      │   │
│  │  ├─ getMedicationsForDisplay()            [获取列表]      │   │
│  │  ├─ updateMedication()                    [更新药物]      │   │
│  │  ├─ updateMedicationStatus()              [更新状态]      │   │
│  │  ├─ deleteMedication()                    [删除药物]      │   │
│  │  ├─ addAdjustmentRecord()                 [新增调整记录]  │   │
│  │  ├─ getAdjustmentRecords()                [查询调整历史]  │   │
│  │  │                                                         │   │
│  │  Firebase Operations (Firestore/Storage)                   │   │
│  │  ├─ users/{uid}/medications/{}            [药物集合]      │   │
│  │  ├─ users/{uid}/medAdjustments/{}         [调整记录]      │   │
│  │  ├─ users/{uid}/medicationCheckins/{}     [打卡记录]      │   │
│  │  ├─ users/{uid}/drugDictionary/{}         [个人字典]      │   │
│  │                                                            │   │
│  └────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│  🔐 存储层 (Storage Layer)                                       │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │                                                            │   │
│  │  Local Storage                                             │   │
│  │  ├─ SQLite: ~/databases/medications.db                    │   │
│  │  │   ├─ medications (主表)                                │   │
│  │  │   └─ medAdjustments (调整记录)                         │   │
│  │  │                                                        │   │
│  │  ├─ SharedPreferences                                     │   │
│  │  │   ├─ med_reminder_{slot}_time                         │   │
│  │  │   └─ 其他配置                                         │   │
│  │  │                                                        │   │
│  │  ├─ SecureStorage (FlutterSecureStorage)                 │   │
│  │  │   └─ AES 加密密钥 (256-bit)                           │   │
│  │  │                                                        │   │
│  │  Cloud Storage (Firebase)                                 │   │
│  │  ├─ Firestore: 用户数据（同步副本）                      │   │
│  │  ├─ Cloud Functions: 可选的服务器逻辑                     │   │
│  │  └─ Cloud Storage: 可选的 PDF 导出                        │   │
│  │                                                            │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 📈 完整数据流

### 1️⃣ 新增药物 - 完整流程

```
┌─────────────┐
│ 用户点击    │
│ "新增药物"  │
└──────┬──────┘
       │
       ▼
┌──────────────────────────┐
│ 1. UI 表单验证           │
│  - 药名非空              │
│  - 剂量合理（0-300）     │
│  - 生成最终计算剂量      │
│  - 选择剂型              │
└──────────┬───────────────┘
           │
           ▼
┌──────────────────────────┐
│ 2. 生成唯一 ID           │
│  - Firebase 自动生成    │
│  - docId 作为主键        │
└──────────┬───────────────┘
           │
           ▼
┌──────────────────────────┐
│ 3. 构建药物对象          │
│  {                       │
│    id: docId,            │
│    uid: currentUser.uid, │
│    name, dose,           │
│    times, purposes,      │
│    type, isActive,       │
│    createdAt,            │
│    ...                   │
│  }                       │
└──────────┬───────────────┘
           │
    ┌──────┴──────┬──────────┐
    │             │          │
    ▼             ▼          ▼
  本地          Firebase   提醒
   写入         同步       系统

【3A】本地 SQLite     【3B】Firebase 同步  【3C】提醒更新
┌──────────────────┐ ┌────────────────┐  ┌──────────────┐
│ 1. 打开 DB       │ │ 1. 检查配置    │  │ 1. 扫描所有  │
│ 2. INSERT        │ │    shouldSync   │  │    激活药物  │
│    medications   │ │ 2. IF true:     │  │ 2. 按时间槽  │
│ 3. 提交事务      │ │    .set()       │  │    分组      │
│ 4. 立即返回成功  │ │ 3. 设置        │  │ 3. 为每个    │
│ ✅ 无需网络     │ │    merge: true   │  │    时段建立  │
│                   │ │ 📍 后台进行     │  │    通知      │
│                   │ │ ⚠️ 失败不阻滞   │  │ 4. 推送 OS   │
│                   │ └────────────────┘  │ ✅ 立即生效  │
└──────────────────┘                      └──────────────┘
       │                                        │
       └────────────┬─────────────┬─────────────┘
                    │             │
                    ▼             ▼
           ┌──────────────────────────┐
           │ 4. 返回成功到 UI         │
           │ ScaffoldMessenger        │
           │ SnackBar: "已新增药物"   │
           │                          │
           │ 5. 刷新列表              │
           │ setState() 或刷新 stream │
           └──────────┬───────────────┘
                      │
                      ▼
              ┌────────────────┐
              │ 药物显示在列表 │
              │ 可进行后续操作 │
              └────────────────┘
```

### 2️⃣ 回诊调药 - 完整流程

```
┌──────────────────────┐
│ 用户打开             │
│ "紀錄調整"頁面       │
└──────────┬───────────┘
           │
           ▼
┌────────────────────────────────────┐
│ 1. 加载所有激活的药物               │
│    from MedicationLocalDB           │
│ ✅ 本地优先（快速显示）             │
│ 📱 背景同步 Firebase（刷新）        │
└──────┬─────────────────────────────┘
       │
       ▼
┌────────────────────────────────────┐
│ 2. 选择回诊日期（预设今天）        │
│    → DatePicker                     │
│    → 保存到 _date                   │
└──────┬─────────────────────────────┘
       │
       ▼
┌────────────────────────────────────┐
│ 3. UI 初始化调整草稿 (_MedDraft)  │
│    对每个药物:                      │
│    - 复制原剂量/时间                │
│    - 设置 type = unchanged          │
│    - 准备编辑界面                   │
└──────┬─────────────────────────────┘
       │
       ▼
┌────────────────────────────────────┐
│ 4. 用户逐个标注变动 (循环)         │
│                                    │
│ 对每个药物:                        │
│ ┌──────────────────────────────┐   │
│ │ 选择变动类型:                 │   │
│ │ a) 🔁 維持原劑量             │   │
│ │    → type = unchanged         │   │
│ │    → 无需编辑                 │   │
│ │                              │   │
│ │ b) 📝 劑量調整              │   │
│ │    → type = doseChanged       │   │
│ │    → 弹出编辑框输入新剂量    │   │
│ │    → 验证 (0-300)            │   │
│ │                              │   │
│ │ c) ⏰ 時間調整              │   │
│ │    → type = scheduleChanged   │   │
│ │    → 弹出 FilterChip 多选     │   │
│ │    → 选择新时间段            │   │
│ │                              │   │
│ │ d) 💊 已施打 (仅针剂)       │   │
│ │    → type = injected          │   │
│ │                              │   │
│ │ e) ❌ 停藥                  │   │
│ │    → type = stopped           │   │
│ │    → 可选输入停药原因        │   │
│ │                              │   │
│ │ ➕ 新增本次新開的藥          │   │
│ │    → 再调用 AddMedicationPage │   │
│ │    → 返回后自动标记为 added  │   │
│ └──────────────────────────────┘   │
│                                    │
│ 更新草稿 (_draftByDocId)          │
└──────┬─────────────────────────────┘
       │
       ▼
┌────────────────────────────────────┐
│ 5. 输入本次调药备註（可选）        │
│    _noteCtrl.text                   │
│    例："醫生建議停用 A，加強 B"   │
└──────┬─────────────────────────────┘
       │
       ▼
┌────────────────────────────────────┐
│ 6️⃣ 点击"儲存"按钮                │
│    → 调用 _save(uid)               │
└──────┬─────────────────────────────┘
       │
       │ ┌─ 验证 ─────────────────┐
       │ │ ☑️ 至少一个药物有变动 │
       │ │ ☑️ 劑量調整要有新值  │
       │ └────────────────────────┘
       │
       ▼
┌────────────────────────────────┐
│ 📝 Step 1: 保存本地调整记录    │
│                                │
│ medAdjustments {               │
│   id: 自動生成,                │
│   uid: currentUser.uid,        │
│   date: '2024/05/02',         │
│   note: 用户输入,              │
│   items: [                     │
│     {                          │
│       medDocId: 'abc123',      │
│       type: 'doseChanged',    │
│       oldDose: 50,             │
│       newDose: 75,             │
│       newTimes:['早上','晚上']│
│     },                         │
│     ...                        │
│   ],                           │
│   createdAt: now               │
│ }                              │
│                                │
│ MedicationLocalDB.             │
│ addAdjustmentRecord()          │
│ ✅ 本地優先完成               │
└─────────┬──────────────────────┘
          │
          ▼
┌────────────────────────────────┐
│ 🔥 Step 2: Firebase 同步       │
│ (背景/异步)                   │
│                                │
│ IF FirebaseSyncConfig.         │
│    shouldSync() ==true:        │
│                                │
│  - /users/{uid}/               │
│    medAdjustments/{adjId}      │
│    .set(adjData)               │
│                                │
│  ⚠️ 失败不会阻滞 UI           │
└─────────┬──────────────────────┘
          │
          ▼
┌────────────────────────────────┐
│ 🔄 Step 3: 更新药物主档        │
│ (batch 操作)                   │
│                                │
│ 对每个有变动的药物:            │
│  .set({                        │
│    dose: 新值,                 │
│    times: 新值,                │
│    isActive: true/false,       │
│    updatedAt: 时间戳,          │
│    lastChangeAt: 日期,         │
│  }, merge: true)               │
│                                │
│ + 本地 DB 也要同步这些变动      │
└─────────┬──────────────────────┘
          │
          ▼
┌────────────────────────────────┐
│ 🔔 Step 4: 重建服藥提醒        │
│                                │
│ MedicationReminderService.     │
│ syncDailyRemindersForActiveMeds()
│                                │
│ 流程:                          │
│ 1️⃣ 扫描所有激活的口服药        │
│ 2️⃣ 按时间槽分组                │
│ 3️⃣ 为每个时段设置提醒          │
│ 4️⃣ 停用药物的提醒被删除        │
│ 5️⃣ 新增/调整的立即生效        │
│                                │
│ ✅ 立即在手机上可见新提醒      │
└─────────┬──────────────────────┘
          │
          ▼
┌────────────────────────────────┐
│ ✅ 一切完成                     │
│                                │
│ ScaffoldMessenger.showSnackBar: │
│ "已儲存本次調整"               │
│                                │
│ Navigator.pop(context, true)   │
│ → 返回药物列表                 │
│ → 列表自动刷新                 │
└────────────────────────────────┘
```

### 3️⃣ 每日服药打卡 - 流程

```
┌──────────────────────┐
│ 用户打开             │
│ "服藥打卡"頁面       │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────────────────────────┐
│ 1. 確定今天日期                          │
│    _selectedDate = DateTime.now()        │
│    → docId = YYYYMMDD 格式               │
└──────────┬───────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────┐
│ 2. 從本地 DB 加載所有激活的口服藥       │
│    getMedicationsForDisplay()            │
│    → 过滤: isActive == true && type != injection
│    → 构建 _items 列表                    │
│                                          │
│    构建算法:                             │
│    for med in activeMeds {               │
│      if med.times.isEmpty {              │
│        添加一个 _CheckinItem             │
│        slot = "未設定"                  │
│      } else {                            │
│        for slot in med.times {           │
│          创建 _CheckinItem 对象:        │
│          {                              │
│            medId: med.id                │
│            medName: med.name             │
│            slot: slot                   │
│            plannedAmount: med.dose      │
│          }                              │
│        }                                │
│      }                                  │
│    }                                    │
└──────────┬───────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────┐
│ 3. 尝试从 Firestore 加載今日打卡記錄    │
│    medicationCheckins/{YYYYMMDD}        │
│                                          │
│    加载字段:                             │
│    - checks: {key: bool}                │
│    - statuses: {key: 'pending'|...}    │
│    - statusAt: {key: Timestamp}         │
│    - actualAmounts: {key: double}       │
│    - prnEvents: {key: [Timestamp]}      │
│                                          │
│    ✅ 恢复之前的打卡进度                │
└──────────┬───────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────┐
│ 4. 渲染打卡 UI                           │
│    按时间槽分组显示:                    │
│                                          │
│    ┌─ 早上 ────────────┐                │
│    │ ☐ 克癇平 50mg    │                │
│    │ ☐ 思樂康 200mg   │                │
│    │ ✅ 艾司唑仑 1mg   │ (已按下)       │
│    └───────────────────┘                │
│    ┌─ 晚上 ────────────┐                │
│    │ ☑️ 克癇平 50mg    │ (勾选状态)    │
│    │ ☑️ 思樂康 200mg   │                │
│    └───────────────────┘                │
│    ┌─ 睡前 ────────────┐                │
│    │ ◉ 或許 (PRN)      │ (radio等待)   │
│    └───────────────────┘                │
└──────────┬───────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────┐
│ 5. 用户交互 (循环)                       │
│                                          │
│ 对每个 CheckinItem:                     │
│ a) 点击打卡按钮                          │
│    → 状态来回切换:                      │
│       pending → taken → skipped → ...    │
│                                         │
│ b) 长按修改用量                          │
│    → 弹出输入框                         │
│    → 输入实际服用量 (double)            │
│    → 保存到 actualAmounts                │
│                                         │
│ c) PRN 药物特殊处理                      │
│    → 记录每次用量时刻                   │
│    → 可多次打卡                         │
│    → 在 prnEvents 中累积                 │
└──────────┬───────────────────────────────┘
           │
           ▼
┌────────────────────────────────────────────┐
│ 6️⃣ 状态改變時: 即時保存到 Firestore      │
│                                            │
│ 每次點擊立即調用:                         │
│ Firestore.set({                           │
│   checks: _updatedChecks,                │
│   statuses: _updatedStatuses,            │
│   statusAt: {                            │
│     'key': Timestamp.now()               │
│   },                                     │
│   actualAmounts: _updatedActual,         │
│   prnEvents: _updatedPrn,                │
│ }, SetOptions(merge: true))              │
│                                            │
│ ✅ 實時保存，無需主動按"保存"            │
└────────────┬─────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────┐
│ 7. 定期計算統計數據                        │
│    (每次加載頁面或狀態變化)              │
│                                            │
│ 計算週期:                                 │
│ - 7天遵循率 (過去7天完成度%)             │
│ - 30天遵循率                             │
│ - 連續完成天數                           │
│ - 最常遺漏的時段                         │
│ - 每個藥物的個別遵循率                   │
│                                            │
│ 算法示例（7天遵循率）:                   │
│ totalDays = 7                            │
│ expectedDoses = totalDays * slotCount   │
│ completedDoses = count(checks==true)    │
│ rate = completedDoses / expectedDoses   │
│ × 100%                                  │
└────────────┬─────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────┐
│ 8. 顯示多維度統計圖表 (fl_chart)         │
│                                            │
│ ├─ 折線圖: 日均遵循率趨勢                 │
│ ├─ 柱狀圖: 時段打卡數量                   │
│ ├─ 圓餅圖: 藥物遵循率分佈                 │
│ └─ KPI: 連續完成天數、最常遺漏藥物      │
│                                            │
│ ✅ 視覺化激勵用戶堅持定時服用             │
└────────────────────────────────────────────┘
```

---

## 🔐 数据加密流程

```
┌──────────────────────┐
│ 用户登录             │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 1. 密钥管理                      │
│                                  │
│ 首次登录:                        │
│ a) 生成新密钥 (256-bit AES)     │
│ b) 保存到 SecureStorage          │
│ c) 生成验证器 (作为检验)        │
│ d) 上传验证器到 Firebase         │
│                                  │
│ 非首次登录:                      │
│ a) 从 SecureStorage 读取密钥     │
│ b) 验证密钥有效性                │
│ c) 若失效→恢复流程              │
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 2. 创建 EncryptionService        │
│    instance = EncryptionService  │
│    (key)                         │
│                                  │
│ 暴露方法:                        │
│ - encryptData(plainText)         │
│ - decryptData(cipherText)        │
│ - tryDecryptData()               │
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 3. 加密過程 (保存時)            │
│                                  │
│ userInput = "克癇平 25mg"       │
│      │                          │
│      ▼                          │
│ 生成隨機 IV (16 bytes) ◄──┐     │
│      │                    │     │
│      ▼                    │     │
│ AES-256-GCM 加密          │     │
│      │                    │     │
│      ▼                    │     │
│ (Ciphertext, Tag)         │     │
│      │                    │     │
│      ▼                    │     │
│ 序列化:                   │     │
│ "IV(B64):Cipher(B64)"     │     │
│      │                    │     │
│      ▼                    │     │
│ 上傳到 Firebase (密文)    │     │
│                          └─────┘
│ ✅ 服務器無法讀取             │
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 4. 解密過程 (顯示時)            │
│                                  │
│ 從 Firebase 下載:                │
│ "IV(B64):Cipher(B64)"           │
│      │                          │
│      ▼                          │
│ 分離 IV 和密文                   │
│      │                          │
│      ├─ IV.fromBase64()         │
│      └─ Cipher.fromBase64()     │
│      │                          │
│      ▼                          │
│ 從 SecureStorage 取出密鑰        │
│      │                          │
│      ▼                          │
│ AES-256-GCM 解密                 │
│      │                          │
│      ▼                          │
│ plainText = "克癇平 25mg"       │
│      │                          │
│      ▼                          │
│ 顯示在 UI                        │
│ ✅ 端到端加密                    │
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 5. 密钥恢复 (如果丢失)          │
│                                  │
│ IF 本地密钥找不到:               │
│  → 尝试从 Firebase 恢复         │
│  → encryptionSalt + 用户密码    │
│  → PBKDF2 派生相同密钥         │
│  → 验证解密某个数据集            │
│  → 重新保存到 SecureStorage      │
│                                  │
│ ⚠️ 如果都失败:                  │
│  → 数据仍加密但无法访问          │
│  → 用户可选择清除或恢复          │
└──────────────────────────────────┘
```

---

## 📊 药物×症状分析流程

```
┌──────────────────────────────┐
│ 用户选择药物进行分析         │
└──────────┬──────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 1. 选择分析范围                  │
│                                  │
│ - 症状对比的时间窗口:           │
│   a) 前: -windowDays 天          │
│   b) 中心: 药物开始日期 (锚点)  │
│   c) 后: +windowDays 天          │
│                                  │
│ 例如:                            │
│ 选择"克癇平"(2024-03-01 开始) │
│ windowDays = 7                   │
│ → 分析 2024-02-23 ~ 2024-03-08  │
│                                  │
│ 3 个区间:                        │
│ ├─ BEFORE: 02-23 ~ 03-01        │
│ ├─ PIVOT: 03-01 (开始日期)      │
│ └─ AFTER: 03-01 ~ 03-08         │
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 2. 从 Daily Records 收集数据    │
│                                  │
│ 遍历日期范围内的每条日记:       │
│ dailyRecords                     │
│ .where(date in [before, after]) │
│ .get()                           │
│                                  │
│ 提取字段:                        │
│ - symptoms: [{name, severity}]  │
│ - emotions: [{name, value}]     │
│ - 其他数据                       │
│                                  │
│ 分别统计:                        │
│ - beforeSymptoms = {...}        │
│ - afterSymptoms = {...}         │
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 3. 计算症状发生率                │
│                                  │
│ beforeRate[symptom] =           │
│   count(days with symptom)      │
│   ÷ totalDays_before × 100%    │
│                                  │
│ afterRate[symptom] =            │
│   count(days with symptom)      │
│   ÷ totalDays_after × 100%     │
│                                  │
│ 例如:                            │
│ "头痛":                          │
│ - 前: 3/7 天 = 42.9%            │
│ - 后: 1/7 天 = 14.3%            │
│ - 改善!                          │
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 4. 计算变化三角 (Delta)          │
│                                  │
│ delta = afterRate - beforeRate   │
│                                  │
│ 分类:                            │
│ 🟢 改善 (improved):              │
│    delta < -10%                  │
│    例: 42.9% → 14.3% = -28.6%   │
│                                  │
│ 🔴 恶化 (worsened):              │
│    delta > +10%                  │
│                                  │
│ 🟡 轻微 (minor):                 │
│    -10% < delta < +10%           │
│                                  │
│ ⚪ 新出现 (newlyAppeared):       │
│    before = 0% && after > 0%    │
│    (药物可能引起的新症状)       │
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ 5. 展示分析结果                  │
│                                  │
│ ┌─ 改善的症状 ────────────────┐ │
│ │ 💚 头痛: 42.9% → 14.3%     │ │
│ │ 💚 焦虑: 71.4% → 42.9%     │ │
│ │ ... (共3项)                 │ │
│ └────────────────────────────┘ │
│ ┌─ 恶化的症状 ────────────────┐ │
│ │ 💔 手抖: 0% → 28.6%        │ │
│ │ (可能是药物副作用)         │ │
│ │ ... (共1项)                │ │
│ └────────────────────────────┘ │
│ ┌─ 轻微变化 ──────────────────┐ │
│ │ ⚪ 胸闷: 14.3% → 21.4%     │ │
│ │ ... (共2项)                │ │
│ └────────────────────────────┘ │
│                                  │
│ 顶部 KPI:                        │
│ - 整体改善症状数: 3 个          │
│ - 新增副作用: 1 个             │
│ - 療效評分: ★★★★☆ (4/5)      │
└──────────────────────────────────┘
```

---

## 🎨 UI 组件关系图

```
MedicationHomePage (主轴)
├─ _buildMedicationList()
│  └─ Card (循环)
│     ├─ 药物名称 + 剂量 + 状态徽章
│     ├─ 服用时间 (chip row)
│     ├─ 用途标签
│     └─ ActionButton (更多操作)
│        └─ showMedicationMoreSheet()
│           ├─ 编辑 → EditMedicationPage
│           ├─ 停用/恢复 → updateMedicationStatus()
│           └─ 删除 → confirDialog() → deleteMedication()
│
├─ TabBar (目前使用 / 已停用)
│  ├─ isActive == true → Tab 1
│  └─ isActive == false → Tab 2
│
├─ AppBar Actions
│  ├─ 服藥打卡 → MedicationCheckinPage
│  ├─ 症狀交叉 → MedSymptomComparePage
│  └─ 紀錄調整 → RecordAdjustmentPage
│
└─ FloatingActionButton
   └─ 新增 → AddMedicationPage

RecordAdjustmentPage (调药工作流)
├─ 日期选择器
├─ 备注输入框 (TextField)
│
├─ 药物卡片列表 (循环)
│  └─ _buildMedCard()
│     ├─ 药物名称 + 当前信息
│     ├─ 状态按钮 (ChoiceChip)
│     │  ├─ 维持原剂量
│     │  ├─ 劑量调整
│     │  ├─ 時間调整
│     │  └─ 停藥
│     │
│     └─ 条件编辑器 (取决于选择)
│        ├─ 新剂量输入 (AlertDialog)
│        ├─ 时间多选 (FilterChip)
│        └─ 停药理由 (TextField)
│
├─ 新增药物按钮 (FAB)
│  └─ AddMedicationPage
│
└─ 保存按钮
   └─ _save() → Firebase + LocalDB

MedicationCheckinPage (打卡工作台)
├─ 日期选择器
│
├─ 时间槽分组 (ExpansionTile)
│  └─ 早上
│     └─ CheckinItem (循环)
│        ├─ 状态按钮 (Radio/Checkbox)
│        │  ├─ ⭕ 待打卡
│        │  ├─ ✅ 已服用
│        │  ├─ ⏭️  跳过
│        │  └─ 🆘 改用量
│        │
│        └─ 长按修改用量
│
├─ 提醒设置 (可折叠板块)
│  └─ 时间选择 (ListTile → TimePicker)
│
├─ 统计面板
│  ├─ 周期选择 (Segment: 7天/30天)
│  ├─ 统计图表 (fl_chart)
│  │  ├─ LineChart (遵循率趋势)
│  │  ├─ BarChart (时段分布)
│  │  └─ PieChart (药物分布)
│  │
│  └─ KPI 卡片
│     ├─ 平均遵循率
│     ├─ 連續完成天數
│     └─ 最常遗漏时段

MedSymptomComparePage (交叉分析)
├─ 药物选择 (Dropdown)
├─ 时间窗口滑块
│
└─ 结果面板 (TabBar)
   ├─ 改善症状 (症状 + 百分比)
   ├─ 恶化症状 (标红警告)
   ├─ 情绪变化 (情绪数据)
   └─ 詳細統計表
```

---

## 🔄 同步与冲突解决

```
设备A                     设备B                 Firebase Firestore
(即时修改)               (后台同步)             (源数据)
  │                       │                        │
  ▼                       ▼                        ▼
┌─┐ 修改剂量             ┌─┐ 修改时间          ┌────┐
│A│ 50mg → 75mg        │B│ +"晚上"           │DB  │
└─┘                      └─┘                   └────┘
  │                       │                      │
  ├─> LocalDB保存      ├─> LocalDB保存        
  │   (v=1)             │   (v=1)    
  │                      │   
  ├─> Firebase.set()   ├─> Firebase.set()   
  │   {dose: 75}        │   {times: [...]}    
  │   UpdatedAt:T1      │   UpdatedAt:T2      
  │   (LastChangeAt=D1) │   (LastChangeAt=D1?)
  │                      │
  └─────────┬────────────┘
            │ ⚠️ 冲突检测
            ▼
      ┌──────────────┐
      │ 比较时间戳   │
      │ T1 vs T2   │
      │ T1 > T2   │
      │ → A值获胜  │
      └──────┬───────┘
            ▼
      ┌──────────────┐
      │ Firebase    │
      │ 最终状态:    │
      │ dose: 75mg  │
      │ times: [...] │
      │ UpdatedAt:T1 │
      └──────────────┘
            │
      ┌─────┴──────┐
      ▼            ▼
   设备A       设备B
  (一致)     (需要同步)
  75mg       50mg → pull → 75mg
   [...] ←─────────────── [...]


策略: "Last Write Wins (LWW)" + updateAt/lastChangeAt
- 优先使用服务器时间戳完全解决
- 冲突很少（因为调药不频繁，通常是不同用户/设备）
- 若遇到 3-way 冲突 → 应用最新的 MedAdjustment 记录
```

---

## 📱 关键数据字段映射

```
┌─────────────────────────────────────────────────────┐
│ Medication (药物主记录)                            │
├─────────────────────────────────────────────────────┤
│ Field              │ Type    │ Required │ Notes      │
├────────────────────┼─────────┼──────────┼────────────┤
│ id                 │ String  │ Yes      │ Doc ID     │
│ uid                │ String  │ Yes      │ 用户ID     │
│ name               │ String  │ Yes      │ 中文名     │
│ nameEn             │ String  │ No       │ 英文名     │
│ dose               │ double  │ Yes      │ 最终剂量   │
│ dosePerUnit        │ double  │ No       │ 每顆/mL    │
│ pillCount          │ double  │ No       │ 每次几顆   │
│ concentrationMg    │ double  │ No       │ 浓度mg     │
│ concentrationMl    │ double  │ No       │ 浓度mL     │
│ intakeMl           │ double  │ No       │ 摄取mL     │
│ unit               │ String  │ Yes      │ mg/mL等    │
│ type               │ String  │ Yes      │ tablet/... │
│ intervalDays       │ int     │ No       │ 针剂间隔   │
│ times              │ [String]│ No       │ 时间槽     │
│ purposes           │ [String]│ No       │ 用途列表   │
│ note               │ String  │ No       │ 备注       │
│ startDate          │ String  │ Yes      │ YYYY-MM-DD │
│ isActive           │ bool    │ Yes      │ 状态       │
│ bodySymptoms       │ [String]│ No       │ 身体症状   │
│ purposeOther       │ String  │ No       │ 其他用途   │
│ createdAt          │ String  │ Yes      │ 创建时间   │
│ updatedAt          │ String  │ Yes      │ 更新时间   │
│ lastChangeAt       │ String  │ No       │ 最后调整   │
└────────────────────┴─────────┴──────────┴────────────┘

┌─────────────────────────────────────────────────────┐
│ MedAdjustment (调药记录)                           │
├─────────────────────────────────────────────────────┤
│ Field              │ Type    │ Description         │
├────────────────────┼─────────┼─────────────────────┤
│ id                 │ String  │ 调整记录ID          │
│ uid                │ String  │ 用户ID              │
│ date               │ Date    │ 回诊日期            │
│ note               │ String  │ 本次调整备注        │
│ items              │ [Object]│ 变动项目列表        │
│ └─ medDocId        │ String  │ 药物ID              │
│ └─ name            │ String  │ 药物名称            │
│ └─ type            │ String  │ 变动类型            │
│ └─ oldDose         │ double? │ 原剂量              │
│ └─ newDose         │ double? │ 新剂量              │
│ └─ oldTimes        │ [String]?│ 原时间              │
│ └─ newTimes        │ [String]?│ 新时间              │
│ └─ stopReason      │ String? │ 停药原因            │
│ createdAt          │ Date    │ 创建时间戳          │
└────────────────────┴─────────┴─────────────────────┘

┌─────────────────────────────────────────────────────┐
│ MedicationCheckin (打卡记录)                       │
├─────────────────────────────────────────────────────┤
│ Field              │ Type    │ Description         │
├────────────────────┼─────────┼─────────────────────┤
│ (docId = YYYYMMDD) │         │ 日期作为文档ID      │
│ checks             │ Map     │ {key: bool}         │
│ │└─ key            │ String  │ 'medId::slot'      │
│ │└─ value          │ bool    │ 是否打卡            │
│ statuses           │ Map     │ {key: status}       │
│ │└─ value          │ String  │ pending/taken/...   │
│ statusAt           │ Map     │ {key: Timestamp}    │
│ actualAmounts      │ Map     │ {key: double}       │
│ prnEvents          │ Map     │ {key: [Timestamp]}  │
│ lastUpdated        │ Timestamp│ 上次更新时间        │
└────────────────────┴─────────┴─────────────────────┘
```

---

**架构图版本：** v1.0  
**最后更新：** 2024-05-02
