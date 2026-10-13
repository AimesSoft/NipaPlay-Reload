const immutable = _Immutable();

final class _Immutable {
  const _Immutable();
}

const kIsWeb = false;
void debugPrint(String? message) {}

/// The router's observable snapshot has no widget subscribers in a Dart host.
final class ValueNotifier<T> {
  ValueNotifier(this.value);
  T value;
}
