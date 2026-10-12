/// Public locators remain usable; authenticated locators never leave the body.
String redactPrivateUrls(String text) => text.replaceAllMapped(
        RegExp(
            r'''(?<![a-zA-Z0-9+.-])[a-zA-Z][a-zA-Z0-9+.-]{0,31}://[^\s<>"'\\]+'''),
        (match) {
      final raw = match[0]!;
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.userInfo.isNotEmpty) {
        return '[redacted URL]';
      }
      final names = [
        ...uri.queryParameters.keys,
        if (uri.fragment.contains('='))
          ...Uri.splitQueryString(uri.fragment).keys
      ];
      // Parameter names that carry access (PT passkeys and authkeys, RSS
      // keys, signatures, sessions), and path segments that look like keys.
      if (names.any(_privateName.hasMatch) ||
          uri.pathSegments.any(_keySegment.hasMatch)) {
        return '[redacted URL]';
      }
      return raw;
    });

final _privateName = RegExp(
    r'pass|auth|token|secret|cookie|sess|key|sig|credential|secure|hash|private|uid|^sid$|^code$',
    caseSensitive: false);

/// A long run of letters and digits without a dot: a key, not a file name.
final _keySegment = RegExp(r'^[A-Za-z0-9_-]{24,}$');
