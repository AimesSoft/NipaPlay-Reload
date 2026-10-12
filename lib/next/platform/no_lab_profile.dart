abstract final class LabProfile {
  static const active = false;
  static const String? name = null;
  static String get root =>
      throw StateError('Dart host uses its own data root.');
  static String location(String child) => '$root/$child';
}
