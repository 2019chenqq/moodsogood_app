// Firebase's already-installed platform interfaces are used only for offline
// test doubles; no native Firebase, emulator, network or persistent writes.
// ignore_for_file: depend_on_referenced_packages
// Firestore annotates SDK types @sealed to prevent production implementations.
// These fail-closed test doubles intentionally implement only read operations.
// ignore_for_file: subtype_of_sealed_class
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encryption;
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodsogood_app/daily/sleep_record_service.dart';
import 'package:moodsogood_app/daily/unified_sleep_repository.dart';
import 'package:moodsogood_app/utils/health_data_encryption_service.dart';
import 'package:moodsogood_app/utils/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = encryption.Key(Uint8List(32));
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = _Auth();
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(
        {'user_aes_encryption_key': key.base64});
    SharedPreferences.setMockInitialValues({
      'e2eVerifier': SecureStorageService.buildKeyVerifier(key),
    });
  });

  test('single and range agree on empty current, including missing date IDs',
      () async {
    final db = _ReadOnlyStore({
      'users/u/sleepRecords/2026-01-31': {},
      'users/u/dailyRecords/2026-01-31': {
        'sleep': {'quality': 4}
      },
    });
    final repo = UnifiedSleepRepository(firestore: db);
    final single =
        await repo.getForDate(userId: 'u', date: DateTime(2026, 1, 31));
    final range = await repo.getByDateRange(
        userId: 'u', start: DateTime(2026, 1, 31), end: DateTime(2026, 2, 1));
    expect(single!.source, SleepRecordSource.legacyDailyRecord);
    expect(range.single.source, single.source);
    expect(range.single.record.toMap(), single.record.toMap());
    expect(single.record.date, DateTime(2026, 1, 31));
  });

  test('partial encrypted current wins without borrowing legacy quality',
      () async {
    final db = _ReadOnlyStore({
      'users/u/sleepRecords/2026-02-01':
          HealthDataEncryptionService.encryptForTesting({
        'date': Timestamp.fromDate(DateTime(2026, 2, 1)),
        'note': 'partial'
      }, key: key, collectionName: 'sleepRecords'),
      'users/u/dailyRecords/2026-02-01': {
        'sleep': {'quality': 5}
      },
    });
    final repo = UnifiedSleepRepository(firestore: db);
    final single =
        await repo.getForDate(userId: 'u', date: DateTime(2026, 2, 1));
    final range = await repo.getByDateRange(
        userId: 'u', start: DateTime(2026, 1, 31), end: DateTime(2026, 2, 1));
    expect(single!.source, SleepRecordSource.sleepRecord);
    expect(single.record.quality, isNull);
    expect(range, hasLength(1)); // date query + ID query must deduplicate.
    expect(range.single.record.toMap(), single.record.toMap());
  });

  test(
      'range recovers valid IDs, excludes invalid IDs and explicit out-of-range dates',
      () async {
    final db = _ReadOnlyStore({
      'users/u/sleepRecords/2026-01-31': {'date': 'bad', 'quality': 3},
      'users/u/sleepRecords/2026-02-01': {'quality': 4},
      'users/u/sleepRecords/2026-02-02': {'date': '2026-03-01', 'quality': 5},
      'users/u/sleepRecords/2026-02-30': {'date': '2026-02-30', 'quality': 5},
      'users/u/sleepRecords/2026-02-01-copy': {'quality': 5},
      'users/u/sleepRecords/auto': {'quality': 5},
    });
    final records = await UnifiedSleepRepository(firestore: db).getByDateRange(
        userId: 'u', start: DateTime(2026, 1, 31), end: DateTime(2026, 2, 28));
    expect(records.map((item) => item.record.date),
        [DateTime(2026, 1, 31), DateTime(2026, 2, 1)]);
  });

  test('single reads reject a valid field belonging to a different day',
      () async {
    final db = _ReadOnlyStore({
      'users/u/sleepRecords/2026-01-31': {'date': '2026-02-01', 'quality': 5},
      'users/u/dailyRecords/2026-01-31': {
        'date': '2026-02-01',
        'sleep': {'quality': 3}
      },
    });
    expect(
        await SleepRecordService(firestore: db)
            .get(userId: 'u', date: DateTime(2026, 1, 31)),
        isNull);
    expect(
        await UnifiedSleepRepository(firestore: db)
            .getForDate(userId: 'u', date: DateTime(2026, 1, 31)),
        isNull);
  });

  test('last microsecond included; empty and duration-only days stay absent',
      () async {
    final db = _ReadOnlyStore({
      'users/u/sleepRecords/auto': {
        'date': Timestamp.fromDate(DateTime(2026, 1, 31, 23, 59, 59, 999, 999)),
        'quality': 4
      },
      'users/u/sleepRecords/2026-02-01': {'duration': 480},
      'users/u/dailyRecords/2026-02-01': {'sleep': {}},
    });
    final repo = UnifiedSleepRepository(firestore: db);
    expect(
        await repo.getForDate(userId: 'u', date: DateTime(2026, 2, 1)), isNull);
    final range = await repo.getByDateRange(
        userId: 'u', start: DateTime(2026, 1, 31), end: DateTime(2026, 2, 1));
    expect(range.single.record.quality, 4);
    expect(range.single.record.date.day, 31);
  });

  test('legacy invalid date uses ID; invalid range performs no reads',
      () async {
    final db = _ReadOnlyStore({
      'users/u/dailyRecords/2026-02-01': {
        'date': '2026-02-30',
        'sleep': {'quality': 2}
      },
    });
    final repo = UnifiedSleepRepository(firestore: db);
    expect(
        await repo.getByDateRange(
            userId: 'u',
            start: DateTime(2026, 2, 2),
            end: DateTime(2026, 2, 1)),
        isEmpty);
    expect(db.reads, 0);
    final single =
        await repo.getForDate(userId: 'u', date: DateTime(2026, 2, 1));
    final range = await repo.getByDateRange(
        userId: 'u', start: DateTime(2026, 2, 1), end: DateTime(2026, 2, 1));
    expect(single!.record.date, DateTime(2026, 2, 1));
    expect(range.single.record.toMap(), single.record.toMap());
  });
}

class _Auth extends FirebaseAuthPlatform {
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues(
          {PigeonUserDetails? currentUser, String? languageCode}) =>
      this;
  @override
  UserPlatform get currentUser => _User(this);
}

class _User extends UserPlatform {
  _User(FirebaseAuthPlatform auth)
      : super(
            auth,
            _MultiFactor(auth),
            PigeonUserDetails(
                userInfo: PigeonUserInfo(
                    uid: 'u', isAnonymous: false, isEmailVerified: true),
                providerData: []));
}

class _MultiFactor extends MultiFactorPlatform {
  _MultiFactor(super.auth);
}

// Fail closed: only the listed read methods are implemented. Any write is an
// unexpected invocation and throws, rather than reaching a Firebase plugin.
class _ReadOnlyStore implements FirebaseFirestore {
  _ReadOnlyStore(this.documents);
  final Map<String, Map<String, dynamic>> documents;
  int reads = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected Firestore operation: ${invocation.memberName}');
}

class _Reference implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.store, this.path);
  final _ReadOnlyStore store;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      _Collection(store, '$path/$name');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    store.reads++;
    final data = store.documents[path];
    return data == null ? _MissingDocument() : _Document(this, data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected document operation: ${invocation.memberName}');
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path, [this.filters = const []]);
  final _ReadOnlyStore store;
  @override
  final String path;
  final List<bool Function(String, Map<String, dynamic>)> filters;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Reference(store, '${this.path}/$path');
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    store.reads++;
    final docs = store.documents.entries
        .where((entry) =>
            entry.key.startsWith('$path/') &&
            entry.key.split('/').length == path.split('/').length + 1 &&
            filters.every(
                (filter) => filter(entry.key.split('/').last, entry.value)))
        .map((entry) => _Document(_Reference(store, entry.key), entry.value))
        .toList();
    return _QuerySnapshot(docs);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #where) {
      throw UnsupportedError(
          'Unexpected query operation: ${invocation.memberName}');
    }
    final field = invocation.positionalArguments.single;
    final lower = invocation.namedArguments[#isGreaterThanOrEqualTo];
    final upper = invocation.namedArguments[#isLessThan];
    return _Collection(store, path, [
      ...filters,
      (id, data) {
        final value = field == FieldPath.documentId ? id : data[field];
        int? compare(Object? bound) {
          if (value is Timestamp && bound is Timestamp) {
            return value.compareTo(bound);
          }
          if (value is String && bound is String) return value.compareTo(bound);
          return null;
        }

        if (lower != null && (compare(lower) == null || compare(lower)! < 0)) {
          return false;
        }
        if (upper != null && (compare(upper) == null || compare(upper)! >= 0)) {
          return false;
        }
        return true;
      }
    ]);
  }
}

class _Document implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Document(this.reference, this.values);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> values;
  @override
  String get id => reference.id;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => Map.from(values);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

class _MissingDocument implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  Map<String, dynamic>? data() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

class _QuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('$invocation');
}
