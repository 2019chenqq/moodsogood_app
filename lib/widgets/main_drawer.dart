import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart'; // 🔥 存照片用
import 'package:image_picker/image_picker.dart'; // 🔥 選照片用
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings_page.dart';
import '../pages/feedback_page.dart';
import '../pages/hub_pages.dart';
import '../pages/life_overview_page.dart';
import '../pages/profile_page.dart';
import '../constants/healing_design_system.dart';
import '../medication/medication_scan_page.dart';

class MainDrawer extends StatefulWidget {
  const MainDrawer({super.key});

  @override
  State<MainDrawer> createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  bool _isUploading = false; // 用來控制轉圈圈

  static const _userGuideUrl =
      'https://2019chenqq.github.io/Innera/guide/daily-record.html';

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
      await storageRef.putData(
        await image.readAsBytes(),
        SettableMetadata(contentType: 'image/jpeg'),
      );

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
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
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
    final baseTheme = Theme.of(context);
    final drawerTextTheme =
        baseTheme.textTheme.apply(fontFamily: HealingDesignSystem.fontFamily);
    final drawerPrimaryTextTheme = baseTheme.primaryTextTheme
        .apply(fontFamily: HealingDesignSystem.fontFamily);
    final drawerTitleStyle = HealingDesignSystem.bodyLarge.copyWith(
      fontFamily: HealingDesignSystem.fontFamily,
      color: HealingDesignSystem.deepText,
    );
    final drawerDangerStyle = drawerTitleStyle.copyWith(
      color: HealingDesignSystem.dangerRed,
    );

    return Theme(
      data: baseTheme.copyWith(
        textTheme: drawerTextTheme,
        primaryTextTheme: drawerPrimaryTextTheme,
        listTileTheme: baseTheme.listTileTheme.copyWith(
          titleTextStyle: drawerTitleStyle,
        ),
      ),
      child: Drawer(
        backgroundColor: HealingDesignSystem.softBlue,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(
                accountName,
                style: HealingDesignSystem.titleMedium.copyWith(
                  fontFamily: HealingDesignSystem.fontFamily,
                  color: HealingDesignSystem.primaryBlue,
                ),
              ),
              accountEmail: Text(
                user?.email ?? '',
                style: HealingDesignSystem.bodySmall.copyWith(
                  fontFamily: HealingDesignSystem.fontFamily,
                  color: HealingDesignSystem.mutedText,
                ),
              ),
              currentAccountPicture: GestureDetector(
                onTap: _isUploading ? null : _pickAndUploadImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: HealingDesignSystem.cardBg,
                      backgroundImage:
                          photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null
                          ? Icon(Icons.person,
                              size: 40, color: HealingDesignSystem.mutedText)
                          : null,
                    ),
                    if (_isUploading)
                      const Positioned.fill(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: HealingDesignSystem.primaryBlue,
                        ),
                      ),
                    if (!_isUploading)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: HealingDesignSystem.cardBg,
                            shape: BoxShape.circle,
                            boxShadow: [HealingDesignSystem.shadowLight()],
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: HealingDesignSystem.primaryBlue,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              decoration: const BoxDecoration(
                color: HealingDesignSystem.softBlue,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A7DB7D8),
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
            // 主要分區
            ListTile(
              leading:
                  Icon(Icons.edit_note, color: HealingDesignSystem.primaryBlue),
              title: Text('紀錄系統', style: drawerTitleStyle),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const RecordHubPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.calendar_month,
                  color: HealingDesignSystem.primaryBlue),
              title: Text('生活軌跡', style: drawerTitleStyle),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LifeOverviewPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.document_scanner_outlined,
                  color: HealingDesignSystem.primaryBlue),
              title: Text('藥單掃描測試', style: drawerTitleStyle),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MedicationScanPage(),
                  ),
                );
              },
            ),
            Divider(
                color: HealingDesignSystem.lineColor, thickness: 1, height: 24),
            ListTile(
              leading: Icon(Icons.person_outline,
                  color: HealingDesignSystem.primaryBlue),
              title: Text('個人資料', style: drawerTitleStyle),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
              },
            ),

            ListTile(
              leading: Icon(Icons.tune_rounded,
                  color: HealingDesignSystem.primaryBlue),
              title: Text('設定', style: drawerTitleStyle),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.help_outline,
                  color: HealingDesignSystem.primaryBlue),
              title: Text('幫助與回饋', style: drawerTitleStyle),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FeedbackPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.menu_book_outlined,
                  color: HealingDesignSystem.primaryBlue),
              title: Text('使用指南', style: drawerTitleStyle),
              onTap: () {
                Navigator.pop(context);
                _openUserGuide();
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: HealingDesignSystem.dangerRed),
              title: Text('登出', style: drawerDangerStyle),
              onTap: () async {
                await _signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}
