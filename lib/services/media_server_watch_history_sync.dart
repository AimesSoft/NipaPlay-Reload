import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A server/profile and user identify a history owner; addresses and tokens only
/// identify the in-flight session and may change without changing that owner.
class MediaServerHistoryConnection {
  const MediaServerHistoryConnection({
    required this.owner,
    required this.userId,
    required this.session,
    this.profileId,
    this.serverUrl,
  });

  final String owner;
  final String userId;
  final Object session;
  final String? profileId;
  final String? serverUrl;
}

WatchHistoryItem? mergeMediaServerWatchHistory(
  WatchHistoryItem local,
  Map<String, dynamic> userData, {
  int? durationMs,
}) {
  final watchedAt =
      DateTime.tryParse(userData['LastPlayedDate']?.toString() ?? '');
  // Jellyfin's PlayedItems endpoint clears the position without advancing
  // LastPlayedDate. Its explicit completed state is authoritative even when
  // local exit saved a later timestamp; active playback and SQL CAS are guarded
  // by the caller. Nonzero rewatch positions still use timestamp precedence.
  final ticksValue = userData['PlaybackPositionTicks'];
  final ticks = (ticksValue as num?)?.toInt() ?? 0;
  final completed =
      userData['Played'] == true && ticksValue is num && ticks == 0;
  if (watchedAt == null) return null;
  final neverWatched = local.lastPosition == 0 && local.watchProgress == 0;
  if (!completed && !neverWatched && watchedAt.isBefore(local.lastWatchTime)) {
    return null;
  }

  final duration =
      durationMs != null && durationMs > 0 ? durationMs : local.duration;
  final position = (ticks ~/ 10000).clamp(0, duration > 0 ? duration : 1 << 62);
  final played = userData['Played'] == true;
  final percentage = (userData['PlayedPercentage'] as num?)?.toDouble();
  // Played means this item was watched before; it may remain true during a
  // rewatch. A nonzero mid-episode position is the current resume point.
  final progress = played && position == 0
      ? 1.0
      : duration > 0
          ? (position / duration).clamp(0.0, 1.0)
          : ((percentage ?? 0) / 100).clamp(0.0, 1.0);
  // Jellyfin resets PositionTicks on completion. Keep that zero so explicitly
  // replaying a completed episode starts at the beginning, with its played mark.
  final result = local.copyWith(
    lastPosition: position,
    duration: duration,
    watchProgress: progress,
    lastWatchTime: completed && watchedAt.isBefore(local.lastWatchTime)
        ? local.lastWatchTime
        : watchedAt,
  );
  return sameWatchHistoryProgress(local, result) ? null : result;
}

bool sameWatchHistoryProgress(WatchHistoryItem a, WatchHistoryItem b) =>
    a.filePath == b.filePath &&
    a.lastWatchTime == b.lastWatchTime &&
    a.lastPosition == b.lastPosition &&
    a.duration == b.duration &&
    a.watchProgress == b.watchProgress;

/// Refresh only known, explicitly owned history entries, with one bounded batch.
/// Legacy paths retain their existing default-server meaning only when exactly
/// one saved account matches the live connection. Persist that migration owner
/// so changing the default later cannot claim the remaining legacy histories.
class MediaServerWatchHistorySync {
  MediaServerWatchHistorySync({
    required this.source,
    required this.connection,
    required this.request,
  });

  final String source;
  final MediaServerHistoryConnection? Function() connection;
  final Future<http.Response> Function(String endpoint) request;
  Future<void> _binding = Future.value();
  int _nextOffset = 0;
  static const batchSize = 100;
  String get _key => '${source}_watch_history_owners_v1';

  Map<String, String> _owners(SharedPreferences prefs) {
    try {
      final value = jsonDecode(prefs.getString(_key) ?? '{}');
      return Map<String, String>.from(value as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> bind(String filePath) {
    final captured = connection();
    if (captured == null || !filePath.startsWith('$source://')) {
      return Future.value();
    }
    final next = _binding.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final owners = _owners(prefs)..remove(filePath);
      owners[filePath] = captured.owner;
      // An owner is part of identity, not a cache entry: evicting it could
      // let a different default account claim this path as legacy history.
      // Explicit history deletion removes the corresponding owner instead.
      await prefs.setString(_key, jsonEncode(owners));
    });
    _binding = next.catchError((Object _) {});
    return next;
  }

  Future<void> forgetWhere(bool Function(String) matches) {
    final next = _binding.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final owners = _owners(prefs)..removeWhere((path, _) => matches(path));
      await prefs.setString(_key, jsonEncode(owners));
    });
    _binding = next.catchError((Object _) {});
    return next;
  }

  Future<bool> _canMigrateLegacy(
    SharedPreferences prefs,
    MediaServerHistoryConnection captured,
  ) async {
    final anchorKey = '${source}_watch_history_legacy_owner_v1';
    final anchor = prefs.getString(anchorKey);
    if (anchor != null && anchor != captured.owner) return false;
    try {
      final profiles =
          (jsonDecode(prefs.getString('server_profiles') ?? '[]') as List)
              .where((value) => value is Map && value['serverType'] == source)
              .cast<Map>()
              .toList();
      bool matches;
      if (captured.profileId != null) {
        matches = profiles.length == 1 &&
            profiles.single['id'] == captured.profileId &&
            profiles.single['userId'] == captured.userId &&
            prefs.getString('${source}_current_profile_id') ==
                captured.profileId;
      } else {
        matches = profiles.isEmpty &&
            captured.serverUrl != null &&
            prefs.getString('${source}_server_url') == captured.serverUrl &&
            prefs.getString('${source}_user_id') == captured.userId;
      }
      if (matches && anchor == null) {
        await prefs.setString(anchorKey, captured.owner);
      }
      return matches;
    } catch (_) {
      return false;
    }
  }

  Future<List<WatchHistoryItem>> refresh(
    List<WatchHistoryItem> histories, {
    String? Function()? activeItemId,
  }) async {
    final captured = connection();
    if (captured == null) return [];
    await _binding;
    final prefs = await SharedPreferences.getInstance();
    final owners = _owners(prefs);
    final migrateLegacy = await _canMigrateLegacy(prefs, captured);
    final eligible = histories
        .where((item) =>
            (owners[item.filePath] == captured.owner ||
                (migrateLegacy && !owners.containsKey(item.filePath))) &&
            item.filePath.startsWith('$source://') &&
            _itemId(item.filePath) != activeItemId?.call())
        .toList();
    final candidates = <WatchHistoryItem>[];
    if (eligible.isNotEmpty) {
      final start = _nextOffset % eligible.length;
      for (var i = 0; i < eligible.length && i < batchSize; i++) {
        candidates.add(eligible[(start + i) % eligible.length]);
      }
      _nextOffset = (start + candidates.length) % eligible.length;
    }
    if (candidates.isEmpty || connection()?.session != captured.session) {
      return [];
    }
    final query = Uri(queryParameters: {
      'Ids': candidates.map((item) => _itemId(item.filePath)).toSet().join(','),
      'EnableUserData': 'true',
      'Limit': '$batchSize',
    }).query;
    final response = await request(
        '/Users/${Uri.encodeComponent(captured.userId)}/Items?$query');
    if (response.statusCode != 200 ||
        connection()?.session != captured.session) {
      return [];
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = <String, Map<String, dynamic>>{};
    for (final value in (body['Items'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(value as Map);
      items[item['Id'].toString()] = item;
    }
    final changes = <WatchHistoryItem>[];
    for (final local in candidates) {
      if (_itemId(local.filePath) == activeItemId?.call()) continue;
      final remote = items[_itemId(local.filePath)];
      final userData = remote?['UserData'];
      if (userData is! Map) continue;
      if (!owners.containsKey(local.filePath)) {
        if (connection()?.session != captured.session) return [];
        await bind(local.filePath);
      }
      final merged = mergeMediaServerWatchHistory(
        local,
        Map<String, dynamic>.from(userData),
        durationMs: ((remote?['RunTimeTicks'] as num?)?.toInt() ?? 0) ~/ 10000,
      );
      if (merged != null) changes.add(merged);
    }
    return changes;
  }

  String _itemId(String path) =>
      path.substring('$source://'.length).split('/').last;
}
