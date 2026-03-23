# Firebase Sync Control - Code Examples

## Example 1: Basic Usage in Existing Code

### Diary Entry Save
```dart
// File: lib/diary/diary_page_demo.dart
import '../utils/firebase_sync_config.dart';

Future<void> _saveDraft() async {
  try {
    // Only sync to Firebase if enabled
    if (FirebaseSyncConfig.shouldSync()) {
      await _docRef.set({
        'date': Timestamp.fromDate(_day),
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    
    // Local update always happens
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedAt = DateTime.now();
    });
  } catch (e) {
    debugPrint('Error: $e');
  }
}
```

## Example 2: Medication Operations

### Deactivate Medication
```dart
// File: lib/meds/medication_actions.dart
import '../utils/firebase_sync_config.dart';

Future<void> _deactivateMedication({
  required String uid,
  required String medId,
}) async {
  // Only sync to Firebase if enabled
  if (FirebaseSyncConfig.shouldSync()) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medications')
        .doc(medId)
        .set({
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
  
  // Local state update would go here
  debugPrint('📝 Medication deactivated locally');
}
```

## Example 3: Delete Operation with User Feedback

```dart
// File: lib/meds/medication_actions.dart

if (action == 'delete') {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: const Text('確認刪除？'),
      content: Text('確定要永久刪除「$name」嗎？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('刪除'),
        ),
      ],
    ),
  );

  if (ok != true) return;

  // Only sync to Firebase if enabled
  if (FirebaseSyncConfig.shouldSync()) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medications')
        .doc(medId)
        .delete();
  }

  if (!context.mounted) return;
  
  // Show appropriate message based on sync status
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '已刪除：$name${!FirebaseSyncConfig.shouldSync() ? ' (本機只)' : '}'
      ),
    ),
  );
}
```

## Example 4: New Feature - User Profile Update

```dart
// File: lib/Home_shell.dart (example for new feature)
import '../utils/firebase_sync_config.dart';

Future<void> updateUserProfile({
  required String uid,
  required String displayName,
  required String nickname,
}) async {
  try {
    // Only sync to Firebase if enabled
    if (FirebaseSyncConfig.shouldSync()) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'displayName': displayName,
            'nickname': nickname,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      
      debugPrint('✅ User profile synced to Firebase');
    } else {
      debugPrint('⚠️ User profile saved locally only');
    }
  } catch (e) {
    debugPrint('❌ Error updating profile: $e');
  }
}
```

## Example 5: Conditional Feedback Creation

```dart
// File: lib/pages/feedback_page.dart (example)
import '../utils/firebase_sync_config.dart';

Future<void> _submitFeedback() async {
  final content = _controller.text.trim();
  if (content.isEmpty) return;

  setState(() => _isSubmitting = true);

  try {
    // Only sync to Firebase if enabled
    if (FirebaseSyncConfig.shouldSync()) {
      await FirebaseFirestore.instance
          .collection('feedback')
          .add({
            'uid': FirebaseAuth.instance.currentUser!.uid,
            'content': content,
            'createdAt': FieldValue.serverTimestamp(),
          });
      
      _showSnackBar('感謝反饋！已上傳');
    } else {
      _showSnackBar('反饋已保存（本機只）');
    }
    
    _controller.clear();
  } catch (e) {
    _showSnackBar('提交失敗：$e');
  } finally {
    if (mounted) setState(() => _isSubmitting = false);
  }
}
```

## Example 6: Reading Sync Status in UI

### Option A: Using Consumer (Recommended)
```dart
// File: lib/settings_page.dart (already implemented)
Consumer<FirebaseSyncProvider>(
  builder: (context, syncProvider, child) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Firebase 雲端同步'),
          subtitle: Text(
            syncProvider.isEnabled
                ? '資料將自動同步到雲端'
                : '僅儲存在本機（開發模式）',
            style: TextStyle(
              color: syncProvider.isEnabled ? Colors.green : Colors.orange,
            ),
          ),
          value: syncProvider.isEnabled,
          onChanged: (val) => syncProvider.toggleSync(val),
        ),
      ],
    );
  },
)
```

### Option B: Direct Check (Simpler)
```dart
// If you just need to check status without listening
import '../utils/firebase_sync_config.dart';

Widget buildStatusWidget() {
  return Text(
    FirebaseSyncConfig.shouldSync()
        ? '✅ Firebase Sync Enabled'
        : '⚠️ Local Only Mode',
  );
}
```

## Example 7: Provider Integration in main.dart

```dart
// File: lib/main.dart
import 'providers/firebase_sync_provider.dart';
import 'utils/firebase_sync_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase Sync Config
  await FirebaseSyncConfig().init();
  debugPrint('📡 Firebase Sync Config initialized');
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<FirebaseSyncProvider>(
          create: (_) => FirebaseSyncProvider()..init(),
        ),
        // ... other providers
      ],
      child: const MainApp(),
    ),
  );
}
```

## Example 8: Testing Mode Setup

### Disable All Firebase Writes for Testing
```dart
// In main.dart or a test initialization function
void setupTestMode() async {
  await FirebaseSyncConfig().setEnabled(false);
  debugPrint('⚠️ TEST MODE: Firebase sync disabled');
}

// Call before running tests
void main() async {
  setupTestMode();
  runApp(const MyApp());
}
```

### Check Current Mode
```dart
void debugPrintSyncStatus() {
  if (FirebaseSyncConfig.shouldSync()) {
    print('🟢 Production Mode: Firebase writes enabled');
  } else {
    print('🟠 Development Mode: Firebase writes disabled (local only)');
  }
}
```

## Example 9: Batch Operation with Sync Control

```dart
// File: lib/meds/medication_batch_service.dart (new file example)
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firebase_sync_config.dart';

class MedicationBatchService {
  /// Add multiple medications at once
  Future<void> addMultipleMedications({
    required String uid,
    required List<Map<String, dynamic>> medications,
  }) async {
    // Only sync to Firebase if enabled
    if (FirebaseSyncConfig.shouldSync()) {
      final batch = FirebaseFirestore.instance.batch();
      final userMedsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications');

      for (final med in medications) {
        batch.set(userMedsRef.doc(), med);
      }

      await batch.commit();
      debugPrint('✅ ${medications.length} medications synced to Firebase');
    } else {
      debugPrint('⚠️ ${medications.length} medications saved locally only');
    }
  }
}
```

## Example 10: Migration - Enable Sync for Synced Data

```dart
// File: lib/service/sync_service.dart (new file example)
import '../utils/firebase_sync_config.dart';

class SyncService {
  /// Enable sync and upload any pending local data
  static Future<void> enableSyncAndMigrate() async {
    // Enable sync
    await FirebaseSyncConfig().setEnabled(true);
    
    // TODO: Implement logic to push pending local changes
    // This would read from SQLite and push to Firestore
    
    debugPrint('✅ Sync enabled - migration started');
  }
  
  /// Disable sync and cache Firestore data locally
  static Future<void> disableSyncAndCache() async {
    // TODO: Download current Firebase data and store in SQLite
    
    // Disable sync
    await FirebaseSyncConfig().setEnabled(false);
    
    debugPrint('✅ Sync disabled - local cache ready');
  }
}
```

---

## 🎯 Pattern Summary

Every Firebase write should follow this pattern:

```dart
// 1. Import
import '../utils/firebase_sync_config.dart';

// 2. Check before write
if (FirebaseSyncConfig.shouldSync()) {
  // 3. Perform Firebase operation
  await FirebaseFirestore.instance...
}

// 4. Local operation always proceeds
// (update UI, local database, etc.)
```

**Exception**: Auth operations typically don't need this check as they're user-initiated.
