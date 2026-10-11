/// The mounted Next shell supplies just one operation, without exposing its UI.
final class WorkDetailBridge {
  static Object? _owner;
  static Future<bool?> Function(String)? _open;
  static void attach(Object owner, Future<bool?> Function(String) open) {
    _owner = owner;
    _open = open;
  }

  static void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _open = null;
  }

  /// Null when Next is not visible; false when its detail cannot open.
  static Future<bool?> open(String id) async =>
      _open == null ? null : await _open!(id);
}
