// lib/models/database/file_external_record.dart


class DbFileExternalRecord {

  /// linkOptions 位标志: 是否关联 Dandanplay 弹幕信息
  static const int linkDandanplay = 0x1;

  /// linkOptions 位标志: 是否关联 Bangumi 剧集信息
  static const int linkBangumi = 0x2;

  /// linkOptions 默认值: 全部开启
  static const int defaultLinkOptions = linkDandanplay | linkBangumi;

  const DbFileExternalRecord({
    required this.fileHash,
    this.danmakuOffsetDandanplay,
    this.danmakuOffsetUser,
    this.linkOptions = defaultLinkOptions,
  });

  final String  fileHash;
  final double? danmakuOffsetDandanplay;
  final double? danmakuOffsetUser;
  final int     linkOptions;

  bool isLinkEnabled(int flag) => linkOptions & flag != 0;

  bool get dandanplayLinkEnabled => isLinkEnabled(linkDandanplay);

  bool get bangumiLinkEnabled => isLinkEnabled(linkBangumi);

  DbFileExternalRecord enableLink(int flag) =>
      copyWith(linkOptions: linkOptions | flag);

  DbFileExternalRecord disableLink(int flag) =>
      copyWith(linkOptions: linkOptions & ~flag);

  Map<String, Object?> toMap() => {
        'file_hash': fileHash,
        'danmaku_offset_dandanplay': danmakuOffsetDandanplay,
        'danmaku_offset_user': danmakuOffsetUser,
        'linkOptions': linkOptions,
      };

  factory DbFileExternalRecord.fromMap(Map<String, Object?> map) {
    return DbFileExternalRecord(
      fileHash: map['file_hash'] as String,
      danmakuOffsetDandanplay: (map['danmaku_offset_dandanplay'] as num?)?.toDouble(),
      danmakuOffsetUser: (map['danmaku_offset_user'] as num?)?.toDouble(),
      linkOptions: (map['linkOptions'] as num?)?.toInt() ?? defaultLinkOptions,
    );
  }

  DbFileExternalRecord copyWith({
    double? danmakuOffsetDandanplay,
    double? danmakuOffsetUser,
    int? linkOptions,
  }) {
    return DbFileExternalRecord(
      fileHash: fileHash,
      danmakuOffsetDandanplay: danmakuOffsetDandanplay ?? this.danmakuOffsetDandanplay,
      danmakuOffsetUser: danmakuOffsetUser ?? this.danmakuOffsetUser,
      linkOptions: linkOptions ?? this.linkOptions,
    );
  }
}
