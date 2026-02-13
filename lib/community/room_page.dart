import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'post_detail_page.dart';
import 'compose_post_page.dart';
import 'providers/rooms_provider.dart';
import 'providers/room_feed_provider.dart';
import 'widgets/post_list_item.dart';
import 'widgets/safety_banner.dart';

class RoomPage extends StatelessWidget {
  static const routeName = '/community/room';
  const RoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    final roomId = ModalRoute.of(context)!.settings.arguments as String;
    final room = context.read<RoomsProvider>().byId(roomId);

    return ChangeNotifierProvider(
      create: (_) => RoomFeedProvider(roomId),
      child: Builder(
        builder: (context) {
          final feed = context.watch<RoomFeedProvider>();

          return Scaffold(
            appBar: AppBar(title: Text(room?.name ?? '房間')),
            floatingActionButton: FloatingActionButton(
              onPressed: () => Navigator.pushNamed(
                context,
                ComposePostPage.routeName,
                arguments: roomId,
              ),
              child: const Icon(Icons.edit),
            ),
            body: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SafetyBanner(show: true),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      // MVP: 先不做拉取；接 Firestore 時在這裡 reload
                      await Future<void>.delayed(const Duration(milliseconds: 500));
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: feed.posts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final post = feed.posts[i];
                        return PostListItem(
                          post: post,
                          onTap: () => Navigator.pushNamed(
                            context,
                            PostDetailPage.routeName,
                            arguments: post.id,
                          ),
                          onReact: (type) => feed.react(post.id, type),
                        );
                      },
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