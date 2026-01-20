import 'package:flutter/material.dart';

/// 交互式頁面導覽
/// 在實際頁面上高亮顯示界面元素並進行說明
class InteractivePageTutorial extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback? onComplete;

  const InteractivePageTutorial({
    super.key,
    required this.steps,
    this.onComplete,
  });

  @override
  State<InteractivePageTutorial> createState() =>
      _InteractivePageTutorialState();
}

class _InteractivePageTutorialState extends State<InteractivePageTutorial> {
  int _currentStep = 0;

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_currentStep];

    return Stack(
      children: [
        // 背景遮蓋（半透明）
        Container(
          color: Colors.black38,
        ),

        // 高亮區域
        if (step.targetArea != null)
          Positioned(
            left: step.targetArea!.dx - 8,
            top: step.targetArea!.dy - 8,
            child: Container(
              width: step.targetSize?.width ?? 100,
              height: step.targetSize?.height ?? 100,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.blue,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
          ),

        // 說明氣泡
        Positioned(
          bottom: 100,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step.title != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title!,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                Text(
                  step.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                        height: 1.5,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_currentStep + 1}/${widget.steps.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[500],
                          ),
                    ),
                    Row(
                      children: [
                        if (_currentStep > 0)
                          TextButton(
                            onPressed: _previousStep,
                            child: const Text('上一步'),
                          ),
                        const SizedBox(width: 8),
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
              ],
            ),
          ),
        ),

        // 跳過按鈕（頂部）
        Positioned(
          top: 16,
          right: 16,
          child: GestureDetector(
            onTap: _complete,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Text(
                '跳過',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
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

  void _complete() {
    Navigator.of(context).pop();
    widget.onComplete?.call();
  }
}

/// 教學步驟
class TutorialStep {
  final String? title;
  final String description;
  final Offset? targetArea; // 要高亮的元素位置
  final Size? targetSize; // 要高亮的元素大小

  TutorialStep({
    this.title,
    required this.description,
    this.targetArea,
    this.targetSize,
  });
}

/// 幫助按鈕 - 用於在頁面上顯示
class TutorialButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const TutorialButton({
    super.key,
    required this.onPressed,
    this.tooltip = '開始教學',
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FloatingActionButton.small(
        onPressed: onPressed,
        child: const Icon(Icons.help_outline),
      ),
    );
  }
}
