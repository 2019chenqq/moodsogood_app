import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
                // 1. 加上 async
                onPressed: () async {
                  final roomId = _selectedRoomId ?? roomsProvider.rooms.first.id;
                  final text = _ctrl.text.trim();
                  if (text.isEmpty) return;

                  // 2. 為了避免用戶狂按按鈕，可以在這裡加一個簡單的 Loading 提示
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('發送中...')),
                  );

                  try {
                    // 3. 呼叫我們部署在 Firebase 的 Cloud Function
                    final callable = FirebaseFunctions.instance.httpsCallable('createCommunityPost');
                    
                    // 傳遞資料給後端 (注意：這裡完全不傳匿名名稱，讓後端自己去查！)
                    await callable.call({
                      'roomId': roomId,
                      'content': text,
                      'allowReplies': _allowReplies,
                    });

                    // 4. 發文成功後，關閉這個頁面
                    if (context.mounted) {
                      Navigator.pop(context, true); // 回傳 true 代表發文成功
                    }
                  } catch (e) {
                    // 5. 如果發生錯誤 (例如沒網路、後端報錯)
                    print("發文失敗: $e");
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('發文失敗，請稍後再試。')),
                      );
                    }
                  }
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