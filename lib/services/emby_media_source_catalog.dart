import '../models/emby_media_selection.dart';
import '../models/media_server_playback.dart';

typedef EmbyMediaSourceLoader = Future<List<PlaybackMediaSource>> Function(
  String itemId,
);

abstract interface class EmbyMediaSourceCatalog {
  Future<List<EmbyMediaSourceDescriptor>> load(
    String cacheScopeKey,
    String itemId, {
    bool forceRefresh = false,
  });

  void invalidateScope(String cacheScopeKey);

  void clear();
}

class CachedEmbyMediaSourceCatalog implements EmbyMediaSourceCatalog {
  CachedEmbyMediaSourceCatalog({
    required EmbyMediaSourceLoader loader,
    this.ttl = const Duration(minutes: 2),
    DateTime Function()? now,
  })  : _loader = loader,
        _now = now ?? DateTime.now;

  final EmbyMediaSourceLoader _loader;
  final Duration ttl;
  final DateTime Function() _now;
  final Map<_CatalogKey, _CatalogEntry> _entries = {};

  @override
  Future<List<EmbyMediaSourceDescriptor>> load(
    String cacheScopeKey,
    String itemId, {
    bool forceRefresh = false,
  }) {
    final key = _CatalogKey(cacheScopeKey, itemId);
    final existing = _entries[key];
    if (existing != null) {
      if (existing.isInFlight || (!forceRefresh && existing.isFresh(_now()))) {
        return existing.future;
      }
    }

    final entry = _CatalogEntry();
    _entries[key] = entry;
    entry.future = _loadEntry(key, itemId, entry);
    return entry.future;
  }

  @override
  void invalidateScope(String cacheScopeKey) {
    _entries.removeWhere((key, _) => key.cacheScopeKey == cacheScopeKey);
  }

  @override
  void clear() => _entries.clear();

  Future<List<EmbyMediaSourceDescriptor>> _loadEntry(
    _CatalogKey key,
    String itemId,
    _CatalogEntry entry,
  ) async {
    try {
      final sources = await _loader(itemId);
      final descriptors = List<EmbyMediaSourceDescriptor>.unmodifiable([
        for (var index = 0; index < sources.length; index++)
          describeEmbyMediaSource(sources[index], ordinal: index),
      ]);
      entry.expiresAt = _now().add(ttl);
      return descriptors;
    } catch (_) {
      if (identical(_entries[key], entry)) {
        _entries.remove(key);
      }
      rethrow;
    }
  }
}

class _CatalogKey {
  const _CatalogKey(this.cacheScopeKey, this.itemId);

  final String cacheScopeKey;
  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is _CatalogKey &&
      cacheScopeKey == other.cacheScopeKey &&
      itemId == other.itemId;

  @override
  int get hashCode => Object.hash(cacheScopeKey, itemId);
}

class _CatalogEntry {
  _CatalogEntry();

  DateTime? expiresAt;
  late final Future<List<EmbyMediaSourceDescriptor>> future;

  bool get isInFlight => expiresAt == null;

  bool isFresh(DateTime now) => expiresAt != null && now.isBefore(expiresAt!);
}
