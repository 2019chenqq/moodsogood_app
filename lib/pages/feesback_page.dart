import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  final _contactController = TextEditingController();
  bool _isSubmitting = false;
  bool _allowContact = false;
  String _selectedCategory = '功能建議';

  static const List<String> _categories = <String>[
    '功能建議',
    '問題回報',
    '使用體驗',
    '其他',
  ];

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      _contactController.text = user!.email!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    final content = _controller.text.trim();
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先登入再送出回饋')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final platform = kIsWeb
          ? 'web'
          : defaultTargetPlatform.name;

      await FirebaseFirestore.instance
        .collection('feedback')
        .add({
          'uid': user.uid,
          'category': _selectedCategory,
          'content': content,
          'allowContact': _allowContact,
          'contact': _allowContact ? _contactController.text.trim() : null,
          'appVersion': packageInfo.version,
          'buildNumber': packageInfo.buildNumber,
          'platform': platform,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'new',
        });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('收到你的建議了，謝謝你！'),
          backgroundColor: Colors.green,
        ),
      );
      _controller.clear();
      Navigator.pop(context);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('發送失敗：$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('回饋與建議')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '你的聲音能讓心域變得更好',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '你可以回報問題、許願功能，或分享使用感受。',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.map((category) {
                  return ChoiceChip(
                    label: Text(category),
                    selected: _selectedCategory == category,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _selectedCategory = category);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                minLines: 7,
                maxLines: 10,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: '請描述你遇到的情況，越具體越能幫助我們改善。',
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return '請先輸入回饋內容';
                  if (text.length < 8) return '內容至少 8 個字，方便我們判斷問題';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('願意讓我們聯絡你'),
                subtitle: const Text('若需要釐清細節，我們可透過此聯絡方式回覆'),
                value: _allowContact,
                onChanged: (value) => setState(() => _allowContact = value),
              ),
              if (_allowContact) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _contactController,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: '聯絡方式（Email 或其他）',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (!_allowContact) return null;
                    if ((value?.trim().isEmpty ?? true)) return '請填寫聯絡方式';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submitFeedback,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSubmitting ? '傳送中...' : '送出建議'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}