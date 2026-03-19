import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'utils/anon_name.dart';

import 'models/post.dart';
import 'providers/post_thread_provider.dart';
import 'providers/room_feed_provider.dart';
import 'widgets/empathy_bar.dart';
import 'widgets/safety_banner.dart';
import 'widgets/community_style.dart';

class PostDetailPage extends StatelessWidget {
  static const routeName = '/community/post';
  const PostDetailPage({super.key});

  static const List<String> _adminUids = [
    'Z6lq7OaKreebFWI9yyGRQiMZPcr1' // TODO: 填入管理員 UID
  ];

  bool _isAdmin(String? uid) => uid != null && _adminUids.contains(uid);

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args is! Post) {
      return const Scaffold(
        body: Center(child: Text('找不到貼文內容')),
      );
    }
    final post = args;

    return ChangeNotifierProvider(
      create: (_) => PostThreadProvider(post.id, post),
      child: Builder(
        builder: (context) {
          final thread = context.watch<PostThreadProvider>();
          final currentUid = FirebaseAuth.instance.currentUser?.uid;
          final isAdmin = _isAdmin(currentUid);
          final ctrl = TextEditingController();
          final inputFocus = FocusNode();

          return Scaffold(
            backgroundColor: CommunityStyle.background,
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('貼文'),
                  Text(
                    currentUid == null ? '未登入' : 'UID: $currentUid',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: CommunityStyle.muted),
                  ),
                ],
              ),
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
                              Text(
                                post.authorAnonId,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                post.content,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              EmpathyBar(
                                post: post,
                                onReact: (t, wasReacted) =>
                                    thread.react(t, wasReacted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('回覆', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '只有自己留言或管理員可以刪除',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: CommunityStyle.muted),
                      ),
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
                                  Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: () {
                                            final mention = '@${c.authorAnonId} ';
                                            if (!ctrl.text.startsWith(mention)) {
                                              ctrl.text = '${mention}${ctrl.text}';
                                              ctrl.selection = TextSelection.collapsed(
                                                offset: ctrl.text.length,
                                              );
                                            }
                                            FocusScope.of(context).requestFocus(inputFocus);
                                          },
                                          child: Text(
                                            c.authorAnonId,
                                            style: Theme.of(context).textTheme.labelLarge,
                                          ),
                                        ),
                                      ),
                                      if (isAdmin || (currentUid != null && c.authorUid == currentUid))
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (currentUid != null && c.authorUid == currentUid)
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined),
                                                tooltip: '編輯留言',
                                                onPressed: () async {
                                                  final controller = TextEditingController(text: c.content);
                                                  final ok = await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      title: const Text('編輯留言'),
                                                      content: TextField(
                                                        controller: controller,
                                                        minLines: 2,
                                                        maxLines: 4,
                                                        decoration: const InputDecoration(
                                                          hintText: '輸入新的留言內容',
                                                        ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context, false),
                                                          child: const Text('取消'),
                                                        ),
                                                        FilledButton(
                                                          onPressed: () => Navigator.pop(context, true),
                                                          child: const Text('儲存'),
                                                        ),
                                                      ],
                                                    ),
                                                  );

                                                  if (ok == true) {
                                                    thread.updateComment(c.id, controller.text);
                                                  }
                                                },
                                              ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline),
                                              tooltip: '刪除留言',
                                              onPressed: () async {
                                                final ok = await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    title: const Text('刪除留言？'),
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

                                                if (ok == true) {
                                                  thread.deleteComment(c.id);
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
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
                            focusNode: inputFocus,
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
                            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

                            thread.addComment(ctrl.text, anonName, authorUid: uid);
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
