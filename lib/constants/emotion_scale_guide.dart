/// 情緒量表引導文（0 分 / 10 分錨點）
///
/// 使用原則：
/// - 0 分 = 幾乎沒有 / 完全沒有
/// - 10 分 = 非常強烈 / 幾乎整天受影響
import 'package:flutter/material.dart';

class EmotionScaleGuide {
  final String question;
  final String zero;
  final String ten;
  final bool isSensitive;

  const EmotionScaleGuide({
    required this.question,
    required this.zero,
    required this.ten,
    this.isSensitive = false,
  });
}

const Map<String, EmotionScaleGuide> emotionScaleGuides = {
  '整體情緒': EmotionScaleGuide(
    question: '今天整體過得還好嗎？',
    zero: '今天整體很不好，幾乎整天都很吃力，缺少平穩或放鬆的時刻。',
    ten: '今天整體很好，大多時間穩定、安心或自在。',
  ),

  '焦慮程度': EmotionScaleGuide(
    question: '今天有感到緊繃或不安嗎？',
    zero: '幾乎沒有緊繃或不安，身心大致放鬆。',
    ten: '非常緊繃或不安，整天明顯受影響，很難放鬆。',
  ),

  '憂鬱程度': EmotionScaleGuide(
    question: '今天心情有比較低落嗎？',
    zero: '沒有特別低落，情緒大致平穩。',
    ten: '非常低落，無力或悲傷感很強，幾乎整天都在。',
  ),

  '空虛程度': EmotionScaleGuide(
    question: '有一種空空的感覺嗎？',
    zero: '沒有空虛或麻木感，內在感覺有連結、有重量。',
    ten: '很強烈的空虛、麻木或失去連結感，幾乎整天如此。',
  ),

  '無聊程度': EmotionScaleGuide(
    question: '今天有提不起勁嗎？',
    zero: '沒有特別無聊或提不起勁，能投入事情。',
    ten: '非常無聊或提不起勁，對多數事情都難以投入，整天受影響。',
  ),

  '難過程度': EmotionScaleGuide(
    question: '今天有比較想哭或委屈嗎？',
    zero: '沒有特別難過或委屈，情緒相對穩。',
    ten: '非常難過或委屈，想哭的感覺很強，幾乎整天都被影響。',
  ),

  '開心程度': EmotionScaleGuide(
    question: '今天有感到一點點開心嗎？',
    zero: '幾乎沒有開心或愉快感，難以感受到一點點亮起來。',
    ten: '很有開心或愉快感，今天有好幾段明顯覺得心情亮起來。',
  ),

  '無望感': EmotionScaleGuide(
    question: '有覺得看不到出口嗎？',
    zero: '沒有明顯的無望感，即使不舒服也仍覺得還有路。',
    ten: '無望感很強，覺得看不到出口或未來，幾乎整天都在。',
  ),

  '孤獨感': EmotionScaleGuide(
    question: '今天有覺得自己被落下嗎？',
    zero: '沒有明顯孤獨感，仍覺得和世界或某些人有連結。',
    ten: '非常孤獨，覺得被落下或不被理解，幾乎整天被影響。',
  ),

  '動力': EmotionScaleGuide(
    question: '今天做事有力氣嗎？',
    zero: '幾乎沒有力氣或動力，連小事都很難開始。',
    ten: '很有動力與力氣，能啟動事情並持續完成。',
  ),

  '自殺意念': EmotionScaleGuide(
    question: '有出現讓你感到害怕的念頭嗎？',
    zero: '沒有出現相關念頭。',
    ten: '相關念頭非常強烈、反覆出現，讓你很難擺脫或明顯影響生活。',
    isSensitive: true,
  ),

  '食慾': EmotionScaleGuide(
    question: '今天吃東西還順利嗎？',
    zero: '很不順利，幾乎吃不下或吃了很不舒服。',
    ten: '很順利，食慾與進食狀態良好。',
  ),

  '能量': EmotionScaleGuide(
    question: '今天身體的能量還夠嗎？',
    zero: '能量幾乎不足，身體很沉，很難支撐日常。',
    ten: '能量很夠，身體狀態能支撐今天的活動。',
  ),

  '活動量': EmotionScaleGuide(
    question: '今天有稍微動一動嗎？',
    zero: '幾乎沒有活動，整天多半坐著或躺著。',
    ten: '活動量很高，今天有明顯走動或運動。',
  ),

  '疲倦程度': EmotionScaleGuide(
    question: '今天是不是很累了？',
    zero: '不太累，精神與體力尚可。',
    ten: '非常疲倦，身心都很累，休息也難以恢復。',
  ),
};
void showEmotionScaleGuideDialog(BuildContext context, String keyName) {
  final guide = emotionScaleGuides[keyName];
  if (guide == null) return;

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(guide.question),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('0 分代表：', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(guide.zero),
            const SizedBox(height: 12),
            const Text('10 分代表：', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(guide.ten),
            if (guide.isSensitive) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                '如果你此刻覺得自己不安全，請優先尋求身邊可信任的人或緊急協助。',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}