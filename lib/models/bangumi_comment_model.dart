class BangumiComment {
  final int userId;
  final String username;
  final String nickname;
  final String avatarUrl;
  final int rate;
  final String comment;
  final int updatedAt;

  BangumiComment({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.avatarUrl,
    required this.rate,
    required this.comment,
    required this.updatedAt,
  });

  factory BangumiComment.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final avatar = user['avatar'] as Map<String, dynamic>? ?? {};
    return BangumiComment(
      userId: user['id'] as int? ?? 0,
      username: user['username'] as String? ?? '',
      nickname: user['nickname'] as String? ?? '',
      avatarUrl: avatar['medium'] as String? ?? avatar['large'] as String? ?? '',
      rate: json['rate'] as int? ?? 0,
      comment: json['comment'] as String? ?? '',
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }
}
