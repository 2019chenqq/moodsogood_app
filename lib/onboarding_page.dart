import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'analytics_service.dart';

/// 初次使用導覽頁面
/// 展示應用的主要功能並引導用戶開始使用
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('onboarding_page');
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // 頁面指示器 (在頂部)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
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

              // 主內容區域
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  children: [
                    // 第1頁：歡迎
                    _buildWelcomePage(),

                    // 第2頁：每日紀錄
                    _buildDailyRecordPage(),

                    // 第3頁：日記
                    _buildDiaryPage(),

                    // 第4頁：統計分析
                    _buildStatisticsPage(),

                    // 第5頁：設定與開始
                    _buildGetStartedPage(),
                  ],
                ),
              ),

              // 底部按鈕區域
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 上一頁按鈕
                    if (_currentPage > 0)
                      OutlinedButton(
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Text('上一頁'),
                      )
                    else
                      const SizedBox(width: 80),

                    const SizedBox(width: 80),

                    // 下一頁/開始按鈕
                    ElevatedButton(
                      onPressed: () {
                        if (_currentPage < 4) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          _completeOnboarding();
                        }
                      },
                      child: Text(_currentPage == 4 ? '開始使用' : '下一頁'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // 各個頁面的構建方法
  // ============================================

  Widget _buildWelcomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          
          // 應用圖標或插圖
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.blue[100],
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(
              Icons.favorite,
              size: 60,
              color: Colors.blue,
            ),
          ),
          
          const SizedBox(height: 40),
          
          Text(
            '心域',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            '您的心理健康管家',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 32),
          
          Text(
            '隨時記錄您的心情、睡眠和日常狀態，'
            '幫助您更好地了解和管理自己的心理健康。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[700],
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 60),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Text(
              '完整的功能導覽只需 2 分鐘，'
              '跟著我們了解如何最好地使用此應用！',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.blue[800],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDailyRecordPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          
          // 標題
          Text(
            '每日狀態紀錄',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            '記錄您當前的心理和身體狀態',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // 功能示意圖
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.note_add,
              size: 80,
              color: Colors.amber,
            ),
          ),
          
          const SizedBox(height: 32),
          
          // 功能列表
          _buildFeatureItem(
            icon: Icons.mood,
            title: '情緒記錄',
            description: '選擇您現在的心情，如平靜、開心、焦慮等。'
                '幫助追蹤您的情緒模式。',
          ),
          
          const SizedBox(height: 20),
          
          _buildFeatureItem(
            icon: Icons.local_hospital,
            title: '症狀與藥物',
            description: '記錄身體症狀和服用的藥物，'
                '例如安眠藥或其他治療藥物。',
          ),
          
          const SizedBox(height: 20),
          
          _buildFeatureItem(
            icon: Icons.bedtime,
            title: '睡眠追蹤',
            description: '記錄睡眠時間、質量和夜間醒來次數，'
                '了解您的睡眠模式。',
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDiaryPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          
          // 標題
          Text(
            '日記',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            '記錄您的想法和感受',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // 功能示意圖
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.purple[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.book,
              size: 80,
              color: Colors.purple,
            ),
          ),
          
          const SizedBox(height: 32),
          
          // 功能詳情
          _buildInfoCard(
            title: '自由書寫',
            description: '用日記的形式深入記錄您的想法、感受和經歷。'
                '沒有字數限制，完全按照您的方式書寫。',
          ),
          
          const SizedBox(height: 16),
          
          _buildInfoCard(
            title: '私密安全',
            description: '所有日記內容都被安全保存，'
                '只有您可以訪問。',
          ),
          
          const SizedBox(height: 16),
          
          _buildInfoCard(
            title: '情感表達',
            description: '日記是表達複雜情感和處理壓力的好方式。'
                '持續寫日記可以幫助自我反思。',
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatisticsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          
          // 標題
          Text(
            '統計分析',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            '查看您的數據趨勢',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // 功能示意圖
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.bar_chart,
              size: 80,
              color: Colors.green,
            ),
          ),
          
          const SizedBox(height: 32),
          
          // 功能詳情
          _buildFeatureItem(
            icon: Icons.timeline,
            title: '歷史記錄',
            description: '查看過去的所有記錄，'
                '回顧您的進度和變化。',
          ),
          
          const SizedBox(height: 20),
          
          _buildFeatureItem(
            icon: Icons.show_chart,
            title: '數據可視化',
            description: '通過圖表和統計數據'
                '更清晰地了解您的模式。',
          ),
          
          const SizedBox(height: 20),
          
          _buildFeatureItem(
            icon: Icons.insights,
            title: '趨勢分析',
            description: '識別與您的心理健康和睡眠相關的模式，'
                '幫助您做出更好的決定。',
          ),
          
          const SizedBox(height: 20),
          
          _buildInfoCard(
            title: '💡 提示',
            description: '定期查看您的數據可以幫助您發現'
                '可能影響您心理健康的觸發因素。',
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildGetStartedPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          
          // 完成圖標
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(
              Icons.check_circle,
              size: 60,
              color: Colors.green,
            ),
          ),
          
          const SizedBox(height: 32),
          
          Text(
            '準備好開始了嗎？',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          Text(
            '您已經了解了 心域 的主要功能。'
            '現在可以開始記錄您的心理健康之旅。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[700],
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 40),
          
          // 建議列表
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '快速開始提示：',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
                const SizedBox(height: 12),
                _buildTipItem('每天至少記錄一次您的情緒、身體狀態和睡眠狀態'),
                const SizedBox(height: 8),
                _buildTipItem('定期查看統計數據以識別模式'),
                const SizedBox(height: 8),
                _buildTipItem('在日記中記錄詳細的想法和感受'),
                const SizedBox(height: 8),
                _buildTipItem('設定提醒以確保您不會忘記記錄'),
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          
          Text(
            '我們很高興您選擇 心域 來支持您的心理健康！',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ============================================
  // 輔助 Widget
  // ============================================

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.blue[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Colors.blue,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
