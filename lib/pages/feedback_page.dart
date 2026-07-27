import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../analytics_service.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('feedback_page');
  }

  Future<void> _submitFeedback() async {
    setState(() => _isSubmitting = true);

    try {
      final uri = Uri(
        scheme: 'mailto',
        path: 'innera0120@gmail.com',
        queryParameters: {
          'subject': 'Innera 回饋與建議',
        },
      );

      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('無法開啟 Email App，請寄信至 innera0120@gmail.com'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('無法開啟 Email App，請寄信至 innera0120@gmail.com'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('回饋與建議')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '你的聲音能讓心域變得更好',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '點擊下方按鈕後，請直接在 Email App 中輸入問題、功能建議或使用感受。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '收件人：innera0120@gmail.com',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
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
                    : const Icon(Icons.email_outlined),
                label: Text(_isSubmitting ? '開啟中...' : '撰寫 Email'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '完成內容後，請在 Email App 中按下寄送。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
