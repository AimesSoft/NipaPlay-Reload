String encodeDanmakuXmlText(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String decodeDanmakuXmlText(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

int parseDanmakuColorToInt(dynamic colorValue) {
  if (colorValue == null) return 0xFFFFFF;

  if (colorValue is int) return colorValue & 0xFFFFFF;
  if (colorValue is num) return colorValue.toInt() & 0xFFFFFF;

  final text = colorValue.toString().trim();
  if (text.isEmpty) return 0xFFFFFF;

  final rgbMatch = RegExp(
    r'rgb\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)',
    caseSensitive: false,
  ).firstMatch(text);
  if (rgbMatch != null) {
    final r = int.tryParse(rgbMatch.group(1) ?? '') ?? 255;
    final g = int.tryParse(rgbMatch.group(2) ?? '') ?? 255;
    final b = int.tryParse(rgbMatch.group(3) ?? '') ?? 255;
    return (_clampColorComponent(r) << 16) |
        (_clampColorComponent(g) << 8) |
        _clampColorComponent(b);
  }

  if (text.startsWith('#')) {
    var hex = text.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    } else if (hex.length == 8) {
      hex = hex.substring(2);
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) return parsed & 0xFFFFFF;
  }

  if (text.startsWith('0x') || text.startsWith('0X')) {
    final parsed = int.tryParse(text.substring(2), radix: 16);
    if (parsed != null) return parsed & 0xFFFFFF;
  }

  final parsed = int.tryParse(text);
  if (parsed != null) return parsed & 0xFFFFFF;

  return 0xFFFFFF;
}

int _clampColorComponent(int value) {
  return value.clamp(0, 255).toInt();
}
