import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'rooms_management_page.dart';
import '../../analytics_service.dart';

/// 看板審核頁面（管理員用）
class RoomRequestsAdminPage extends StatefulWidget {
  const RoomRequestsAdminPage({super.key});

  @override
  State<RoomRequestsAdminPage> createState() => _RoomRequestsAdminPageState();
}

class _RoomRequestsAdminPageState extends State<RoomRequestsAdminPage> {

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('room_requests_admin_page');
  }

  static const _requestsCollection = 'community_room_requests';
  static const _roomsCollection = 'community_rooms';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('看板申請審核'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: '看板管理',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RoomsManagementPage(),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(_requestsCollection)
            .snapshots(),
        builder: (context, snap) {
          debugPrint('📋 Admin page - connectionState: ${snap.connectionState}');
          debugPrint('📋 Admin page - hasData: ${snap.hasData}, docs: ${snap.data?.docs.length ?? 0}');
          
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            debugPrint('❌ Admin query error: ${snap.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('讀取申請失敗：${snap.error}'),
                ],
              ),
            );
          }

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            debugPrint('ℹ️ Admin page - 沒有申請');
            return const Center(
              child: Text('沒有申請'),
            );
          }

          debugPrint('✅ Admin page - 加載 ${snap.data!.docs.length} 個申請');

          // 在客户端排序和過濾
          var docs = snap.data!.docs;
          docs.sort((a, b) {
            final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
            final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
            return bTime.compareTo(aTime); // 降序
          });
          
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
            debugPrint('ℹ️ Admin page - 沒有有效申請');
            return const Center(
              child: Text('沒有申請'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              final title = (data['title'] ?? '').toString();
              final description = (data['description'] ?? '').toString();
              final status = (data['status'] ?? 'pending').toString();
              final requesterEmail = (data['requesterEmail'] ?? '').toString();
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

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
                                  title,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  requesterEmail,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(status),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _statusLabel(status),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(description),
                      if (createdAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '申請時間：${createdAt.toString().split('.').first}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                      if (status == 'pending') ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () =>
                                  _rejectRequest(doc.id, context),
                              child: const Text('拒絕'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () =>
                                  _approveRequest(doc.id, data, context),
                              child: const Text('通過'),
                            ),
                          ],
                        ),
                      ],
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

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return '已通過';
      case 'rejected':
        return '已拒絕';
      default:
        return '待審核';
    }
  }

  Future<void> _approveRequest(
    String requestId,
    Map<String, dynamic> data,
    BuildContext context,
  ) async {
    try {
      // 1. 標記申請為已通過
      await FirebaseFirestore.instance
          .collection(_requestsCollection)
          .doc(requestId)
          .update({'status': 'approved'});

      // 2. 建立新看板
      final roomRef = await FirebaseFirestore.instance
          .collection(_roomsCollection)
          .add({
        'name': (data['title'] ?? '未命名看板').toString(),
        'description': (data['description'] ?? '').toString(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdByRequest': requestId,
        'createdBy': (data['requesterUid'] ?? '').toString(),
      });

      // 3. 將看板 ID 寫回申請
      await FirebaseFirestore.instance
          .collection(_requestsCollection)
          .doc(requestId)
          .update({
        'roomId': roomRef.id,
        'roomCreatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已通過，看板已建立')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通過失敗：$e')),
      );
    }
  }

  Future<void> _rejectRequest(
    String requestId,
    BuildContext context,
  ) async {
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('拒絕申請'),
        content: TextField(
          controller: reasonController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '填寫拒絕原因（會顯示給申請者）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await FirebaseFirestore.instance
                    .collection(_requestsCollection)
                    .doc(requestId)
                    .update({
                  'status': 'rejected',
                  'rejectionReason': reasonController.text.trim(),
                });

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已拒絕')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('拒絕失敗：$e')),
                );
              }
            },
            child: const Text('確認拒絕'),
          ),
        ],
      ),
    );
  }
}
