enum RemoteAccessAddressType {
  local,
  lan,
  wan,
  unknown,
}

class RemoteAccessAddressUtils {
  static RemoteAccessAddressType classifyUrl(String url) {
    final host = _tryGetHost(url);
    if (host == null || host.isEmpty) return RemoteAccessAddressType.unknown;

    final normalizedHost = host.toLowerCase();
    if (normalizedHost == 'localhost' || normalizedHost == '127.0.0.1' || normalizedHost == '::1') {
      return RemoteAccessAddressType.local;
    }

    final ipv4 = _parseIpv4(host);
    if (ipv4 != null) {
      if (ipv4[0] == 127) return RemoteAccessAddressType.local;
      if (_isPrivateOrLanIpv4(ipv4)) return RemoteAccessAddressType.lan;
      return RemoteAccessAddressType.wan;
    }

    if (host.contains(':')) {
      if (normalizedHost == '::1') return RemoteAccessAddressType.local;
      if (normalizedHost.startsWith('fe80:') ||
          normalizedHost.startsWith('fc') ||
          normalizedHost.startsWith('fd')) {
        return RemoteAccessAddressType.lan;
      }
      return RemoteAccessAddressType.wan;
    }

    return RemoteAccessAddressType.unknown;
  }

  static String labelZh(RemoteAccessAddressType type) {
    switch (type) {
      case RemoteAccessAddressType.local:
        return '本机';
      case RemoteAccessAddressType.lan:
        return '内网';
      case RemoteAccessAddressType.wan:
        return '外网';
      case RemoteAccessAddressType.unknown:
      default:
        return '未知';
    }
  }

  static String? _tryGetHost(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return null;
    }
  }

  static List<int>? _parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;

    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return null;
      octets.add(value);
    }
    return octets;
  }

  static bool _isPrivateOrLanIpv4(List<int> octets) {
    final a = octets[0];
    final b = octets[1];

    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 169 && b == 254) return true; // Link-local
    if (a == 100 && b >= 64 && b <= 127) return true; // CGNAT

    return false;
  }
}

