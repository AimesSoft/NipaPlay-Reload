class AppHttpProxy {
  AppHttpProxy._();

  static String _endpoint = '';

  static String get endpoint => _endpoint;

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

  static bool isLoopback(Uri target) {
    var host = target.host.toLowerCase();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host == 'localhost' || host == 'localhost.') return true;
    try {
      if (host.startsWith('127.')) {
        return Uri.parseIPv4Address(host).first == 127;
      }
      if (host.contains(':')) {
        final bytes = Uri.parseIPv6Address(host);
        if (bytes.take(15).every((b) => b == 0) && bytes.last == 1) {
          return true;
        }
        // IPv4-mapped IPv6 loopback addresses name the same local service.
        return bytes.take(10).every((b) => b == 0) &&
            bytes[10] == 255 &&
            bytes[11] == 255 &&
            bytes[12] == 127;
      }
    } on FormatException {
      // Hostnames resembling an IP must keep their configured proxy policy.
    }
    return false;
  }

  static String findProxy(
    Uri target,
    String Function(Uri target) systemProxy,
  ) {
    // A loopback URL names a service in this process's network namespace.
    // Sending it to an outbound proxy would address the proxy's own machine
    // instead (Mesh playback, local MCP and plugin HTTP bridges use these).
    if (isLoopback(target)) return 'DIRECT';
    final endpoint = validate(_endpoint);
    if (endpoint == null) return systemProxy(target);
    final port = endpoint.hasPort ? endpoint.port : 80;
    return 'PROXY ${endpoint.host}:$port';
  }
}
