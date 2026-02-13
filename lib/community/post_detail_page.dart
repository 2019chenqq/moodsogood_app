import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/post_thread_provider.dart';
import 'providers/room_feed_provider.dart';
import 'widgets/empathy_bar.dart';
import 'widgets/safety_banner.dart';

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
            appBar: AppBar(title: const Text('貼文')),
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
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          onPressed: () {
                            thread.addComment(ctrl.text);
                            ctrl.clear();
                            FocusScope.of(context).unfocus();
                          },
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
