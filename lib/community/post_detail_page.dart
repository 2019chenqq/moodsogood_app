import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'utils/anon_name.dart';

import 'providers/post_thread_provider.dart';
import 'providers/room_feed_provider.dart';
import 'widgets/empathy_bar.dart';
import 'widgets/safety_banner.dart';
import 'widgets/community_style.dart';

class PostDetailPage extends StatelessWidget {
  static const routeName = '/community/post';
  const PostDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final postId = ModalRoute.of(context)!.settings.arguments as String;

    return ChangeNotifierProvider(
      create: (_) => PostThreadProvider(postId),
      child: Builder(
        builder: (context) {
          final thread = context.watch<PostThreadProvider>();
          final ctrl = TextEditingController();

          return Scaffold(
            backgroundColor: CommunityStyle.background,
            appBar: AppBar(
              title: const Text('貼文'),
              elevation: 0,
              backgroundColor: CommunityStyle.surfaceSoft,
              foregroundColor: CommunityStyle.text,
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '刪除貼文',
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('刪除貼文？'),
                        content: const Text('刪除後無法復原。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('刪除'),
                          ),
                        ],
                      ),
                    );

                    if (ok == true && context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                ),
              ],
            ),
            body: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SafetyBanner(show: true),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      Card(
                        color: CommunityStyle.surface,
                        shape: CommunityStyle.cardShape,
                        elevation: 0.5,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('匿名者 A17',
                                  style: Theme.of(context).textTheme.labelLarge),
                              const SizedBox(height: 10),
                              Text(
                                '（示範）這裡放貼文全文。之後接 Firestore 時，'
                                '用 postId 去取貼文內容。',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              EmpathyBar(
                                hug: thread.hug,
                                listen: thread.listen,
                                hope: thread.hope,
                                heart: thread.heart,
                                onReact: (t) => thread.react(t),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('回覆', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...thread.comments.map((c) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            color: CommunityStyle.surface,
                            shape: CommunityStyle.cardShape,
                            elevation: 0.5,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('匿名者 ${c.authorAnonId}',
                                      style: Theme.of(context).textTheme.labelLarge),
                                  const SizedBox(height: 6),
                                  Text(c.content),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            decoration: InputDecoration(
                              hintText: '匿名回應…',
                              filled: true,
                              fillColor: CommunityStyle.surface,
                              hintStyle: const TextStyle(color: CommunityStyle.muted),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: CommunityStyle.outline),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: CommunityStyle.outline),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: CommunityStyle.accent, width: 1.2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          onPressed: () async {
                            final anonName = await AnonNameService.getOrCreate();

                            thread.addComment(ctrl.text, anonName);
                            ctrl.clear();
                            FocusScope.of(context).unfocus();
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: CommunityStyle.accent,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
