import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
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
          alignment: Alignment.centerLeft,
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
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                        textWidthBasis: TextWidthBasis.parent,
                                        textAlign: TextAlign.justify,
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
