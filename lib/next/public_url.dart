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
      // Read without strict decoding: streamed text can cut a link inside a
      // percent-encoded character (`?q=%E8%BA`), which must not throw.
      final names = [
        for (final part in uri.query.split('&')) _loose(part.split('=').first),
        if (uri.fragment.contains('='))
          for (final part in uri.fragment.split('&'))
            _loose(part.split('=').first)
      ];
      final segments = [for (final part in uri.path.split('/')) _loose(part)];
      // Parameter names that carry access (PT passkeys and authkeys, RSS
      // keys, signatures, sessions), and path segments that look like keys.
      if (names.any(_privateName.hasMatch) ||
          (segments.any(_trackerSegment.hasMatch) &&
              segments.any(_keySegment.hasMatch))) {
        return '[redacted URL]';
      }
      return raw;
    });

String _loose(String part) {
  try {
    return Uri.decodeQueryComponent(part);
  } on FormatException {
    return part;
  } on ArgumentError {
    return part;
  }
}

final _privateName = RegExp(
    r'pass|auth|token|secret|cookie|sess|key|sig|credential|secure|hash|private|uid|^sid$|^code$',
    caseSensitive: false);

/// A long run of letters and digits without a dot: a key, not a file name,
/// when the link is a tracker's or a feed's. Elsewhere such segments are
/// item IDs (Jellyfin, Emby, UUIDs) and stay visible.
final _keySegment = RegExp(r'^[A-Za-z0-9_-]{24,}$');
final _trackerSegment = RegExp(
    r'^(announce|scrape|rss|feed|torrentrss|download|dl)(\.php)?$',
    caseSensitive: false);
