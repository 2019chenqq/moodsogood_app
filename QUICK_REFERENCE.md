# Firebase Sync Control - Quick Reference

## 🎯 One-Minute Overview

Your app now has a toggleable Firebase sync flag that lets you:
- **Enable**: Sync data to Firebase (production mode) ✅
- **Disable**: Store data locally only (development/testing mode) ⚠️

## 🔧 3 Core Components

### 1. Configuration (`firebase_sync_config.dart`)
```dart
// Check if sync is enabled
if (FirebaseSyncConfig.shouldSync()) {
  // Do Firebase write
}

// Toggle sync
await FirebaseSyncConfig().setEnabled(false);
```

### 2. Provider (`firebase_sync_provider.dart`)
```dart
// Use in UI with Consumer
Consumer<FirebaseSyncProvider>(
  builder: (ctx, syncProvider, _) {
    return Text('Sync: ${syncProvider.statusString}');
  },
)
```

### 3. UI Toggle (in `settings_page.dart`)
```
Settings > 資料同步 > Firebase 雲端同步 [Toggle]
```

## 📍 Where It's Used

| Component | File | Function |
|-----------|------|----------|
| Diary | `diary_page_demo.dart` | `_saveDraft()` |
| Medications | `medication_actions.dart` | `_deactivateMedication()` |
| Medications | `medication_actions.dart` | `_activateMedication()` |
| Medications | `medication_actions.dart` | `_deleteMedication()` |

## 🚀 Adding to New Code

Pattern for any new Firebase write:

```dart
import 'path/to/firebase_sync_config.dart';

// Before Firebase write
if (FirebaseSyncConfig.shouldSync()) {
  await firebaseWrite();
}
```

## 📱 User Experience

**In Settings app:**
1. Scroll down to "資料同步" section
2. Toggle "Firebase 雲端同步" switch
3. See status update (green = enabled, orange = local-only)
4. Preference auto-saves

## 🎨 Visual Indicators

- **Enabled**: "資料將自動同步到雲端" (green)
- **Disabled**: "僅儲存在本機（開發模式）" (orange)

## 💾 Persistence

- Saved to SharedPreferences key: `firebase_sync_enabled`
- Survives app restart
- Default: `true` (sync enabled)

## 🔄 Data Flow

### Sync ON ✅
```
App Input → Local Cache → Firebase Firestore
```

### Sync OFF ⚠️
```
App Input → Local Cache → [Firebase write skipped]
```

## ⚙️ Default Configuration

**Production**: Sync enabled by default
```dart
static const bool kDebugDefaultFirebaseSync = true;
```

To change, edit `lib/utils/firebase_sync_config.dart` and update the constant.

## 🐛 Debugging

Check console output:
```
📡 Firebase Sync initialized: ENABLED
📡 Firebase Sync DISABLED
```

## 📚 Full Docs

See [FIREBASE_SYNC_CONTROL.md](FIREBASE_SYNC_CONTROL.md) for complete guide with examples.
