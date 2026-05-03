import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 用於 kDebugMode
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart'; // 🔥 存照片用
import 'package:image_picker/image_picker.dart'; // 🔥 選照片用
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:io';
import '../settings_page.dart';
import '../pages/feesback_page.dart';
import '../pages/hub_pages.dart';
import '../pages/life_overview_page.dart';
import '../pages/profile_page.dart';
import '../Sign_in_page.dart';

class MainDrawer extends StatefulWidget {
  const MainDrawer({super.key});

  @override
  State<MainDrawer> createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  bool _isUploading = false; // 用來控制轉圈圈

  static const _userGuideUrl =
      'https://www.notion.so/App-3557a479d31f800f842dd1ffb9ef5409?source=copy_link';

  /// 從 Firestore 加載日記記錄用於導出
  Future<void> _pickAndUploadImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 1. 從相簿選照片
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512, // 縮小一點，節省流量
        maxHeight: 512,
        imageQuality: 70,
      );

      if (image == null) return; // 使用者取消選取

      setState(() => _isUploading = true); // 開始轉圈圈

      // 2. 設定上傳路徑：user_avatars/使用者ID.jpg
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_avatars')
          .child('${user.uid}.jpg');

      // 3. 上傳檔案
      await storageRef.putFile(File(image.path));

      // 4. 取得照片的網路連結 (URL)
      final String downloadUrl = await storageRef.getDownloadURL();

      // 5. 更新 Firebase 使用者資料
      await user.updatePhotoURL(downloadUrl);
      await user.reload(); // 強制重新整理使用者資料

      // 6. 更新畫面
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('大頭貼更新成功！')),
        );
      }
    } catch (e) {
      debugPrint('上傳失敗: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('上傳失敗，請稍後再試')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final hasGoogleProvider =
          user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

      await FirebaseAuth.instance.signOut();
      if (hasGoogleProvider) {
        final googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('登出失敗: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登出失敗：$e')),
      );
    }
  }

  Future<void> _openUserGuide() async {
    final uri = Uri.parse(_userGuideUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法開啟使用指南，請稍後再試。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 每次 build 都重新抓取 user，確保顯示最新的 photoURL
    final user = FirebaseAuth.instance.currentUser;
    final String? photoUrl = user?.photoURL;
    final displayName = (user?.displayName ?? '').trim();
    final accountName = displayName.isEmpty ? '使用者' : displayName;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              accountName,
              style: const TextStyle(
                color: Color.fromARGB(255, 25, 107, 231),
                fontSize: 17,
              ),
            ),
            accountEmail: Text(user?.email ?? ''),

            // 🔥 頭貼區塊（完整整合）
            currentAccountPicture: GestureDetector(
              onTap: _isUploading ? null : _pickAndUploadImage,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? const Icon(Icons.person, size: 40, color: Colors.grey)
                        : null,
                  ),

                  // 上傳中 → 顯示轉圈
                  if (_isUploading)
                    const Positioned.fill(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),

                  // 未上傳 → 相機提示
                  if (!_isUploading)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 14,
                          color: Color(0xFF4BB0C6),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 179, 227, 222), // Drawer header 背景色
            ),
          ),

          // 主要分區
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('紀錄'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RecordHubPage()),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: const Text('生活軌跡'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LifeOverviewPage()),
              );
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('個人資料'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('設定'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('幫助與回饋'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FeedbackPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('使用指南'),
            onTap: () {
              Navigator.pop(context);
              _openUserGuide();
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('登出', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await _signOut();
            },
          ),
        ],
      ),
    );
  }
}
