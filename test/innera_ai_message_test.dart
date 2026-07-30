import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_message.dart';
import 'package:moodsogood_app/ai/innera_ai_safety_service.dart';

void main() {
  test('persisted AI messages restore their full conversation fields', () {
    final original = InneraAiMessage(
      id: 'a-1',
      role: InneraAiMessageRole.assistant,
      text: '我記得你早上很興奮，下午有些空虛。',
      createdAt: DateTime.parse('2026-07-23T21:00:00+08:00'),
      sources: const [
        AiContextSource(label: '今天的紀錄', dateRange: '2026-07-23', count: 1),
      ],
      safetyLevel: AiSafetyLevel.possibleSelfHarm,
    );

    final restored = InneraAiMessage.tryFromMap(original.toMap());

    expect(restored, isNotNull);
    expect(restored!.id, original.id);
    expect(restored.role, original.role);
    expect(restored.text, original.text);
    expect(restored.createdAt, original.createdAt);
    expect(restored.sources.single.label, '今天的紀錄');
    expect(restored.safetyLevel, AiSafetyLevel.possibleSelfHarm);
  });

  test('loading and error bubbles are never persisted', () {
    final loading = InneraAiMessage(
      id: 'loading',
      role: InneraAiMessageRole.assistant,
      text: '',
      createdAt: DateTime.now(),
      isLoading: true,
    );
    final error = InneraAiMessage(
      id: 'error',
      role: InneraAiMessageRole.assistant,
      text: '暫時無法連線',
      createdAt: DateTime.now(),
      isError: true,
    );

    expect(loading.canPersist, isFalse);
    expect(error.canPersist, isFalse);
  });

  test('photo attachments persist and restore with the chat message', () {
    final original = InneraAiMessage(
      id: 'photo-1',
      role: InneraAiMessageRole.user,
      text: '請幫我看看這張照片',
      createdAt: DateTime.parse('2026-07-30T10:00:00+08:00'),
      image: const InneraAiImageAttachment(
        storagePath: 'users/user-1/ai_chat_images/2026-07-30/photo.jpg',
        downloadUrl: 'https://example.com/photo.jpg',
        contentType: 'image/jpeg',
      ),
    );

    final restored = InneraAiMessage.tryFromMap(original.toMap());

    expect(restored, isNotNull);
    expect(restored!.image, isNotNull);
    expect(restored.image!.storagePath, original.image!.storagePath);
    expect(restored.image!.downloadUrl, original.image!.downloadUrl);
    expect(restored.image!.contentType, 'image/jpeg');
  });

  test(
      'an image-only persisted message is accepted when its attachment is valid',
      () {
    final restored = InneraAiMessage.tryFromMap({
      'id': 'photo-only',
      'role': 'user',
      'text': '',
      'createdAt': '2026-07-30T10:00:00+08:00',
      'image': {
        'storagePath': 'users/user-1/ai_chat_images/2026-07-30/photo.png',
        'downloadUrl': 'https://example.com/photo.png',
        'contentType': 'image/png',
      },
    });

    expect(restored, isNotNull);
    expect(restored!.canPersist, isTrue);
  });

  test('encrypted photo attachments do not require a download URL', () {
    const attachment = InneraAiImageAttachment(
      storagePath:
          'users/user-1/ai_chat_images_encrypted/2026-07-30/photo.innera',
      downloadUrl: '',
      contentType: 'image/webp',
      encryptionVersion: 1,
    );

    final restored = InneraAiImageAttachment.fromMap(attachment.toMap());

    expect(attachment.toMap().containsKey('downloadUrl'), isFalse);
    expect(restored.isValid, isTrue);
    expect(restored.isEncrypted, isTrue);
    expect(restored.encryptionVersion, 1);
  });
}
