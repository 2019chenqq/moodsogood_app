import 'package:flutter/material.dart';

/// 功能導覽覆蓋層
/// 用於在功能頁面上顯示逐步導覽
class FeatureOverlay extends StatefulWidget {
  final List<OverlayStep> steps;
  final VoidCallback? onComplete;
  final bool showSkip;

  const FeatureOverlay({
    super.key,
    required this.steps,
    this.onComplete,
    this.showSkip = true,
  });

  @override
  State<FeatureOverlay> createState() => _FeatureOverlayState();
}

class _FeatureOverlayState extends State<FeatureOverlay> {
  int _currentStep = 0;

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_currentStep];
    
    return Stack(
      children: [
        // 背景遮蓋
        GestureDetector(
          onTap: _nextStep,
          child: Container(
            color: Colors.black54,
          ),
        ),
        
        // 導覽內容
        Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 標題
                if (step.title != null)
                  Text(
                    step.title!,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                
                if (step.title != null) const SizedBox(height: 16),
                
                // 圖標或圖片
                if (step.iconData != null)
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: (step.iconColor ?? Colors.blue).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        step.iconData,
                        size: 50,
                        color: step.iconColor ?? Colors.blue,
                      ),
                    ),
                  ),
                
                if (step.iconData != null) const SizedBox(height: 16),
                
                // 描述
                Text(
                  step.description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[700],
                    height: 1.6,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 進度指示
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.steps.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentStep == index ? 12 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentStep == index
                            ? Colors.blue
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 按鈕
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.showSkip)
                      TextButton(
                        onPressed: _skip,
                        child: const Text('跳過'),
                      ),
                    const Spacer(),
                    if (_currentStep > 0)
                      TextButton(
                        onPressed: _previousStep,
                        child: const Text('上一步'),
                      ),
                    ElevatedButton(
                      onPressed: _nextStep,
                      child: Text(
                        _currentStep == widget.steps.length - 1
                            ? '完成'
                            : '下一步',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _nextStep() {
    if (_currentStep < widget.steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _complete();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _skip() {
    _complete();
  }

  void _complete() {
    Navigator.of(context).pop();
    widget.onComplete?.call();
  }
}

/// 導覽步驟
class OverlayStep {
  final String? title;
  final String description;
  final IconData? iconData;
  final Color? iconColor;

  OverlayStep({
    this.title,
    required this.description,
    this.iconData,
    this.iconColor,
  });
}
