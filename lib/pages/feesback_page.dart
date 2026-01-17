import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/firebase_sync_config.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitFeedback() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      // 將回饋存入 'feedbacks' 集合
      await FirebaseFirestore.instance
        .collection('feedback')
        .add({
          'uid': FirebaseAuth.instance.currentUser!.uid,
          'content': _controller.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });

      if (!mounted) return;

      // 顯示感謝訊息並離開
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('收到你的建議了，謝謝你！❤️'),
          backgroundColor: Colors.green,
        ),
      );
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '你的聲音能讓心晴變得更好 ✨',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '無論是發現 Bug、或是想要許願新功能，都歡迎告訴我們。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            
            // 輸入框
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: 10, // 讓它高一點
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: '請輸入你的想法...',
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 送出按鈕
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _submitFeedback,
                icon: _isSubmitting 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(_isSubmitting ? '傳送中...' : '送出建議'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}