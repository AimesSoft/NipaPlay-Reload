import 'dart:async';
import 'dart:collection';

class _ProcessMemoryListCacheEntry<V> {
  const _ProcessMemoryListCacheEntry({
    required this.values,
    required this.loadedAt,
  });

  final List<V> values;
  final DateTime loadedAt;
}

/// 仅在当前 Dart 进程中存活的异步列表缓存。
///
/// 不写入磁盘；应用进程结束后会自然释放。相同键的并发请求会复用同一个
/// Future，避免目录预加载与用户点击同时触发重复网络请求。
///
/// 缓存采用按访问顺序淘汰的 LRU，并同时限制键数量和列表元素总数。新鲜期
/// 结束后默认先返回旧值、再在后台重新验证；显式强刷会等待真实加载完成。
class ProcessMemoryListCache<K, V> {
  ProcessMemoryListCache({
    this.maxEntries = 64,
    this.maxTotalValues = 20000,
    this.maxAge = const Duration(minutes: 2),
    DateTime Function()? now,
  })  : assert(maxEntries > 0),
        assert(maxTotalValues > 0),
        _now = now ?? DateTime.now;

  final int maxEntries;
  final int maxTotalValues;
  final Duration maxAge;
  final DateTime Function() _now;

  final LinkedHashMap<K, _ProcessMemoryListCacheEntry<V>> _values =
      LinkedHashMap<K, _ProcessMemoryListCacheEntry<V>>();
  final Map<K, Future<List<V>>> _inFlight = <K, Future<List<V>>>{};
  final Map<K, int> _keyGenerations = <K, int>{};
  int _clearGeneration = 0;
  int _totalValues = 0;

  Future<List<V>> getOrLoad(
    K key,
    Future<List<V>> Function() loader, {
    bool forceRefresh = false,
    bool staleWhileRevalidate = true,
  }) async {
    final cached = _touch(key);
    if (!forceRefresh && cached != null) {
      final isFresh = _now().difference(cached.loadedAt) <= maxAge;
      if (isFresh) {
        return List<V>.of(cached.values);
      }

      if (staleWhileRevalidate) {
        final refresh = _inFlight[key] ?? _startLoad(key, loader);
        // 后台刷新失败时保留旧值；调用方仍可通过显式强刷观察错误。
        unawaited(refresh.then<void>((_) {}, onError: (_) {}));
        return List<V>.of(cached.values);
      }
    }

    final pending = _inFlight[key];
    if (pending != null) {
      return List<V>.of(await pending);
    }

    return List<V>.of(await _startLoad(key, loader));
  }

  _ProcessMemoryListCacheEntry<V>? _touch(K key) {
    final cached = _values.remove(key);
    if (cached != null) {
      _values[key] = cached;
    }
    return cached;
  }

  Future<List<V>> _startLoad(
    K key,
    Future<List<V>> Function() loader,
  ) {
    final clearGeneration = _clearGeneration;
    final keyGeneration = _keyGenerations[key] ?? 0;
    late final Future<List<V>> future;
    future = () async {
      final loaded = List<V>.unmodifiable(await loader());
      if (clearGeneration == _clearGeneration &&
          keyGeneration == (_keyGenerations[key] ?? 0)) {
        _store(key, loaded);
      }
      return loaded;
    }();
    _inFlight[key] = future;

    void removeInFlight() {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }

    unawaited(future.then<void>(
      (_) => removeInFlight(),
      onError: (_, __) => removeInFlight(),
    ));
    return future;
  }

  void _store(K key, List<V> loaded) {
    final previous = _values.remove(key);
    if (previous != null) {
      _totalValues -= previous.values.length;
    }

    // 单个异常大目录不进入缓存，确保元素总数上限真实有效。
    if (loaded.length > maxTotalValues) {
      return;
    }

    _values[key] = _ProcessMemoryListCacheEntry<V>(
      values: loaded,
      loadedAt: _now(),
    );
    _totalValues += loaded.length;
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    while (_values.length > maxEntries || _totalValues > maxTotalValues) {
      final oldestKey = _values.keys.first;
      final removed = _values.remove(oldestKey);
      if (removed != null) {
        _totalValues -= removed.values.length;
      }
    }
  }

  void removeWhere(bool Function(K key) test) {
    final matchingKeys = <K>{
      ..._values.keys.where(test),
      ..._inFlight.keys.where(test),
    };
    for (final key in matchingKeys) {
      final removed = _values.remove(key);
      if (removed != null) {
        _totalValues -= removed.values.length;
      }
      _keyGenerations[key] = (_keyGenerations[key] ?? 0) + 1;
      _inFlight.remove(key);
    }
  }

  void clear() {
    _clearGeneration++;
    _values.clear();
    _inFlight.clear();
    _keyGenerations.clear();
    _totalValues = 0;
  }
}
