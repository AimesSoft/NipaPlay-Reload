/// 仅在当前 Dart 进程中存活的异步列表缓存。
///
/// 不写入磁盘；应用进程结束后会自然释放。相同键的并发请求会复用同一个
/// Future，避免目录预加载与用户点击同时触发重复网络请求。
class ProcessMemoryListCache<K, V> {
  final Map<K, List<V>> _values = <K, List<V>>{};
  final Map<K, Future<List<V>>> _inFlight = <K, Future<List<V>>>{};
  int _generation = 0;

  Future<List<V>> getOrLoad(
    K key,
    Future<List<V>> Function() loader,
  ) async {
    final cached = _values[key];
    if (cached != null) {
      return List<V>.of(cached);
    }

    final pending = _inFlight[key];
    if (pending != null) {
      return List<V>.of(await pending);
    }

    final generation = _generation;
    final future = () async {
      final loaded = List<V>.unmodifiable(await loader());
      if (generation == _generation) {
        _values[key] = loaded;
      }
      return loaded;
    }();
    _inFlight[key] = future;

    try {
      return List<V>.of(await future);
    } finally {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }
  }

  void removeWhere(bool Function(K key) test) {
    _generation++;
    _values.removeWhere((key, _) => test(key));
    _inFlight.removeWhere((key, _) => test(key));
  }

  void clear() {
    _generation++;
    _values.clear();
    _inFlight.clear();
  }
}
