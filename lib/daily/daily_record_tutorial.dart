import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 每日紀錄功能導覽
class DailyRecordTutorialPage extends StatefulWidget {
  const DailyRecordTutorialPage({super.key});

  @override
  State<DailyRecordTutorialPage> createState() =>
      _DailyRecordTutorialPageState();
}

class _DailyRecordTutorialPageState extends State<DailyRecordTutorialPage> {
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
    await prefs.setBool('seen_daily_record_tutorial', true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日紀錄教學'),
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
                5,
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
                _buildPage5(),
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
                    if (_currentPage < 4) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      _completeTutorial();
                    }
                  },
                  child: Text(_currentPage == 4 ? '完成' : '下一步'),
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
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.note_add,
                size: 60,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '開始您的每日紀錄',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '每日紀錄是您追蹤心理和身體狀態的主要工具。'
            '您可以每天記錄一次或多次，根據您的需要靈活使用。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[700],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          _buildInfoBox(
            title: '💡 提示',
            content: '定期記錄可以幫助您識別影響心理健康的模式。',
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
                color: Colors.amber[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.mood,
                size: 60,
                color: Colors.amber,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '記錄您的情緒',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '選擇您當前的心情。應用程式提供了多種情緒選項：',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          _buildFeatureList([
            '整體狀態：平靜、開心、有力量、疲憊、沒動力',
            '壓力情緒：焦慮、緊張、壓力大、煩躁、生氣',
            '低落警訊：難過、憂鬱、無助、崩潰感、自殺意念',
          ]),
          const SizedBox(height: 24),
          _buildInfoBox(
            title: '❤️ 重要',
            content: '如果您有自殺意念，請立即尋求專業幫助。',
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
                color: Colors.purple[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.local_hospital,
                size: 60,
                color: Colors.purple,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '記錄症狀與藥物',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '追蹤您的身體症狀和正在使用的藥物。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          _buildFeatureList([
            '症狀：輸入任何身體症狀或不適',
            '安眠藥：記錄安眠藥的名稱和劑量',
            '其他藥物：記錄其他治療藥物',
            '生理期：標記生理期狀態（如適用）',
          ]),
          const SizedBox(height: 24),
          _buildInfoBox(
            title: '📝 建議',
            content: '詳細記錄症狀有助於您和醫療專業人員更好地協作。',
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
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.bedtime,
                size: 60,
                color: Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '追蹤睡眠',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '記錄您的睡眠模式，這對心理健康至關重要。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          _buildFeatureList([
            '睡眠時間：記錄何時入睡',
            '醒來時間：記錄最終醒來的時間',
            '夜間醒來：記錄夜間醒來次數和原因',
            '睡眠品質：評估整體睡眠品質',
            '小睡時間：記錄白天的小睡',
          ]),
          const SizedBox(height: 24),
          _buildInfoBox(
            title: '🛏️ 提示',
            content: '睡眠不足會影響心理健康，請確保每晚充足睡眠。',
          ),
        ],
      ),
    );
  }

  Widget _buildPage5() {
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
                Icons.check_circle,
                size: 60,
                color: Colors.teal,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '完成您的紀錄',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '您已經了解了如何進行每日紀錄。現在可以開始使用！',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          Container(
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
                  '快速開始清單：',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildCheckItem('記錄今天的心情'),
                _buildCheckItem('記錄任何症狀或不適'),
                _buildCheckItem('記錄睡眠信息'),
                _buildCheckItem('添加備註（可選）'),
                _buildCheckItem('查看統計數據以追蹤進度'),
              ],
            ),
          ),
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

  Widget _buildInfoBox({
    required String title,
    required String content,
  }) {
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

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          const Text(
            '✓ ',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.blue[900],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
