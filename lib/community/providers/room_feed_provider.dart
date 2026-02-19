import 'package:flutter/foundation.dart';
import '../models/post.dart';

enum ReactType { hug, listen, hope, heart }

class RoomFeedProvider extends ChangeNotifier {
  final String roomId;

  RoomFeedProvider(this.roomId, {Post? initialPost}) {
    _seed();
    if (initialPost != null) {
      _posts.insert(0, initialPost);
    }
  }

  final List<Post> _posts = [];
  List<Post> get posts => List.unmodifiable(_posts);

  void _seed() {
    if (roomId == 'mood_down') {
      _posts.addAll([
        Post(
          id: 'p1_$roomId',
          roomId: roomId,
          authorAnonId: 'A17',
          content: '今天好像什麼都沒發生，但心裡就是很重。\n明明知道自己應該去做點什麼，卻連起床都覺得費力。\n我有點怕——怕這種狀態又要拖很久，也怕我會讓身邊的人失望。\n\n我只是想在這裡說一句：我現在真的好累。\n如果你也在類似的狀態，想問你——你怎麼撐過去的？',
          createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
          hug: 18,
          listen: 11,
          hope: 6,
          heart: 9,
          replyCount: 6,
        ),
      ]);
    } else if (roomId == 'anxiety') {
      _posts.addAll([
        Post(
          id: 'p1_$roomId',
          roomId: roomId,
          authorAnonId: '微光31',
          content: '剛剛在公車上又發作了……\n心跳突然很快，胸口好緊，呼吸不過來，覺得自己快要死掉了。\n我想按鈴下車，但手抖到連鈴都按不好。\n下車之後找了路邊一個角落蹲下來，深呼吸了好久才慢慢穩下來。\n\n明明什麼都沒發生，就突然開始恐慌……\n我真的好累，不知道該怎麼辦才好。',
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
          hug: 24,
          listen: 18,
          hope: 9,
          heart: 12,
          replyCount: 7,
        ),
      ]);
    } else if (roomId == 'sleep') {
      _posts.addAll([
        Post(
          id: 'p1_$roomId',
          roomId: roomId,
          authorAnonId: '夜行者92',
          content: '又醒了。\n\n明明很累，眼睛也酸，可是腦袋就是停不下來。\n一直在想白天說錯的話、明天要做的事，還有那些根本控制不了的事情。\n\n最討厭的是——白天又會後悔自己沒睡好。\n變成一個循環。\n\n有沒有人也是這樣？\n你們怎麼跟「醒著的夜晚」相處？',
          createdAt: DateTime.now().subtract(const Duration(hours: 9, minutes: 13)),
          hug: 21,
          listen: 14,
          hope: 7,
          heart: 10,
          replyCount: 6,
        ),
      ]);
    } else if (roomId == 'meds') {
      _posts.addAll([
        Post(
          id: 'p1_$roomId',
          roomId: roomId,
          authorAnonId: '星河',
          content: '這週開始換新的藥。\n前幾天都還好，這兩天開始覺得有點想睡、腦袋霧霧的。\n\n我知道剛開始可能需要適應期，但還是會忍不住想：\n這樣正常嗎？\n還是我不適合？\n\n醫師有說如果有不舒服可以回診調整，\n只是現在有點分不清——\n是我太敏感，還是真的副作用。\n\n想問問有類似經驗的人，你們都怎麼觀察自己的身體變化？',
          createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 48)),
          hug: 16,
          listen: 13,
          hope: 5,
          heart: 8,
          replyCount: 5,
        ),
      ]);
    } else if (roomId == 'heard') {
      _posts.addAll([
        Post(
          id: 'p1_$roomId',
          roomId: roomId,
          authorAnonId: '靜靜的人',
          content: '今天其實沒有發生什麼大事。\n但我好像一直在撑。\n\n在公司要笑、回家要正常、跟朋友聊天要看起來沒事。\n\n有時候會突然覺得——\n如果我安靜地消失幾天，\n會不會也沒有人真的發現。\n\n我不是要解決什麼。\n只是想在這裡說一句：\n我其實很累。',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 42)),
          hug: 32,
          listen: 21,
          hope: 11,
          heart: 18,
          replyCount: 6,
        ),
      ]);
    }
  }

  void react(String postId, ReactType type, bool wasReacted) {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;

    final p = _posts[idx];
    switch (type) {
      case ReactType.hug:
        p.hug = (p.hug + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
      case ReactType.listen:
        p.listen = (p.listen + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
      case ReactType.hope:
        p.hope = (p.hope + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
      case ReactType.heart:
        p.heart = (p.heart + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
    }
    notifyListeners();
  }

  void addPost(Post post) {
    _posts.insert(0, post);
    notifyListeners();
  }

  void deletePost(String postId) {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    _posts.removeAt(idx);
    notifyListeners();
  }
}