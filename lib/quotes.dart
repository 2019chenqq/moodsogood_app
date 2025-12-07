import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class QuotesTitle extends StatelessWidget {
  const QuotesTitle({super.key});
  static const _quotes = <String> [
  "你累了嗎？那就先喘口氣吧🌿",
  "一件事做得糟，不代表你是糟糕的人，別輕易用事件定義自己了",
  "有時候逃避一下沒關係，人生不需要一直前進，汽油會燃盡，總需要熄火加油的⛽",
  "連天空都會哭泣，我們也可以",
  "休息不是退步，而是加油的時候⛽",
  "你做得已經很好了，真的🫶",
  "慢一點也沒關係，每首歌都有不同的節奏，人也是",
  "你不需要被任何人趕著走",
  "今天也有努力活著，辛苦了❤️‍🩹",
  "你的價值，不取決於你今天完成了多少事",
  "有時候不穩定，是因為你太努力在撐",
  "就算只前進一小步，也是一種前進🐢",
  "你可以不堅強，可以暫時軟下來💤",
  "別忘了，你值得被善待，包括被自己善待",
  "別怕被誤會，重要的是你知道自己在努力💛",
  "難過時先讓自己坐下，呼吸一下就好",
  "有些事現在不懂沒關係，總有一天會懂",
  "你沒有落後，只是走在自己的節奏裡",
  "日子不必亮閃閃，有呼吸就已經很好",
  "願今天的你，能被一點點溫柔包圍🤍",
  "生活不是只能前進，也允許後退"
  "天氣有陰有晴，也允許情緒可以陰晴變化"
];

String _pickQuoteForToday() {
  final now = DateTime.now();
  final ymd = now.year * 10000 + now.month * 100 + now.day;

  // 若有登入，把 UID 一起納入，讓每位使用者的「今天」各自穩定
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final uidHash = uid.hashCode;

  final seed = ymd + uidHash;
  final index = seed.abs() % _quotes.length;
  return _quotes[index];
}

@override
Widget build(BuildContext context) {
  final quote = _pickQuoteForToday();

  return Text(
    quote,
    textAlign: TextAlign.start,
    maxLines: 4,                    // ✅ 最多顯示兩行
    softWrap: true,                 // ✅ 自動換行
    overflow: TextOverflow.visible, // ✅ 不會出現「...」
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontStyle: FontStyle.normal,  // ✅ 取消斜體
      fontWeight: FontWeight.w600,
    ),
  );
}
}