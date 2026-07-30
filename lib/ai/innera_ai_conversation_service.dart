import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'innera_ai_message.dart';
import 'innera_ai_mode.dart';
import '../utils/health_data_encryption_service.dart';

class InneraAiConversation {
  const InneraAiConversation({
    required this.messages,
    required this.mode,
  });

  final List<InneraAiMessage> messages;
  final InneraAiMode mode;
}

class InneraAiConversationService {
  InneraAiConversationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static const maxStoredMessages = 120;

  static String conversationDocumentId(
    String dateKey,
    InneraAiMode mode,
  ) =>
      '${dateKey}_${mode.name}';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<InneraAiConversation?> loadToday({
    required InneraAiMode mode,
  }) async {
    final uid = _requireUid();
    final dateKey = _todayKey();
    final snapshot = await _conversationRef(uid, dateKey, mode).get();
    final conversation = await _conversationFromSnapshot(snapshot);
    if (conversation != null) return conversation;

    // Read the old once-per-day document only when its saved mode matches.
    // This preserves existing conversations without letting one mode replace
    // the mode explicitly selected from the home screen.
    final legacySnapshot = await _legacyConversationRef(uid, dateKey).get();
    final legacyConversation = await _conversationFromSnapshot(legacySnapshot);
    return legacyConversation?.mode == mode ? legacyConversation : null;
  }

  Future<InneraAiConversation?> _conversationFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final raw = snapshot.data();
    if (!snapshot.exists || raw == null) return null;
    final data = await HealthDataEncryptionService.decryptData(raw);
    final messages = (data['messages'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => InneraAiMessage.tryFromMap(
                Map<String, dynamic>.from(item),
              ),
            )
            .whereType<InneraAiMessage>()
            .toList() ??
        const [];
    if (messages.isEmpty) return null;
    final modeName = data['mode']?.toString();
    return InneraAiConversation(
      messages: messages,
      mode: InneraAiMode.values.firstWhere(
        (value) => value.name == modeName,
        orElse: () => InneraAiMode.dailyRecord,
      ),
    );
  }

  Future<void> saveToday({
    required List<InneraAiMessage> messages,
    required InneraAiMode mode,
  }) async {
    final uid = _requireUid();
    final persistable =
        messages.where((message) => message.canPersist).toList();
    final start = persistable.length > maxStoredMessages
        ? persistable.length - maxStoredMessages
        : 0;
    await HealthDataEncryptionService.setEncrypted(
      _conversationRef(uid, _todayKey(), mode),
      {
        'schemaVersion': 1,
        'dateKey': _todayKey(),
        'mode': mode.name,
        'messages':
            persistable.skip(start).map((message) => message.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  /// Clears the selected chat session and, when requested, the shared
  /// unconfirmed record draft in one atomic batch. Official DailyRecord and
  /// diary documents are intentionally left untouched.
  Future<void> resetToday({
    required InneraAiMode mode,
    bool deleteRecordDraft = false,
  }) async {
    final uid = _requireUid();
    final dateKey = _todayKey();
    final batch = _firestore.batch();
    batch.delete(_conversationRef(uid, dateKey, mode));
    if (deleteRecordDraft) {
      batch.delete(
        _firestore
            .collection('users')
            .doc(uid)
            .collection('aiRecordDrafts')
            .doc(dateKey),
      );
    }
    final legacyRef = _legacyConversationRef(uid, dateKey);
    final legacySnapshot = await legacyRef.get();
    final legacyData = legacySnapshot.data();
    if (legacyData != null &&
        (await HealthDataEncryptionService.decryptData(legacyData))['mode'] ==
            mode.name) {
      batch.delete(legacyRef);
    }
    await batch.commit();
  }

  DocumentReference<Map<String, dynamic>> _conversationRef(
    String uid,
    String dateKey,
    InneraAiMode mode,
  ) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('aiConversations')
          .doc(conversationDocumentId(dateKey, mode));

  DocumentReference<Map<String, dynamic>> _legacyConversationRef(
    String uid,
    String dateKey,
  ) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('aiConversations')
          .doc(dateKey);

  String _requireUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    return uid;
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
