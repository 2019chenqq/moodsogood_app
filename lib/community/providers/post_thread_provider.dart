import 'package:flutter/foundation.dart';
import '../models/comment.dart';
import '../models/post.dart';
import 'room_feed_provider.dart';

class PostThreadProvider extends ChangeNotifier {
  final String postId;
  final Post post;

  PostThreadProvider(this.postId, this.post) {
    _seed();
  }

  int get hug => post.hug;
  int get listen => post.listen;
  int get hope => post.hope;
  int get heart => post.heart;

  final List<Comment> _comments = [];
  List<Comment> get comments => List.unmodifiable(_comments);
  
  void _seed() {
    // Check if this is an anxiety room post
    if (postId.contains('anxiety')) {
      _comments.addAll([
        Comment(
          id: 'c1_$postId',
          postId: postId,
          authorAnonId: '夜色',
          authorUid: '',
          content: '我也經歷過這樣的發作…真的很可怕對不對。你現在還好嗎？有沒有在安全的地方？',
          createdAt: DateTime.now().subtract(const Duration(minutes: 55)),
        ),
        Comment(
          id: 'c2_$postId',
          postId: postId,
          authorAnonId: '海霧',
          authorUid: '',
          content: '我之前醫生教我「54321」方法：找5個看得到的、4個摸得到的、3個聽得到的、2個聞得到的、1個嚐得到的。\n有時候可以幫助自己慢慢回到當下。',
          createdAt: DateTime.now().subtract(const Duration(minutes: 50)),
        ),
        Comment(
          id: 'c3_$postId',
          postId: postId,
          authorAnonId: '小石頭',
          authorUid: '',
          content: '恐慌發作的時候真的會覺得自己要死掉了…但其實不會的，它會過去。\n我會隨身帶一個小東西（彈力球、小石頭之類的），發作時候握著，提醒自己：這會過去。',
          createdAt: DateTime.now().subtract(const Duration(minutes: 45)),
        ),
        Comment(
          id: 'c4_$postId',
          postId: postId,
          authorAnonId: '雨聲',
          authorUid: '',
          content: '我懂那種手抖到連鈴都按不好的感覺…你今天能平安下車，能找到角落蹲下來好好呼吸，已經很厲害了。\n發作的時候每一個動作都需要很大力氣，你做到了。',
          createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
        ),
        Comment(
          id: 'c5_$postId',
          postId: postId,
          authorAnonId: '海霧',
          authorUid: '',
          content: '@微光31 如果頻率很高的話，也許可以考慮跟醫生聊聊，有一些藥物或方法可以幫忙。你不用一個人硬撐。',
          createdAt: DateTime.now().subtract(const Duration(minutes: 35)),
        ),
        Comment(
          id: 'c6_$postId',
          postId: postId,
          authorAnonId: '小石頭',
          authorUid: '',
          content: '對，而且有時候知道「這是恐慌發作，不是心臟病」也會讓自己比較不那麼怕。\n我現在包包裡都會放一張小紙條寫：「這是恐慌發作，它會過去，我很安全。」',
          createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
        ),
        Comment(
          id: 'c7_$postId',
          postId: postId,
          authorAnonId: '微光31',
          authorUid: '',
          content: '謝謝你們…我現在好多了，在家休息。\n看到你們的留言覺得很溫暖，原來真的不是只有我一個人。我會試試看 54321 和小紙條的方法。',
          createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
        ),
      ]);
    } else if (postId.contains('mood_down')) {
      // Mood down room comments
      _comments.addAll([
        Comment(
          id: 'c1_$postId',
          postId: postId,
          authorAnonId: '月光22',
          authorUid: '',
          content: '我懂你說的「什麼都沒發生但很重」。有時候不是事件，是累積。你願意說出來已經很勇敢了。',
          createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
        ),
        Comment(
          id: 'c2_$postId',
          postId: postId,
          authorAnonId: '雨聲',
          authorUid: '',
          content: '我以前會逼自己「快點好起來」，反而更痛苦。後來改成：今天只做一件很小的事——洗臉、喝水、換衣服，任何一件都算。',
          createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
        ),
        Comment(
          id: 'c3_$postId',
          postId: postId,
          authorAnonId: '海藍324',
          authorUid: '',
          content: '你問我怎麼撐過去的…我常常是靠「把一天切成很小段」。先撐過 10 分鐘，再 10 分鐘。\n如果可以的話，你現在有吃一點東西嗎？',
          createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
        ),
        Comment(
          id: 'c4_$postId',
          postId: postId,
          authorAnonId: '樹洞77',
          authorUid: '',
          content: '我也是那種會怕拖很久的人。後來我練習跟自己說：拖很久也沒關係，至少我還在。\n你今天有沒有一個讓你稍微不那麼痛的角落？（音樂、被子、洗澡之類的）',
          createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
        Comment(
          id: 'c5_$postId',
          postId: postId,
          authorAnonId: '微光',
          authorUid: '',
          content: '謝謝你發這篇。我剛好也在床上動不了。看到你寫「我現在真的好累」，我就突然覺得我不是只有我一個人。',
          createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
        ),
        Comment(
          id: 'c6_$postId',
          postId: postId,
          authorAnonId: 'A17',
          authorUid: '',
          content: '謝謝你們…我剛剛去喝水了，也把窗簾拉開一點點。雖然狀態還在，但好像有比較能呼吸。\n我會試試看「只做一件小事」那個方法。',
          createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
        ),
      ]);
    } else if (postId.contains('sleep')) {
      // Sleep room comments
      _comments.addAll([
        Comment(
          id: 'c1_$postId',
          postId: postId,
          authorAnonId: '雨聲',
          authorUid: '',
          content: '我也是凌晨會突然醒來那種。\n後來我試著不要跟自己說「完蛋了又沒睡好」，\n而是告訴自己：至少現在躺著休息，也算在恢復。',
          createdAt: DateTime.now().subtract(const Duration(hours: 9)),
        ),
        Comment(
          id: 'c2_$postId',
          postId: postId,
          authorAnonId: '海霧',
          authorUid: '',
          content: '我有一陣子會把夜晚分成兩段：\n第一段是「睡眠」，第二段是「靜靜躺著」。\n如果醒來，我就把它當成第二段。\n這樣焦慮會少一點。',
          createdAt: DateTime.now().subtract(const Duration(hours: 8, minutes: 50)),
        ),
        Comment(
          id: 'c3_$postId',
          postId: postId,
          authorAnonId: '小石頭',
          authorUid: '',
          content: '以前我會一直滑手機，結果更清醒。\n現在我會放一段很熟悉的聲音（Podcast 或白噪音），\n讓腦袋有東西跟著，不會亂跑。',
          createdAt: DateTime.now().subtract(const Duration(hours: 8, minutes: 40)),
        ),
        Comment(
          id: 'c4_$postId',
          postId: postId,
          authorAnonId: '夜行者92',
          authorUid: '',
          content: '謝謝你們。\n我剛剛試著不要責怪自己，\n只是閉著眼睛呼吸。\n雖然還沒睡著，但沒有那麼焦躁了。',
          createdAt: DateTime.now().subtract(const Duration(hours: 8, minutes: 30)),
        ),
        Comment(
          id: 'c5_$postId',
          postId: postId,
          authorAnonId: '微光',
          authorUid: '',
          content: '看到這篇才發現我不是唯一一個 2 點多醒來的人。\n有時候只是知道有人也在這個時段醒著，\n就比較不孤單。',
          createdAt: DateTime.now().subtract(const Duration(hours: 8, minutes: 20)),
        ),
      ]);
    } else if (postId.contains('meds')) {
      // Medication room comments
      _comments.addAll([
        Comment(
          id: 'c1_$postId',
          postId: postId,
          authorAnonId: '雨聲',
          authorUid: '',
          content: '我之前換藥的前兩週也有「霧霧的」感覺。\n後來有慢慢適應，但我有把每天的狀況記下來，回診時比較好說清楚。',
          createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 30)),
        ),
        Comment(
          id: 'c2_$postId',
          postId: postId,
          authorAnonId: '海霧',
          authorUid: '',
          content: '我會觀察幾件事：\n• 這種不舒服是不是每天都一樣\n• 有沒有越來越嚴重\n• 有沒有影響到基本生活\n然後把它們記下來帶去問醫師。',
          createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 20)),
        ),
        Comment(
          id: 'c3_$postId',
          postId: postId,
          authorAnonId: '微光',
          authorUid: '',
          content: '我也曾經懷疑自己是不是太敏感。\n後來發現——就算是「小不舒服」，也是身體在講話。\n不一定代表要停藥，但可以讓醫師知道。',
          createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 10)),
        ),
        Comment(
          id: 'c4_$postId',
          postId: postId,
          authorAnonId: '小石頭',
          authorUid: '',
          content: '我有一次副作用比較明顯，是主動提前回診。\n醫師幫我調整之後舒服很多。\n所以如果真的很困擾，提早回診也是一個選項。',
          createdAt: DateTime.now().subtract(const Duration(hours: 4)),
        ),
        Comment(
          id: 'c5_$postId',
          postId: postId,
          authorAnonId: '星河',
          authorUid: '',
          content: '謝謝你們。\n我決定先記錄幾天，再觀察看看。\n至少現在知道不是只有我一個人會這樣。',
          createdAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 50)),
        ),
      ]);
    } else if (postId.contains('heard')) {
      // Want to be heard room comments
      _comments.addAll([
        Comment(
          id: 'c1_$postId',
          postId: postId,
          authorAnonId: '微光',
          authorUid: '',
          content: '我看到你了。\n不是那種「回一下就走」的看到，\n是真的停下來看的那種。',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 35)),
        ),
        Comment(
          id: 'c2_$postId',
          postId: postId,
          authorAnonId: '夜色',
          authorUid: '',
          content: '有時候最累的不是事情，\n是一直扮演「沒事」的人。\n謝謝你把這句話說出來。',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 30)),
        ),
        Comment(
          id: 'c3_$postId',
          postId: postId,
          authorAnonId: '海霧',
          authorUid: '',
          content: '你不需要在這裡看起來正常。\n在這裡，你可以只是「很累」。',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 25)),
        ),
        Comment(
          id: 'c4_$postId',
          postId: postId,
          authorAnonId: '雨聲',
          authorUid: '',
          content: '如果你消失，我會發現。\n因為我剛剛停下來讀完你的每一行。',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 20)),
        ),
        Comment(
          id: 'c5_$postId',
          postId: postId,
          authorAnonId: '小石頭',
          authorUid: '',
          content: '你不需要解釋、不需要交代、不需要證明。\n你現在這樣，就是值得被聽見的。',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 15)),
        ),
        Comment(
          id: 'c6_$postId',
          postId: postId,
          authorAnonId: '靜靜的人',
          authorUid: '',
          content: '謝謝你們。\n看到「我看到你了」那句話的時候，\n我真的有一點點鬆下來。',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 10)),
        ),
      ]);
    }
  }

  void react(ReactType type, bool wasReacted) {
    // 切換反應：已按就取消（-1），未按就按下（+1）
    switch (type) {
      case ReactType.hug:
        post.hug = (post.hug + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
      case ReactType.listen:
        post.listen = (post.listen + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
      case ReactType.hope:
        post.hope = (post.hope + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
      case ReactType.heart:
        post.heart = (post.heart + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
    }
    notifyListeners();
  }

  void addComment(String text, String authorAnonId, {String authorUid = ''}) {
    final t = text.trim();
    if (t.isEmpty) return;

    final author = authorAnonId.trim().isEmpty ? '匿名者' : authorAnonId.trim();

    _comments.add(
      Comment(
        id: 'c${_comments.length + 1}_$postId',
        postId: postId,
        authorAnonId: author,
        authorUid: authorUid,
        content: t,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void deleteComment(String commentId) {
    final idx = _comments.indexWhere((c) => c.id == commentId);
    if (idx < 0) return;
    _comments.removeAt(idx);
    notifyListeners();
  }

  void updateComment(String commentId, String newContent) {
    final idx = _comments.indexWhere((c) => c.id == commentId);
    if (idx < 0) return;
    final trimmed = newContent.trim();
    if (trimmed.isEmpty) return;

    final old = _comments[idx];
    _comments[idx] = Comment(
      id: old.id,
      postId: old.postId,
      authorAnonId: old.authorAnonId,
      authorUid: old.authorUid,
      content: trimmed,
      createdAt: old.createdAt,
    );
    notifyListeners();
  }
}