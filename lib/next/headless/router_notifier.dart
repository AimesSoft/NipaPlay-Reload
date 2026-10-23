const immutable = _Immutable();
const visibleForTesting = _Immutable();

final class _Immutable {
  const _Immutable();
}

const kIsWeb = false;
void debugPrint(String? message) {}

final class ValueNotifier<T> {
  ValueNotifier(this._value);
  T _value;
  final _listeners = <void Function()>[];
  T get value => _value;
  set value(T next) {
    if (_value == next) return;
    _value = next;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
}
