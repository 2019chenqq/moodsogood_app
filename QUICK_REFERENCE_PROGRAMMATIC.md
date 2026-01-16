# Firebase Sync Control - Quick Reference

## 🎯 One-Minute Overview

Your app has a **program-controlled** Firebase sync flag:
- **Enable**: Sync data to Firebase ✅ 
- **Disable**: Local-only storage ⚠️

This is controlled by your **code**, not by end-users.

## 🔧 How It Works

### 1. Set Control
Edit `lib/utils/firebase_sync_config.dart`:
```dart
// Production: Enable Firebase
static const bool kEnableFirebaseSync = true;

// Development: Disable Firebase
static const bool kEnableFirebaseSync = false;
```

### 2. Check Before Write
```dart
import '../utils/firebase_sync_config.dart';

if (FirebaseSyncConfig.shouldSync()) {
  await firebaseWrite();  // Only if enabled
}
```

### 3. Provider (Optional Display)
```dart
Consumer<FirebaseSyncProvider>(
  builder: (ctx, syncProvider, _) {
    return Text(syncProvider.statusString);
  },
)
```

## 📍 Protected Operations

| Component | File | Method |
|-----------|------|--------|
| Diary | `diary_page_demo.dart` | `_saveDraft()` |
| Medications | `medication_actions.dart` | All mutations |

## 🚀 Pattern

```dart
// Before any Firebase write:
if (FirebaseSyncConfig.shouldSync()) {
  await FirebaseFirestore.instance...
}
```

## 🔄 Data Flow

**Sync ON ✅**: Input → Local → Firebase  
**Sync OFF ⚠️**: Input → Local → [Firebase skipped]

## 💡 Use Cases

- **Development**: Set `false` to avoid Firebase quota
- **Testing**: Set `false` for local-only testing  
- **Production**: Set `true` for cloud sync

## 📚 Full Docs

See [README_FIREBASE_SYNC.md](README_FIREBASE_SYNC.md) for complete guide.
