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
  
  // 追蹤當前用戶對這個貼文的反應
  final Set<String> userReactions; // {'hug', 'listen', 'hope', 'heart'}

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
    Set<String>? userReactions,
  }) : userReactions = userReactions ?? {};
  
  // 檢查用戶是否已按下某個反應
  bool hasReacted(String reactionType) => userReactions.contains(reactionType);
  
  // 切換反應狀態
  void toggleReaction(String reactionType) {
    if (userReactions.contains(reactionType)) {
      userReactions.remove(reactionType);
    } else {
      userReactions.add(reactionType);
    }
  }
}