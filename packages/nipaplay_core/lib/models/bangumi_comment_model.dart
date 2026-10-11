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

class DandanplayComment {
  final int id;
  final int userId;
  final String externalUserId;
  final String userName;
  final String imageUrl;
  final String source;
  final String text;
  final int rating;
  final DateTime updatedTime;

  DandanplayComment({
    required this.id,
    required this.userId,
    required this.externalUserId,
    required this.userName,
    required this.imageUrl,
    required this.source,
    required this.text,
    required this.rating,
    required this.updatedTime,
  });

  factory DandanplayComment.fromJson(Map<String, dynamic> json) {
    DateTime parseUpdatedTime(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DandanplayComment(
      id: json['id'] as int? ?? 0,
      userId: json['userId'] as int? ?? 0,
      externalUserId: json['externalUserId'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      source: json['source'] as String? ?? '',
      text: json['text'] as String? ?? '',
      rating: json['rating'] as int? ?? 0,
      updatedTime: parseUpdatedTime(json['updatedTime']),
    );
  }

  BangumiComment toBangumiComment() {
    return BangumiComment(
      userId: userId,
      username: userName,
      nickname: userName,
      avatarUrl: 'assets/avatar.png',
      rate: rating,
      comment: text,
      updatedAt: updatedTime.millisecondsSinceEpoch ~/ 1000,
    );
  }
}
