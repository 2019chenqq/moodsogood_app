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
    _posts.addAll([
      Post(
        id: 'p1_$roomId',
        roomId: roomId,
        authorAnonId: 'A17',
        content: '今天真的撐不住…明明什麼都沒發生，但就是好重。',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
        hug: 12,
        listen: 8,
        hope: 3,
        heart: 9,
        replyCount: 4,
      ),
      Post(
        id: 'p2_$roomId',
        roomId: roomId,
        authorAnonId: '海藍324',
        content: '有沒有人懂那種「空掉」的感覺？像是整個人被掏空。',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        hug: 20,
        listen: 5,
        hope: 2,
        heart: 7,
        replyCount: 2,
      ),
      Post(
        id: 'p3_$roomId',
        roomId: roomId,
        authorAnonId: '樹洞77',
        content: '失眠第 5 天了，白天很累但晚上就是睡不著。',
        createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
        hug: 9,
        listen: 6,
        hope: 1,
        heart: 4,
        replyCount: 1,
      ),
    ]);
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