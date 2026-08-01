class AppHttpProxy {
  AppHttpProxy._();

  static String _endpoint = '';

  static Uri? validate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    final schemeSeparator = trimmed.indexOf('://');
    final rawAuthority = schemeSeparator < 0
        ? ''
        : trimmed.substring(schemeSeparator + 3).split(RegExp(r'[/#?]')).first;
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        rawAuthority.endsWith(':') ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Unsupported HTTP proxy endpoint');
    }
    final port = uri.hasPort ? uri.port : 80;
    if (port < 1 || port > 65535) {
      throw const FormatException(
          'HTTP proxy port must be between 1 and 65535');
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
    final host =
        endpoint.host.contains(':') ? '[${endpoint.host}]' : endpoint.host;
    return 'PROXY $host:$port';
  }
}
