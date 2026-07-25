class AppHttpProxy {
  AppHttpProxy._();

  static String _endpoint = '';

  static Uri? validate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Unsupported HTTP proxy endpoint');
    }
    return uri;
  }

  static void set(String value) {
    _endpoint = validate(value)?.toString() ?? '';
  }

  static void clear() => _endpoint = '';

  static String findProxy(
    Uri target,
    String Function(Uri target) systemProxy,
  ) {
    final endpoint = validate(_endpoint);
    if (endpoint == null) return systemProxy(target);
    final port = endpoint.hasPort ? endpoint.port : 80;
    return 'PROXY ${endpoint.host}:$port';
  }
}
