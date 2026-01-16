# Firebase Sync Control Implementation Guide

## Overview
This implementation adds a Firebase sync control flag to allow toggling between cloud-based Firebase storage and local-only storage modes.

## Files Created

### 1. `lib/utils/firebase_sync_config.dart`
**Purpose**: Core configuration and singleton for managing Firebase sync state

**Key Components**:
- `kDebugDefaultFirebaseSync`: Default flag (set to `true` for production, `false` for local-only development)
- `FirebaseSyncConfig.shouldSync()`: Static method to check if Firebase sync is enabled
- `init()`: Loads saved preference from SharedPreferences on app startup
- `setEnabled(bool)`: Toggles sync state and persists to SharedPreferences

**Usage**:
```dart
import 'package:moodsogood_app/utils/firebase_sync_config.dart';

// Check if sync should happen
if (FirebaseSyncConfig.shouldSync()) {
  // Write to Firebase
  await FirebaseFirestore.instance...
}
```

### 2. `lib/providers/firebase_sync_provider.dart`
**Purpose**: ChangeNotifier provider for reactive UI updates based on sync state

**Key Components**:
- `isEnabled`: Current sync state (readable by UI)
- `statusString`: Human-readable status for display
- `toggleSync(bool)`: Async method to toggle and notify listeners

**Usage in UI**:
```dart
Consumer<FirebaseSyncProvider>(
  builder: (context, syncProvider, child) {
    return SwitchListTile(
      value: syncProvider.isEnabled,
      onChanged: (val) => syncProvider.toggleSync(val),
    );
  },
)
```

## Modified Files

### 1. `lib/main.dart`
- Added import: `firebase_sync_config.dart` and `firebase_sync_provider.dart`
- Added initialization: `await FirebaseSyncConfig().init();` in `main()`
- Added to MultiProvider: `FirebaseSyncProvider` alongside existing providers

### 2. `lib/diary/diary_page_demo.dart`
- Added import: `firebase_sync_config.dart`
- Wrapped Firestore write in `_saveDraft()`:
  ```dart
  if (FirebaseSyncConfig.shouldSync()) {
    await _docRef.set({...}, SetOptions(merge: true));
  }
  ```

### 3. `lib/meds/medication_actions.dart`
- Added import: `firebase_sync_config.dart`
- Wrapped Firebase writes in all mutation functions:
  - `_deactivateMedication()`
  - `_activateMedication()`
  - `_deleteMedication()`

### 4. `lib/settings_page.dart`
- Added import: `firebase_sync_provider.dart`
- Added UI section "資料同步" (Data Sync) with:
  - Toggle switch for Firebase sync on/off
  - Status indicator (green when enabled, orange when local-only)
  - Toast notification on toggle

## How to Use

### For Development (Local-Only Mode)
1. Open Settings page
2. Find "資料同步" section
3. Toggle "Firebase 雲端同步" OFF
4. App will now:
   - Store data locally only
   - Skip all Firebase writes
   - Show "⚠️ 本機儲存模式已啟用" notification

### For Production (Firebase Sync)
1. Ensure flag is ON in Settings (default on app startup)
2. All data writes will sync to Firebase

### Programmatically

**To disable sync for testing**:
```dart
import 'package:moodsogood_app/utils/firebase_sync_config.dart';

// In code
FirebaseSyncConfig().setEnabled(false);
```

**To check sync status**:
```dart
if (FirebaseSyncConfig.shouldSync()) {
  print('Firebase sync is enabled');
} else {
  print('Local-only mode');
}
```

## Adding Sync Control to More Operations

To add the sync check to other Firebase write operations:

1. Import the config:
   ```dart
   import '../utils/firebase_sync_config.dart';
   ```

2. Wrap the Firestore operation:
   ```dart
   if (FirebaseSyncConfig.shouldSync()) {
     await FirebaseFirestore.instance
         .collection('users')
         .doc(uid)
         .collection('myData')
         .doc(id)
         .set({...});
   }
   ```

## Examples

### Diary Save
```dart
Future<void> _saveDraft() async {
  if (FirebaseSyncConfig.shouldSync()) {
    await _docRef.set({
      'title': titleCtrl.text,
      'content': contentCtrl.text,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  // Local SQLite save can happen regardless
}
```

### User Profile Update
```dart
Future<void> updateUserProfile(String displayName) async {
  if (FirebaseSyncConfig.shouldSync()) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'displayName': displayName}, SetOptions(merge: true));
  }
}
```

## Data Flow

### When Sync is ENABLED ✅
```
User Input 
  → Local Storage (SQLite/SharedPreferences) 
  → Firebase Firestore
```

### When Sync is DISABLED ⚠️
```
User Input 
  → Local Storage (SQLite/SharedPreferences) 
  → [Firebase write skipped]
```

## Storage Notes

- **Local SQLite**: Used for diary entries (always writes)
- **SharedPreferences**: Used for app settings (always writes)
- **Firebase Firestore**: Controlled by `FirebaseSyncConfig.shouldSync()`
- **Firebase Storage**: Not yet controlled (consider adding if needed)

## Persistence

The sync preference is saved in SharedPreferences with key `firebase_sync_enabled` and persists across app restarts.

## Next Steps

Consider adding sync control to:
- User profile photo uploads (Firebase Storage)
- Feedback submissions
- Drug dictionary custom entries
- Any other Firestore writes in your app

Just follow the pattern: Check `FirebaseSyncConfig.shouldSync()` before each Firebase write.
