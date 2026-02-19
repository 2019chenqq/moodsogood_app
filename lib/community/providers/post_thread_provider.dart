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
        authorUid: '',
        content: '我懂你…那種重到呼吸都覺得費力的感覺。',
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
      Comment(
        id: 'c2_$postId',
        postId: postId,
        authorAnonId: '雨聲',
        authorUid: '',
        content: '你不是一個人。願意說出來已經很勇敢了。',
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
      ),
    ]);
  }

  void react(ReactType type, bool wasReacted) {
    // 切換反應：已按就取消（-1），未按就按下（+1）
    switch (type) {
      case ReactType.hug:
        hug = (hug + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
      case ReactType.listen:
        listen = (listen + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
      case ReactType.hope:
        hope = (hope + (wasReacted ? -1 : 1)).clamp(0, 999);
        break;
      case ReactType.heart:
        heart = (heart + (wasReacted ? -1 : 1)).clamp(0, 999);
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