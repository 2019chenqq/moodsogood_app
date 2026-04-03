import 'dart:io';
import 'package:flutter/material.dart' as m;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

// 引入頁面
import 'pages/hub_pages.dart';
import 'pages/feesback_page.dart';

import 'Sign_in_page.dart';
import 'settings_page.dart';

class HomeShell extends m.StatefulWidget {
  const HomeShell({super.key});

  @override
  m.State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends m.State<HomeShell> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _photoUrl;
  String _displayName = '使用者';
  String _email = '';
  bool _isUploading = false;

  // 🔥 定義底部導航頁面
  final List<m.Widget> _pages = const [
    RecordHubPage(), // Index 0: 紀錄
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    User? user = _auth.currentUser;
    if (user != null) {
      await user.reload();
      user = _auth.currentUser;

      setState(() {
        _photoUrl = user?.photoURL;
        _displayName = user?.displayName ?? '使用者';
        _email = user?.email ?? '';
      });

      try {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(user!.uid).get();
        if (userDoc.exists && userDoc.data() != null) {
          Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _displayName =
                data['nickname'] ?? user?.displayName ?? _displayName;
          });
        }
      } catch (e) {
        m.debugPrint('Error loading user data from Firestore: $e');
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() {
      _isUploading = true;
    });

    User? user = _auth.currentUser;
    if (user == null) return;

    try {
      File imageFile = File(pickedFile.path);
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child(user.uid)
          .child('profile.jpg');

      await storageRef.putFile(imageFile);
      final downloadUrl = await storageRef.getDownloadURL();
      await user.updatePhotoURL(downloadUrl);
      await _loadUserData();

      if (mounted) {
        m.ScaffoldMessenger.of(context).showSnackBar(
          const m.SnackBar(content: m.Text('大頭貼更新成功！')),
        );
      }
    } catch (e) {
      m.debugPrint('上傳失敗: $e');
      if (mounted) {
        m.ScaffoldMessenger.of(context).showSnackBar(
          m.SnackBar(content: m.Text('更新失敗，請稍後再試。')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      final googleSignIn = GoogleSignIn();
      await _auth.signOut();
      await googleSignIn.signOut();
      try {
        await googleSignIn.disconnect();
      } catch (_) {}

      if (mounted) {
        m.Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          m.MaterialPageRoute(builder: (_) => const SignInPage()),
          (route) => false,
        );
      }
    } catch (e) {
      m.debugPrint('Error signing out: $e');
    }
  }

  @override
  m.Widget build(m.BuildContext context) {
    const currentIndex = 0;

    return m.Scaffold(
      // 🔥 這裡很重要：如果現在顯示的是首頁(Index 0)，才顯示 AppBar
      // 如果是日記頁或統計頁，因為它們自己有 AppBar，所以這裡隱藏，避免雙重標題
      // 其他頁面不顯示這個 AppBar

      drawer: m.Drawer(
        child: m.ListView(
          padding: m.EdgeInsets.zero,
          children: [
            m.DrawerHeader(
              decoration: const m.BoxDecoration(
                color: m.Color.fromARGB(255, 6, 213, 192),
              ),
              child: m.Stack(
                children: [
                  m.Align(
                    alignment: m.Alignment.centerLeft,
                    child: m.Column(
                      crossAxisAlignment: m.CrossAxisAlignment.start,
                      mainAxisAlignment: m.MainAxisAlignment.center,
                      children: [
                        m.Stack(
                          children: [
                            m.CircleAvatar(
                              radius: 40,
                              backgroundColor: m.Colors.white,
                              backgroundImage:
                                  _photoUrl != null && !_isUploading
                                      ? m.NetworkImage(_photoUrl!)
                                      : null,
                              child: (_photoUrl == null && !_isUploading)
                                  ? const m.Icon(m.Icons.person,
                                      size: 50,
                                      color: m.Color.fromARGB(255, 6, 213, 192))
                                  : null,
                            ),
                            if (_isUploading)
                              const m.Positioned.fill(
                                child: m.CircularProgressIndicator(
                                  color: m.Colors.white,
                                ),
                              ),
                          ],
                        ),
                        const m.SizedBox(height: 10),
                        m.Text(
                          _displayName,
                          style: const m.TextStyle(
                            color: m.Colors.white,
                            fontSize: 20,
                            fontWeight: m.FontWeight.bold,
                          ),
                        ),
                        m.Text(
                          _email,
                          style: const m.TextStyle(
                            color: m.Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  m.Positioned(
                    bottom: 60,
                    left: 55,
                    child: m.GestureDetector(
                      onTap: _isUploading ? null : _pickAndUploadImage,
                      child: m.CircleAvatar(
                        radius: 15,
                        backgroundColor: m.Colors.white,
                        child: m.Icon(
                          m.Icons.camera_alt,
                          size: 18,
                          color: m.Color.fromARGB(255, 6, 213, 192),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            m.Divider(),

            // 設定 (獨立頁面，使用跳轉)
            m.ListTile(
              leading: const m.Icon(m.Icons.settings),
              title: const m.Text('設定'),
              onTap: () {
                m.Navigator.pop(context);
                m.Navigator.push(
                  context,
                  m.MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),

            m.ListTile(
              leading: const m.Icon(m.Icons.help),
              title: const m.Text('幫助與回饋'),
              onTap: () {
                m.Navigator.pop(context);
                m.Navigator.push(
                  context,
                  m.MaterialPageRoute(builder: (_) => const FeedbackPage()),
                );
              },
            ),
            m.Divider(),
            m.ListTile(
              leading: const m.Icon(m.Icons.logout, color: m.Colors.red),
              title:
                  const m.Text('登出', style: m.TextStyle(color: m.Colors.red)),
              onTap: _signOut,
            ),
          ],
        ),
      ),

      // 🔥 核心：使用 IndexedStack 來保持頁面狀態
      body: m.IndexedStack(
        index: currentIndex,
        children: _pages,
      ),
      // 已切回精簡版：僅保留「紀錄 + 設定」
    );
  }
}
