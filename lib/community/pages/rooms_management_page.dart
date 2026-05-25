import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../analytics_service.dart';

/// 看板管理頁面（刪除重複看板）
class RoomsManagementPage extends StatefulWidget {
  const RoomsManagementPage({super.key});

  @override
  State<RoomsManagementPage> createState() => _RoomsManagementPageState();
}

class _RoomsManagementPageState extends State<RoomsManagementPage> {

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('rooms_management_page');
  }

  static const _roomsCollection = 'community_rooms';

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('看板管理')),
        body: const Center(
          child: Text('請先登入'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('看板管理'),
            Text(
              '用戶: ${currentUser.email ?? currentUser.uid}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(_roomsCollection)
            .snapshots(),
        builder: (context, snap) {
          debugPrint('📊 Rooms management snapshot state: ${snap.connectionState}');
          debugPrint('📊 Current user: ${currentUser.uid}');

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            debugPrint('❌ Rooms query error: ${snap.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      '無法加載看板列表',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '錯誤：${snap.error}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            debugPrint('ℹ️ No rooms found');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_open_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('沒有看板'),
                  const SizedBox(height: 8),
                  Text(
                    '你的 UID: ${currentUser.uid}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          debugPrint('✅ Rooms loaded: ${snap.data!.docs.length} items');

          // 在客户端排序
          var docs = snap.data!.docs;
          docs.sort((a, b) {
            final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
            final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
            return bTime.compareTo(aTime); // 降序
          });

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              final name = (data['name'] ?? '未命名看板').toString();
              final description = (data['description'] ?? '').toString();
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
              final createdBy = (data['createdBy'] ?? '').toString();

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ID: ${doc.id}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: '刪除看板',
                            onPressed: () => _confirmDeleteRoom(context, doc.id, name),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (description.isNotEmpty) ...[
                        Text(description),
                        const SizedBox(height: 8),
                      ],
                      if (createdAt != null) ...[
                        Text(
                          '建立時間：${createdAt.toString().split('.').first}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (createdBy.isNotEmpty)
                        Text(
                          '建立者 UID：$createdBy',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _confirmDeleteRoom(BuildContext context, String roomId, String roomName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除看板「$roomName」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // ⚠️ 在異步前先取得 ScaffoldMessenger
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              await _deleteRoom(scaffoldMessenger, roomId, roomName);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRoom(
    ScaffoldMessengerState messenger,
    String roomId,
    String roomName,
  ) async {
    try {
      debugPrint('🗑️ 開始刪除看板：$roomId ($roomName)');

      // 1. 找到對應的申請並清空 roomId
      final requestsSnap = await FirebaseFirestore.instance
          .collection('community_room_requests')
          .where('roomId', isEqualTo: roomId)
          .get();
      
      for (final doc in requestsSnap.docs) {
        await doc.reference.update({'roomId': ''});
        debugPrint('📋 已清空申請 ${doc.id} 的 roomId');
      }

      // 2. 刪除看板
      await FirebaseFirestore.instance
          .collection(_roomsCollection)
          .doc(roomId)
          .delete();

      debugPrint('✅ 看板已刪除：$roomId');

      if (!mounted) return;
      
      messenger.showSnackBar(
        SnackBar(content: Text('✅ 看板「$roomName」已刪除')),
      );
    } catch (e) {
      debugPrint('❌ 刪除看板失敗：$e');

      if (!mounted) return;
      
      messenger.showSnackBar(
        SnackBar(content: Text('❌ 刪除失敗：$e')),
      );
    }
  }
}
