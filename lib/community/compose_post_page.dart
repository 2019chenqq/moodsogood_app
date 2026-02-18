import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'utils/anon_name.dart';

import 'models/post.dart';
import 'providers/rooms_provider.dart';
import 'providers/room_feed_provider.dart';
import 'widgets/community_style.dart';

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
  String _anonName = '匿名者';

  @override
  void initState() {
    super.initState();
    _loadAnonName();
  }

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

  Future<void> _loadAnonName() async {
    final name = await AnonNameService.getOrCreate();
    if (!mounted) return;
    setState(() => _anonName = name);
  }

  String get _effectiveAnonName => _anonName.trim().isEmpty ? '匿名者' : _anonName.trim();

  @override
  Widget build(BuildContext context) {
    final roomsProvider = context.watch<RoomsProvider>();

    return Scaffold(
      backgroundColor: CommunityStyle.background,
      appBar: AppBar(
        title: const Text('發一篇匿名貼文'),
        elevation: 0,
        backgroundColor: CommunityStyle.surfaceSoft,
        foregroundColor: CommunityStyle.text,
      ),
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
              decoration: const InputDecoration(
                labelText: '選擇房間',
                filled: true,
                fillColor: CommunityStyle.surface,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '匿名身分：$_effectiveAnonName',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: CommunityStyle.muted),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  hintText: '你想說什麼？',
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
                    authorAnonId: _effectiveAnonName,
                    content: text,
                    createdAt: DateTime.now(),
                    allowReplies: _allowReplies,
                  );

                  Navigator.pop(context, post);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: CommunityStyle.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('發送'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}