import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart'; // 🔥 存照片用
import 'package:image_picker/image_picker.dart';         // 🔥 選照片用
import 'dart:io';
import '../daily/daily_record_screen.dart';
import '../daily/daily_record_history.dart';
import '../diary/diary_home_page.dart';
import '../settings_page.dart';
import '../pages/feesback_page.dart';

class MainDrawer extends StatefulWidget {
  const MainDrawer({super.key});

  @override
  State<MainDrawer> createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  bool _isUploading = false; // 用來控制轉圈圈

  // 🔥 上傳照片的核心功能
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
          const SnackBar(content: Text('大頭貼更新成功！🎉')),
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

  @override
  Widget build(BuildContext context) {
    // 每次 build 都重新抓取 user，確保顯示最新的 photoURL
    final user = FirebaseAuth.instance.currentUser;
    final String displayName = user?.email ?? '使用者';
    final String? photoUrl = user?.photoURL;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
  accountName: Text(
    displayName,
    style: const TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 18,
    ),
  ),

  // 這裡只在「上傳中」時顯示文字，平常什麼都不顯示
  accountEmail: _isUploading
      ? const Text(
          '正在上傳...',
          style: TextStyle(color: Colors.white70),
        )
      : const SizedBox.shrink(),

            
            // 🔥 頭貼區塊
            currentAccountPicture: GestureDetector(
              onTap: _isUploading ? null : _pickAndUploadImage, // 點擊觸發上傳
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null 
                        ? const Icon(Icons.person, size: 40, color: Colors.grey) 
                        : null,
                  ),
                  
                  // 如果正在上傳，顯示轉圈圈
                  if (_isUploading)
                    const Positioned.fill(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    
                  // 如果沒在上傳，顯示一個小相機圖示提示使用者可以點
                  if (!_isUploading)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color.fromARGB(255, 255, 255, 255),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, size: 14, color: Color.fromARGB(255, 80, 194, 182)),
                      ),
                    ),
                ],
              ),
            ),
            
            decoration: BoxDecoration(
              color: Color.fromARGB(255, 28, 185, 169),
            ),
          ),
          // 2. 選單項目
          ListTile(
            leading: const Icon(Icons.dashboard_outlined), // 圖示：每日紀錄
            title: const Text('每日紀錄 (首頁)'),
            onTap: () {
              Navigator.pop(context); // 關閉側邊欄
              // 跳轉並取代當前頁面 (避免按上一頁鬼打牆)
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DailyRecordScreen()),
                            );
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined), // 圖示：日記
            title: const Text('我的日記'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DiaryHomePage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.insights), // 圖示：統計
            title: const Text('統計圖表'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DailyRecordHistory()),
              );
            },
          ),

          const Divider(),

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
          const Divider(),

          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('回饋與建議'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FeedbackPage()),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('登出', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              // 這裡通常會跳轉回登入頁，暫時先關閉
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}