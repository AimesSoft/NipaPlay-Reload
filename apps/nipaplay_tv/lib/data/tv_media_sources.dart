import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nipaplay_core/utils/settings_storage.dart';

/// 媒体连接类型（与媒体库「添加来源」一一对应）。
enum TvSourceKind {
  localFile('本地文件', Icons.insert_drive_file_outlined),
  localFolder('本地文件夹', Icons.folder_outlined),
  webdav('WebDAV', Icons.cloud_outlined),
  emby('Emby', Icons.dns_outlined),
  jellyfin('Jellyfin', Icons.dns_outlined),
  smb('SMB 共享', Icons.dns_outlined),
  dandanplayRemote('弹弹远程服务', Icons.cloud_outlined),
  url('网络串流 URL', Icons.travel_explore);

  const TvSourceKind(this.label, this.icon);
  final String label;
  final IconData icon;

  static TvSourceKind parse(String? name) => TvSourceKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => TvSourceKind.localFile,
      );
}

/// 一条媒体连接（持久化到 core [SettingsStorage]）。
///
/// **支持多组同类型连接**（例如多个弹弹远程端口）：列表按添加顺序保存，
/// 每条独立持有自己的地址与凭据，互不覆盖。
class TvMediaSource {
  const TvMediaSource({
    required this.name,
    required this.location,
    required this.kind,
    this.username,
    this.password,
    this.token,
    this.rating,
    this.isNew = false,
    this.pinned = false,
  });

  final String name;
  final String location;
  final TvSourceKind kind;
  final String? username;
  final String? password;
  final String? token;
  final double? rating;
  final bool isNew;

  /// 是否钉选到侧边栏（用户手动选择）。
  final bool pinned;

  IconData get icon => kind.icon;

  String encode() => jsonEncode({
        'n': name,
        'l': location,
        'k': kind.name,
        if (username != null && username!.isNotEmpty) 'un': username,
        if (password != null && password!.isNotEmpty) 'pw': password,
        if (token != null && token!.isNotEmpty) 'tk': token,
        if (rating != null) 'r': rating,
        if (isNew) 'new': true,
        if (pinned) 'pin': true,
      });

  TvMediaSource copyWith({bool? pinned}) => TvMediaSource(
        name: name,
        location: location,
        kind: kind,
        username: username,
        password: password,
        token: token,
        rating: rating,
        isNew: isNew,
        pinned: pinned ?? this.pinned,
      );

  static TvMediaSource? tryDecode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return TvMediaSource(
        name: (map['n'] as String?) ?? '未命名',
        location: (map['l'] as String?) ?? '',
        kind: TvSourceKind.parse(map['k'] as String?),
        username: map['un'] as String?,
        password: map['pw'] as String?,
        token: map['tk'] as String?,
        rating: (map['r'] as num?)?.toDouble(),
        isNew: map['new'] == true,
        pinned: map['pin'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 媒体连接的持久化存储（键 `tv.media_sources`，JSON 行列表）。
class TvMediaSourceStore {
  TvMediaSourceStore._();
  static const _key = 'tv.media_sources';

  static Future<List<TvMediaSource>> load() async {
    final raw = await SettingsStorage.loadStringList(_key);
    final list = <TvMediaSource>[];
    for (final line in raw) {
      final s = TvMediaSource.tryDecode(line);
      if (s != null) list.add(s);
    }
    return list;
  }

  static Future<void> save(List<TvMediaSource> sources) async {
    await SettingsStorage.saveStringList(
      _key,
      sources.map((e) => e.encode()).toList(),
    );
  }
}
