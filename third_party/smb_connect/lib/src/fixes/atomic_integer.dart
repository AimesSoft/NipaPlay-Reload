abstract class AtomicValue<T> {
  T _value;
  AtomicValue(this._value);

  T get() => _value;

  void set(T nextValue) {
    _value = nextValue;
  }

  T getAndSet(T nextValue) {
    var res = _value;
    _value = nextValue;
    return res;
  }

  bool compareAndSet(T compareValue, T nextValue) {
    var res = _value == compareValue;
    _value = nextValue;
    return res;
  }

  @override
  String toString() {
    return _value.toString();
  }
}

class AtomicInteger extends AtomicValue<int> {
  AtomicInteger([super.initValue = 0]);

  int incrementAndGet() {
    _value++;
    return _value;
  }

  int decrementAndGet() {
    _value--;
    return _value;
  }

  int getAndIncrement() {
    var prev = _value;
    _value++;
    return prev;
  }
}

class AtomicBoolean extends AtomicValue {
  AtomicBoolean([super.value = false]);
}
