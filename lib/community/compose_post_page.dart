import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/post.dart';
import 'providers/rooms_provider.dart';
import 'providers/room_feed_provider.dart';

class ComposePostPage extends StatefulWidget {
  static const routeName = '/community/compose';
  const ComposePostPage({super.key});

  @override
  State<ComposePostPage> createState() => _ComposePostPageState();
}

class _ComposePostPageState extends State<ComposePostPage> {
  final _ctrl = TextEditingController();
  bool _allowReplies = true;
  String? _selectedRoomId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && _selectedRoomId == null) {
      _selectedRoomId = arg;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomsProvider = context.watch<RoomsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('發一篇匿名貼文')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedRoomId ?? roomsProvider.rooms.first.id,
              items: roomsProvider.rooms
                  .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedRoomId = v),
              decoration: const InputDecoration(labelText: '選擇房間'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  hintText: '你想說什麼？',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('允許他人回應'),
              value: _allowReplies,
              onChanged: (v) => setState(() => _allowReplies = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final roomId = _selectedRoomId ?? roomsProvider.rooms.first.id;
                  final text = _ctrl.text.trim();
                  if (text.isEmpty) return;

                  final post = Post(
                    id: 'new_${DateTime.now().millisecondsSinceEpoch}',
                    roomId: roomId,
                    authorAnonId: '你',
                    content: text,
                    createdAt: DateTime.now(),
                    allowReplies: _allowReplies,
                  );

                  // ⚠ MVP：如果你是從 RoomPage 進來，RoomFeedProvider 在上一頁存在，
                  // 你可以用 Navigator.pop 回去後再 insert。這裡先簡化：直接 pop。
                  Navigator.pop(context);

                  // 進階：你要做到「發文後立即插入列表」，我下一步可以幫你加
                  // (用 result 回傳 post 給 RoomPage，再 feed.addPost)
                },
                child: const Text('發送'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}