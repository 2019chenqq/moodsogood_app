import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'compose_post_page.dart';
import 'room_page.dart';
import 'widgets/room_card.dart';
import 'widgets/warm_message_card.dart';
import 'providers/rooms_provider.dart';

class CommunityHomePage extends StatelessWidget {
  static const routeName = '/community';
  const CommunityHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = context.watch<RoomsProvider>().rooms;

    return Scaffold(
      appBar: AppBar(title: const Text('樹洞討論區')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, ComposePostPage.routeName),
        icon: const Icon(Icons.add),
        label: const Text('發一篇匿名貼文'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                decoration: InputDecoration(
                  hintText: '搜尋想聊的主題',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: WarmMessageCard(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final room = rooms[index];
                  return RoomCard(
                    room: room,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        RoomPage.routeName,
                        arguments: room.id,
                      );
                    },
                  );
                },
                childCount: rooms.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}