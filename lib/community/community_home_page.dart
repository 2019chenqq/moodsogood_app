import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'compose_post_page.dart';
import 'room_page.dart';
import 'models/post.dart';
import 'models/room.dart';
import 'widgets/room_card.dart';
import 'widgets/warm_message_card.dart';
import 'providers/rooms_provider.dart';
import '../widgets/main_drawer.dart';
import 'widgets/community_style.dart';
import 'pages/room_requests_admin_page.dart';

class CommunityHomePage extends StatefulWidget {
  static const routeName = '/community';
  const CommunityHomePage({super.key});

  @override
  State<CommunityHomePage> createState() => _CommunityHomePageState();
}

class _CommunityHomePageState extends State<CommunityHomePage> with TickerProviderStateMixin {
  static const _requestsCollection = 'community_room_requests';
  static const _roomsCollection = 'community_rooms';
  final Set<String> _processingRoomRequests = {};
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = context.watch<RoomsProvider>().rooms;

  final communityTheme = Theme.of(context).copyWith(
    // ✅ 只影響討論區（community）內的卡片外觀，不會跟全域打架
    cardTheme: const CardThemeData(
      elevation: 0.5,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      color: CommunityStyle.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: CommunityStyle.outline, width: 1),
      ),
    ),

    // ✅ 讓搜尋框/輸入框也統一（你原本每個 border 都寫一遍，這樣更順）
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CommunityStyle.surface,
      hintStyle: const TextStyle(color: CommunityStyle.muted),
      prefixIconColor: CommunityStyle.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: CommunityStyle.surfaceSoft,
      foregroundColor: CommunityStyle.text,
      surfaceTintColor: Colors.transparent,
    ),
  );

  return Theme(
    data: communityTheme,
    child: Scaffold(
      drawer: const MainDrawer(),
      backgroundColor: CommunityStyle.background,
      appBar: AppBar(
        title: Text('樹洞討論區'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '聊天室'),
            Tab(text: '申請看板'),
          ],
        ),
        actions: [
          // 管理員審核按鈕（對所有登入用戶顯示）
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: '看板申請審核',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RoomRequestsAdminPage(),
                ),
              ),
            ),
          ),
        ],      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final post = await Navigator.pushNamed(
            context,
            ComposePostPage.routeName,
          ) as Post?;

          if (post != null) {
            Navigator.pushNamed(
              context,
              RoomPage.routeName,
              arguments: {
                'roomId': post.roomId,
                'initialPost': post,
              },
            );
          }
        },
        backgroundColor: CommunityStyle.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('發一篇匿名貼文'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: 聊天室
          _buildChatRoomsTab(context, rooms),
          // Tab 2: 申請看板
          _buildBoardRequestTab(context),
        ],
      ),
    ),
  );
}

// 聊天室 Tab
Widget _buildChatRoomsTab(BuildContext context, List<Room> rooms) {
  return CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '搜尋想聊的主題',
              prefixIcon: Icon(Icons.search),
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
                onTap: () => Navigator.pushNamed(
                  context,
                  RoomPage.routeName,
                  arguments: room.id,
                ),
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
  );
}

// 申請看板 Tab
Widget _buildBoardRequestTab(BuildContext context) {
  return CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildBoardRequestCard(context),
        ),
      ),
    ],
  );
}

  Widget _buildBoardRequestCard(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '申請開設看板',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '由心域團隊審核通過後自動建立。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: CommunityStyle.muted),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: user == null ? null : () => _openRequestDialog(context),
                icon: const Icon(Icons.note_add_outlined, size: 18),
                label: const Text('提出申請'),
              ),
            ),
            const SizedBox(height: 10),
            if (user == null)
              Text(
                '請先登入以提交申請。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: CommunityStyle.muted),
              )
            else
              _buildRequestStatusList(context, user.uid),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestStatusList(BuildContext context, String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(_requestsCollection)
          .where('requesterUid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        debugPrint(
          '📋 Request list snapshot: connectionState=${snap.connectionState}, hasData=${snap.hasData}, docs=${snap.data?.docs.length ?? 0}',
        );

        if (snap.hasError) {
          return Text(
            '讀取申請失敗：${snap.error}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.red),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Text(
            '尚無申請紀錄。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: CommunityStyle.muted),
          );
        }

        // 在客户端排序和限制
        var docs = snap.data!.docs;
        docs.sort((a, b) {
          final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
          final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
          return bTime.compareTo(aTime); // 降序
        });
        docs = docs.take(5).toList();

        // 過濾掉已批准但看板已刪除的申請
        docs = docs.where((doc) {
          final data = doc.data();
          final status = (data['status'] ?? 'pending').toString();
          final roomId = (data['roomId'] ?? '').toString();
          
          // 如果是已批准但沒有 roomId，說明看板已被刪除，過濾掉
          if (status == 'approved' && roomId.isEmpty) {
            return false;
          }
          return true;
        }).toList();

        if (docs.isEmpty) {
          return Text(
            '尚無申請紀錄。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: CommunityStyle.muted),
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data();
            final title = (data['title'] ?? '').toString();
            final status = (data['status'] ?? 'pending').toString();
            final reason = (data['rejectionReason'] ?? '').toString();
            final statusLabel = _statusLabel(status);

            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title.isEmpty ? '未命名看板' : title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusLabel),
                  if (status == 'rejected' && reason.isNotEmpty)
                    Text('原因：$reason'),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return '狀態：已通過（看板已建立）';
      case 'rejected':
        return '狀態：已拒絕';
      default:
        return '狀態：待審核';
    }
  }

  Future<void> _openRequestDialog(BuildContext context) async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String? errorText;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: const Text('申請開設看板'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  TextField(
                    controller: titleController,
                    enabled: !isSubmitting,
                    decoration: InputDecoration(
                      labelText: '看板名稱',
                      errorText: errorText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    enabled: !isSubmitting,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '看板簡述（審核用）',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                  final title = titleController.text.trim();
                  if (title.isEmpty) {
                    setState(() => errorText = '請輸入看板名稱');
                    return;
                  }

                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    setState(() => errorText = '請先登入');
                    return;
                  }

                  setState(() {
                    isSubmitting = true;
                    errorText = null;
                  });

                  try {
                    debugPrint('🔄 開始提交申請：title=$title, uid=${user.uid}');
                    
                    // 直接送出申請，不檢查是否已有待審核
                    final docRef = await FirebaseFirestore.instance
                        .collection(_requestsCollection)
                        .add({
                      'title': title,
                      'description': descController.text.trim(),
                      'requesterUid': user.uid,
                      'requesterEmail': user.email,
                      'status': 'pending',
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    debugPrint('✅ 申請已寫入 Firestore，docId=${docRef.id}');

                    if (!mounted) return;
                    titleController.clear();
                    descController.clear();
                    setState(() => isSubmitting = false);
                    
                    if (!mounted) return;
                    Navigator.pop(dialogContext);
                    
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ 申請已送出，等待審核。'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    setState(() => isSubmitting = false);
                    debugPrint('❌ 申請失敗：$e');
                    setState(() => errorText = '送出失敗：$e');
                  }
                },
                child: const Text('送出申請'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _ensureRoomForApprovedRequest(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final status = (data['status'] ?? 'pending').toString();
    final roomId = (data['roomId'] ?? '').toString();
    if (status != 'approved' || roomId.isNotEmpty) return;

    if (_processingRoomRequests.contains(doc.id)) return;
    _processingRoomRequests.add(doc.id);

    try {
      final roomRef = await FirebaseFirestore.instance
          .collection(_roomsCollection)
          .add({
        'name': (data['title'] ?? '未命名看板').toString(),
        'description': (data['description'] ?? '').toString(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdByRequest': doc.id,
        'createdBy': (data['requesterUid'] ?? '').toString(),
      });

      await doc.reference.update({
        'roomId': roomRef.id,
        'roomCreatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _processingRoomRequests.remove(doc.id);
      return;
    }

    _processingRoomRequests.remove(doc.id);
  }
}
