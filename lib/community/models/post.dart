class Post {
  final String id;
  final String roomId;
  final String authorAnonId;
  final String content;
  final DateTime createdAt;
  final bool allowReplies;

  int hug;
  int listen;
  int hope;
  int heart;

  int replyCount;

  Post({
    required this.id,
    required this.roomId,
    required this.authorAnonId,
    required this.content,
    required this.createdAt,
    this.allowReplies = true,
    this.hug = 0,
    this.listen = 0,
    this.hope = 0,
    this.heart = 0,
    this.replyCount = 0,
  });
}