import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 日記功能導覽
class DiaryTutorialPage extends StatefulWidget {
  const DiaryTutorialPage({super.key});

  @override
  State<DiaryTutorialPage> createState() => _DiaryTutorialPageState();
}

class _DiaryTutorialPageState extends State<DiaryTutorialPage> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_diary_tutorial', true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日記教學'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 進度指示器
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                4,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 12 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Colors.blue
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          
          // PageView 內容
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
              },
              children: [
                _buildPage1(),
                _buildPage2(),
                _buildPage3(),
                _buildPage4(),
              ],
            ),
          ),
          
          // 底部按鈕
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentPage > 0)
                  TextButton(
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: const Text('上一步'),
                  )
                else
                  const SizedBox(width: 80),
                TextButton(
                  onPressed: _completeTutorial,
                  child: const Text('跳過'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_currentPage < 3) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      _completeTutorial();
                    }
                  },
                  child: Text(_currentPage == 3 ? '完成' : '下一步'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.purple[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.book,
                size: 60,
                color: Colors.purple,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '歡迎使用日記本',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '日記是深入表達您的想法和感受的地方。'
            '與每日紀錄的簡潔記錄不同，日記允許您自由書寫。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[700],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          _buildBenefitBox(
            '📖 日記的好處',
            [
              '深入反思您的情感和經歷',
              '記錄詳細的事件和背景',
              '自我表達和情感釋放',
              '建立自我意識',
              '追蹤個人成長',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPage2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.edit,
                size: 60,
                color: Colors.orange,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '開始寫日記',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '點擊「新增日記」按鈕，即可開始寫日記。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          _buildFeatureList([
            '選擇日期：選擇您想為其寫日記的日期',
            '添加標題（可選）：為日記添加一個簡短的標題',
            '自由寫作：沒有字數限制，完全按照您的方式寫',
            '保存：書寫時即自動儲存，無需擔心丟失內容',
          ]),
          const SizedBox(height: 24),
          _buildInfoBox(
            '💭 提示',
            '沒有對或錯的方式來寫日記。'
            '重要的是真誠地表達您的想法。',
          ),
        ],
      ),
    );
  }

  Widget _buildPage3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.pink[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.lock,
                size: 60,
                color: Colors.pink,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '隱私與安全',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '您的日記內容完全安全和隱私。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          _buildFeatureList([
            '加密保存：所有日記都被加密保存',
            '只有您可以看到：沒有人能訪問您的私人日記',
            '儲存：您可以選擇本地存儲或成為會員雲端同步',
                    ]),
          const SizedBox(height: 24),
          _buildInfoBox(
            '🔒 重要',
            '如果您啟用了 App 密碼鎖定，'
            '日記將受到額外的密碼保護。',
          ),
        ],
      ),
    );
  }

  Widget _buildPage4() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.teal[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.favorite,
                size: 60,
                color: Colors.teal,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '充分利用日記',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '以下是充分利用日記功能的一些建議：',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSuggestion('定期寫日記，最好每天一次'),
                _buildSuggestion('寫下您的感受、想法和經歷'),
                _buildSuggestion('不要擔心語法或拼寫，專注於表達'),
                _buildSuggestion('定期閱讀過去的日記以反思成長'),
                _buildSuggestion('在困難時刻使用日記作為發洩工具'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitBox(String title, List<String> benefits) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.purple[900],
            ),
          ),
          const SizedBox(height: 12),
          ...benefits.map((benefit) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✓ ',
                    style: TextStyle(
                      color: Colors.purple,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      benefit,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.purple[800],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildFeatureList(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '• ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: Text(
                  item,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoBox(String title, String content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.blue[900],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.blue[800],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestion(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '💡 ',
            style: TextStyle(fontSize: 14),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.amber[900],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
