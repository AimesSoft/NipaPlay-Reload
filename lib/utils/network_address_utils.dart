/// 网络地址工具：判断主机地址是否属于内网（私有地址）。
///
/// 用于媒体库连接在迁移历史数据时，将旧的单一地址自动归类为「内网」或
/// 「公网」，以及表单校验时的辅助判断。
class NetworkAddressUtils {
  NetworkAddressUtils._();

  /// 判断 [hostOrUrl] 是否指向内网/本地地址。
  ///
  /// 支持传入纯主机名（如 `192.168.1.10`、`nas.local`）或完整 URL
  /// （如 `http://192.168.1.10:5244/dav`）。无法解析或为空时返回 false。
  static bool isPrivateHost(String hostOrUrl) {
    final host = _extractHost(hostOrUrl);
    if (host.isEmpty) return false;

    final lower = host.toLowerCase();
    if (lower == 'localhost' || lower.endsWith('.local')) return true;

    // IPv6 字面量
    if (lower.contains(':')) {
      return _isPrivateIpv6(lower);
    }

    // IPv4 字面量
    return _isPrivateIpv4(lower);
  }

  static String _extractHost(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    // 优先按 URI 解析（去掉 scheme / 端口 / 路径 / 查询串）
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.host.isNotEmpty) {
      return _stripBrackets(uri.host);
    }

    // 退化为纯主机名（可能带端口）
    var host = trimmed;
    final schemeIndex = host.indexOf('://');
    if (schemeIndex >= 0) {
      host = host.substring(schemeIndex + 3);
    }
    final slashIndex = host.indexOf('/');
    if (slashIndex >= 0) {
      host = host.substring(0, slashIndex);
    }
    final atIndex = host.lastIndexOf('@');
    if (atIndex >= 0) {
      host = host.substring(atIndex + 1);
    }
    // IPv6 用方括号包裹，端口在括号外
    if (host.startsWith('[')) {
      final close = host.indexOf(']');
      if (close >= 0) {
        return _stripBrackets(host.substring(0, close + 1));
      }
    }
    final colonIndex = host.lastIndexOf(':');
    if (colonIndex >= 0) {
      host = host.substring(0, colonIndex);
    }
    return host;
  }

  static String _stripBrackets(String host) {
    if (host.startsWith('[') && host.endsWith(']')) {
      return host.substring(1, host.length - 1);
    }
    return host;
  }

  static bool _isPrivateIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      if (part.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(part)) return false;
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }

    final a = octets[0];
    final b = octets[1];

    // 10.0.0.0/8
    if (a == 10) return true;
    // 172.16.0.0/12
    if (a == 172 && b >= 16 && b <= 31) return true;
    // 192.168.0.0/16
    if (a == 192 && b == 168) return true;
    // 127.0.0.0/8（环回）
    if (a == 127) return true;
    // 169.254.0.0/16（链路本地）
    if (a == 169 && b == 254) return true;
    // 100.64.0.0/10（CGNAT）
    if (a == 100 && b >= 64 && b <= 127) return true;

    return false;
  }

  static bool _isPrivateIpv6(String host) {
    final lower = host.toLowerCase();
    // 环回 ::1
    if (lower == '::1') return true;
    // 未指定 ::
    if (lower == '::') return true;

    final firstGroup = lower.contains(':') ? lower.split(':').first : lower;
    if (firstGroup.isEmpty) {
      // 形如 ::1 已被上面拦截，其余需展开判断
      return lower.startsWith('::1') || lower.startsWith('fe80') || lower.startsWith('fc') || lower.startsWith('fd');
    }

    final group = int.tryParse(firstGroup, radix: 16);
    if (group == null) return false;
    // fe80::/10（链路本地）
    if ((group & 0xffc0) == 0xfe80) return true;
    // fc00::/7（唯一本地）
    if ((group & 0xfe00) == 0xfc00) return true;
    return false;
  }

  /// 判断 [hostOrUrl] 是否为「可能是公网」的外部地址。
  ///
  /// 目前用于迁移决策：非私有的合法主机即视为公网。
  static bool isPublicHost(String hostOrUrl) {
    final host = _extractHost(hostOrUrl);
    if (host.isEmpty) return false;
    return !isPrivateHost(hostOrUrl);
  }
}
