# Firebase Sync Control - Architecture & Diagrams

## 📊 System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      User App Layer                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Settings Page              Diary Page        Med Page       │
│  ┌──────────────┐          ┌──────────┐     ┌─────────┐    │
│  │ Sync Toggle  │          │ Save     │     │ Action  │    │
│  │ ON / OFF ← ─ │→ Event   │ Draft    │     │ Buttons │    │
│  └──────────────┘          └──────────┘     └─────────┘    │
│                                  │                 │         │
│                                  ▼                 ▼         │
└─────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
        ┌──────────────────────────────────────┐
        │   FirebaseSyncProvider               │
        │   (ChangeNotifier)                   │
        ├──────────────────────────────────────┤
        │ • isEnabled                          │
        │ • toggleSync(bool)                   │
        │ • statusString                       │
        │ • Notify listeners on change         │
        └──────────────────────────────────────┘
                        │
                        ▼
        ┌──────────────────────────────────────┐
        │   FirebaseSyncConfig                 │
        │   (Singleton)                        │
        ├──────────────────────────────────────┤
        │ • shouldSync() → bool                │
        │ • setEnabled(bool)                   │
        │ • init()                             │
        │ • kDebugDefaultFirebaseSync          │
        └──────────────────────────────────────┘
                        │
                        ▼
        ┌──────────────────────────────────────┐
        │   SharedPreferences                  │
        │   (Key: firebase_sync_enabled)       │
        └──────────────────────────────────────┘
```

## 🔄 Data Flow Diagram

### When Firebase Sync is ENABLED ✅

```
User Input
    │
    ▼
┌─────────────────────┐
│ Diary/Med Pages     │
│ (Accept input)      │
└─────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────┐
│ Check: shouldSync()?                        │
│ Result: TRUE ✅                             │
└─────────────────────────────────────────────┘
    │
    ├──────────────────────┬──────────────────────┐
    │                      │                      │
    ▼                      ▼                      ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Save to:     │    │ Save to:     │    │ Notify UI    │
│              │    │              │    │              │
│ SQLite DB    │    │ Firebase     │    │ "✅ Synced   │
│ (Local)      │    │ Firestore    │    │  to cloud"   │
└──────────────┘    └──────────────┘    └──────────────┘
```

### When Firebase Sync is DISABLED ⚠️

```
User Input
    │
    ▼
┌─────────────────────┐
│ Diary/Med Pages     │
│ (Accept input)      │
└─────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────┐
│ Check: shouldSync()?                        │
│ Result: FALSE ⚠️                            │
└─────────────────────────────────────────────┘
    │
    ├──────────────────────┬──────────────────────┐
    │                      │                      │
    ▼                      ▼                      ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Save to:     │    │ SKIP:        │    │ Notify UI    │
│              │    │              │    │              │
│ SQLite DB    │    │ Firebase     │    │ "⚠️ Local    │
│ (Local)      │    │ (Disabled)   │    │  only mode"  │
└──────────────┘    └──────────────┘    └──────────────┘
```

## 🎯 Component Interaction Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│                    USER ACTIONS                                  │
│                                                                  │
│  Click Toggle          Edit Diary            Action on Med      │
│       │                     │                      │             │
│       ▼                     ▼                      ▼             │
│  ┌────────────┐        ┌────────────┐       ┌────────────┐    │
│  │  Settings  │        │   Diary    │       │ Medication │    │
│  │   Page     │        │   Page     │       │   Pages    │    │
│  └────────────┘        └────────────┘       └────────────┘    │
│       │                     │                      │             │
│       │  onChanged          │  _saveDraft()        │  actions   │
│       │                     │                      │             │
│       └─────────────┬───────┴──────────────────────┘             │
│                     │                                            │
│                     ▼                                            │
│          ┌────────────────────────────┐                        │
│          │  FirebaseSyncProvider      │                        │
│          │  toggleSync(bool)          │                        │
│          └────────────────────────────┘                        │
│                     │                                            │
│                     ▼                                            │
│          ┌────────────────────────────┐                        │
│          │ FirebaseSyncConfig.setEnabled()                     │
│          └────────────────────────────┘                        │
│                     │                                            │
│        ┌────────────┴────────────┐                             │
│        │                         │                             │
│        ▼                         ▼                             │
│  ┌────────────────┐      ┌─────────────────┐                 │
│  │ SharedPrefs    │      │ Notify Listeners│                 │
│  │ (Persistence)  │      │ (UI updates)    │                 │
│  └────────────────┘      └─────────────────┘                 │
│        │                         │                             │
│        │                         │                             │
│        └────────────┬────────────┘                             │
│                     │                                            │
│                     ▼                                            │
│          ┌────────────────────────────┐                        │
│          │ Next Firebase Operation    │                        │
│          │ Check shouldSync()         │                        │
│          │  ├─ TRUE → Write           │                        │
│          │  └─ FALSE → Skip           │                        │
│          └────────────────────────────┘                        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## 📱 State Machine Diagram

```
                    ┌─────────────────────────┐
                    │                         │
                    ▼                         │
            ┌──────────────────┐             │
            │  SYNC ENABLED    │             │
            │     (DEFAULT)    │             │
            │  ✅ Firebase ON  │             │
            └──────────────────┘             │
                    │                         │
                    │                         │
       User clicks toggle OFF              User clicks toggle ON
                    │                         │
                    ▼                         │
            ┌──────────────────┐             │
            │  SYNC DISABLED   │─────────────┘
            │   LOCAL ONLY     │
            │  ⚠️ Firebase OFF │
            └──────────────────┘
                    │
                    │
            App stores preference
            in SharedPreferences
                    │
                    ▼
            App restart: Read
            from SharedPrefs
                    │
                    ├─ YES → SYNC ENABLED
                    └─ NO  → SYNC DISABLED
```

## 🔌 Firebase Write Guard Pattern

```
Every Firebase Write Operation:

    ┌─────────────────────────────────┐
    │  Start Firebase Write           │
    └─────────────────────────────────┘
                 │
                 ▼
    ┌─────────────────────────────────┐
    │ if (FirebaseSyncConfig          │
    │     .shouldSync())              │
    └─────────────────────────────────┘
            │              │
          TRUE          FALSE
            │              │
            ▼              ▼
    ┌──────────────┐  ┌──────────────┐
    │ Execute      │  │ Skip Write   │
    │ Firebase     │  │ (Do Nothing) │
    │ Operation    │  │              │
    └──────────────┘  └──────────────┘
            │              │
            └──────┬───────┘
                   │
                   ▼
    ┌─────────────────────────────────┐
    │ Continue with next operation    │
    │ (Local updates, UI notifications)
    └─────────────────────────────────┘
```

## 📊 File Dependencies Graph

```
lib/
├── main.dart
│   ├─→ firebase_sync_config.dart
│   ├─→ firebase_sync_provider.dart
│   └─→ settings_page.dart
│
├── utils/
│   └── firebase_sync_config.dart ◄── Imported by all modules
│       ├─→ SharedPreferences
│       └─→ Flutter (debugPrint)
│
├── providers/
│   └── firebase_sync_provider.dart ◄── Used in UI
│       ├─→ firebase_sync_config.dart
│       └─→ Flutter (ChangeNotifier)
│
├── settings_page.dart
│   ├─→ firebase_sync_provider.dart (Consumer)
│   └─→ Shows/manages toggle
│
├── diary/
│   └── diary_page_demo.dart
│       └─→ firebase_sync_config.dart (in _saveDraft)
│
└── meds/
    └── medication_actions.dart
        └─→ firebase_sync_config.dart (in all mutations)
```

## 🎯 Permission & Access Levels

```
┌─────────────────────────────────────────────────────┐
│         FirebaseSyncConfig Access                   │
├─────────────────────────────────────────────────────┤
│                                                     │
│ PUBLIC (static, can call from anywhere):            │
│ • shouldSync() → bool                              │
│   └─ Used in: Diary, Meds, any Firebase write     │
│                                                     │
│ PUBLIC (instance, call on singleton):               │
│ • init() → Future<void>                            │
│   └─ Called in: main.dart                          │
│ • setEnabled(bool) → Future<void>                  │
│   └─ Called by: FirebaseSyncProvider               │
│                                                     │
│ PRIVATE (internal only):                            │
│ • _firebaseSyncEnabled → bool                      │
│ • _instance → FirebaseSyncConfig                   │
│ • _prefKey → String                                │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## 📈 Integration Timeline

```
App Lifecycle:

main() 
  │
  ├─ 1: Firebase.initializeApp()
  │
  ├─ 2: FirebaseSyncConfig().init()
  │     └─ Loads from SharedPreferences
  │
  ├─ 3: Create FirebaseSyncProvider
  │     └─ Adds to MultiProvider
  │
  └─ 4: App Ready
      └─ All Firebase writes check shouldSync()

User Interaction:

Settings > Toggle Firebase Sync
  │
  └─ FirebaseSyncProvider.toggleSync()
     └─ FirebaseSyncConfig.setEnabled()
        └─ Saves to SharedPreferences
           └─ Notifies listeners
              └─ UI updates immediately

Next Firebase Write:
  │
  └─ Check shouldSync()
     ├─ If TRUE  → Write to Firebase
     └─ If FALSE → Skip Firebase write
```

---

This architecture ensures:
- ✅ Clean separation of concerns
- ✅ Easy to add sync control to new features
- ✅ Persistent across app restarts
- ✅ Reactive UI updates via Provider
- ✅ No impact on local storage
