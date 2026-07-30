import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../innera_ai_chat_image_service.dart';
import '../innera_ai_message.dart';
import 'ai_context_sources_sheet.dart';

class AiMessageBubble extends StatelessWidget {
  const AiMessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.userPhotoUrl,
  });

  final InneraAiMessage message;
  final VoidCallback? onRetry;
  final String? userPhotoUrl;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == InneraAiMessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = isUser
        ? colorScheme.primary
        : message.isError
            ? colorScheme.errorContainer
            : HealingDesignSystem.adaptiveSurface(context);
    final textColor = isUser
        ? colorScheme.onPrimary
        : message.isError
            ? colorScheme.onErrorContainer
            : HealingDesignSystem.adaptivePrimaryText(context);

    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isUser
                      ? (constraints.maxWidth - 68)
                          .clamp(0.0, constraints.maxWidth * 0.84)
                          .toDouble()
                      : constraints.maxWidth * 0.84,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isUser ? 18 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 18),
                        ),
                        border: isUser
                            ? null
                            : Border.all(
                                color: HealingDesignSystem.adaptiveCardBorder(
                                  context,
                                ),
                              ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: message.isLoading
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('正在整理...',
                                      style: TextStyle(color: textColor)),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (message.image != null) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _EncryptedChatImage(
                                        message.image!,
                                        width: 240,
                                        height: 180,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                          width: 240,
                                          height: 120,
                                          alignment: Alignment.center,
                                          color: colorScheme.surfaceContainer,
                                          child: const Text('照片目前無法顯示'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isUser) ...[
                                        Icon(
                                          Icons.auto_awesome_rounded,
                                          size: 18,
                                          color: colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Flexible(
                                        child: SelectionArea(
                                          child: Text(
                                            message.text,
                                            softWrap: true,
                                            overflow: TextOverflow.visible,
                                            textWidthBasis:
                                                TextWidthBasis.parent,
                                            textAlign: TextAlign.left,
                                            style: TextStyle(
                                              color: textColor,
                                              height: 1.55,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ),
                    if (message.canRetry && onRetry != null)
                      TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('重試'),
                      ),
                    if (message.sources.isNotEmpty)
                      TextButton(
                        onPressed: () => AiContextSourcesSheet.show(
                            context, message.sources),
                        child: const Text('查看本次參考資料'),
                      ),
                  ],
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage: userPhotoUrl?.trim().isNotEmpty == true
                      ? NetworkImage(userPhotoUrl!.trim())
                      : null,
                  child: userPhotoUrl?.trim().isNotEmpty == true
                      ? null
                      : Icon(
                          Icons.person_rounded,
                          size: 20,
                          color: colorScheme.onPrimaryContainer,
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EncryptedChatImage extends StatefulWidget {
  const _EncryptedChatImage(
    this.attachment, {
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
  });

  final InneraAiImageAttachment attachment;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<_EncryptedChatImage> createState() => _EncryptedChatImageState();
}

class _EncryptedChatImageState extends State<_EncryptedChatImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _EncryptedChatImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.storagePath != widget.attachment.storagePath) {
      _load();
    }
  }

  void _load() {
    _bytes = InneraAiChatImageService().downloadForDisplay(widget.attachment);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.data!,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              gaplessPlayback: true,
            );
          }
          if (snapshot.hasError) {
            final errorBuilder = widget.errorBuilder;
            if (errorBuilder != null) {
              return errorBuilder(
                context,
                snapshot.error!,
                StackTrace.current,
              );
            }
            return const Center(child: Icon(Icons.broken_image_outlined));
          }
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
}
