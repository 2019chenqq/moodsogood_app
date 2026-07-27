import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../innera_ai_message.dart';
import 'ai_context_sources_sheet.dart';

class AiMessageBubble extends StatelessWidget {
  const AiMessageBubble({super.key, required this.message, this.onRetry});

  final InneraAiMessage message;
  final VoidCallback? onRetry;

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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                            Text('正在整理...', style: TextStyle(color: textColor)),
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
                              child: SelectableText(
                                message.text,
                                style: TextStyle(
                                  color: textColor,
                                  height: 1.55,
                                  fontSize: 15,
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
                  onPressed: () =>
                      AiContextSourcesSheet.show(context, message.sources),
                  child: const Text('查看本次參考資料'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
