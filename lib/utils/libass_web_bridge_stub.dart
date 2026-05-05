// Non-web stub — all methods are no-ops.

class LibassWebBridge {
  static bool get available => false;
  static bool get isActive => false;

  static Future<void> initWithUrl(String subUrl) async {}
  static Future<void> initWithContent(String assContent) async {}
  static void dispose() {}
  static void resize() {}
  static void setTimeOffset(double seconds) {}
}
