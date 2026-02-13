class Comment {
  final String id;
  final String postId;
  final String authorAnonId;
  final String content;
  final DateTime createdAt;

  const Comment({
    required this.id,
    required this.postId,
    required this.authorAnonId,
    required this.content,
    required this.createdAt,
  });
}