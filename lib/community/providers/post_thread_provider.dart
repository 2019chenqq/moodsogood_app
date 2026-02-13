import 'package:flutter/foundation.dart';
import '../models/comment.dart';
import 'room_feed_provider.dart';

class PostThreadProvider extends ChangeNotifier {
  final String postId;

  PostThreadProvider(this.postId) {
    _seed();
  }

  int hug = 12;
  int listen = 8;
  int hope = 3;
  int heart = 9;

  final List<Comment> _comments = [];
  List<Comment> get comments => List.unmodifiable(_comments);

  void _seed() {
    _comments.addAll([
      Comment(
        id: 'c1_$postId',
        postId: postId,
        authorAnonId: '月光22',
        content: '我懂你…那種重到呼吸都覺得費力的感覺。',
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
      Comment(
        id: 'c2_$postId',
        postId: postId,
        authorAnonId: '雨聲',
        content: '你不是一個人。願意說出來已經很勇敢了。',
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
      ),
    ]);
  }

  void react(ReactType type) {
    switch (type) {
      case ReactType.hug:
        hug += 1;
        break;
      case ReactType.listen:
        listen += 1;
        break;
      case ReactType.hope:
        hope += 1;
        break;
      case ReactType.heart:
        heart += 1;
        break;
    }
    notifyListeners();
  }

  void addComment(String text) {
    final t = text.trim();
    if (t.isEmpty) return;

    _comments.add(
      Comment(
        id: 'c${_comments.length + 1}_$postId',
        postId: postId,
        authorAnonId: '你',
        content: t,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }
}