import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 番剧删除墓碑。
///
/// 记录用户显式删除整部番剧观看记录的动作：
/// 1. 作为特殊条目注入 WebDAV 增量同步状态（键前缀 `deletedAnime:`），
///    随 diff 传播到其他设备，各端应用墓碑时删除本地对应番剧的全部记录；
/// 2. 本地写入路径（同步恢复、备份恢复、扫描回写）据此拦截已删除
///    番剧的脏条目，防止云端残留（含 animeName 为空的「未知动画」）
///    倒灌回本地；
/// 3. 墓碑保留 90 天后过期清理，随同步自然退出；用户重新观看该番
///    （animeName 非空的正常写入）会立即解除墓碑（复活）。
class AnimeDeletionTombstones {
  const AnimeDeletionTombstones._();

  static const String _prefsKey = 'anime_deletion_tombstones';
  static const Duration retention = Duration(days: 90);

  /// 同步状态中的墓碑条目 key 前缀与删除标记。
  static const String keyPrefix = 'deletedAnime:';
  static const String tombstoneMarker = '_syncDeleted';

  // ---------- 本地存储 ----------

  static Future<Map<String, int>> _readRaw() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_prefsKey);
      if (encoded == null || encoded.isEmpty) return const {};
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const {};
      final result = <String, int>{};
      for (final entry in decoded.entries) {
        final deletedAt = (entry.value as num?)?.toInt();
        if (deletedAt == null) continue;
        result[entry.key.toString()] = deletedAt;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  static Future<void> _writeRaw(Map<String, int> tombstones) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(tombstones));
    } catch (_) {}
  }

  static bool _isExpired(int deletedAtMs) {
    final cutoff = DateTime.now().toUtc().millisecondsSinceEpoch -
        retention.inMilliseconds;
    return deletedAtMs < cutoff;
  }

  /// 返回仍在保留期内的墓碑（键为 animeId 字符串，值为删除时间 ISO），
  /// 顺带清理过期条目。
  static Future<Map<String, String>> activeTombstones() async {
    final raw = Map<String, int>.from(await _readRaw());
    final beforeCount = raw.length;
    raw.removeWhere((_, deletedAt) => _isExpired(deletedAt));
    if (raw.length != beforeCount) {
      await _writeRaw(raw);
    }
    return raw.map(
      (animeId, deletedAt) => MapEntry(
        animeId,
        DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true)
            .toIso8601String(),
      ),
    );
  }

  /// 返回仍处于删除状态的 animeId 集合（仅内存判断，不做清理写入）。
  static Future<Set<int>> deletedAnimeIds() async {
    final raw = await _readRaw();
    final result = <int>{};
    for (final entry in raw.entries) {
      if (_isExpired(entry.value)) continue;
      final animeId = int.tryParse(entry.key);
      if (animeId != null) result.add(animeId);
    }
    return result;
  }

  static Future<bool> isDeleted(int? animeId) async {
    if (animeId == null) return false;
    final raw = await _readRaw();
    final deletedAt = raw[animeId.toString()];
    return deletedAt != null && !_isExpired(deletedAt);
  }

  static Future<void> record(int animeId, {DateTime? deletedAt}) async {
    final raw = Map<String, int>.from(await _readRaw());
    raw[animeId.toString()] =
        (deletedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _writeRaw(raw);
  }

  /// 用户重新观看等主动写入时解除墓碑（复活）。
  static Future<void> clear(int animeId) async {
    final raw = Map<String, int>.from(await _readRaw());
    if (raw.remove(animeId.toString()) != null) {
      await _writeRaw(raw);
    }
  }

  // ---------- 同步状态编码 ----------

  static String keyFor(String animeId) => '$keyPrefix$animeId';

  static bool isDeletionKey(String key) => key.startsWith(keyPrefix);

  static int? animeIdFromKey(String key) {
    if (!isDeletionKey(key)) return null;
    return int.tryParse(key.substring(keyPrefix.length));
  }

  static bool isTombstone(dynamic value) =>
      value is Map && value[tombstoneMarker] == true;

  static Map<String, dynamic> tombstoneValue({
    required String animeId,
    required String deletedAt,
  }) {
    return {
      'animeId': animeId,
      tombstoneMarker: true,
      'deletedAt': deletedAt,
    };
  }
}
