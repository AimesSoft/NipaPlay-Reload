/// How the player's menus name a track, the same whichever playback is
/// behind them: its title, else its language, else its number.
abstract final class TrackLabels {
  static const _languages = {
    'chi': '中文', 'zho': '中文', 'zh': '中文', 'chs': '简体中文',
    'cht': '繁体中文', 'jpn': '日语', 'ja': '日语', 'eng': '英语',
    'en': '英语', 'kor': '韩语', 'ko': '韩语',
    'ger': '德语', 'deu': '德语', 'de': '德语',
    'fre': '法语', 'fra': '法语', 'fr': '法语',
    'spa': '西班牙语', 'es': '西班牙语',
    'ita': '意大利语', 'it': '意大利语',
    'dut': '荷兰语', 'nld': '荷兰语', 'nl': '荷兰语',
    'pol': '波兰语', 'pl': '波兰语',
    'por': '葡萄牙语', 'pt': '葡萄牙语',
    'rus': '俄语', 'ru': '俄语',
    'vie': '越南语', 'vi': '越南语',
    'tha': '泰语', 'th': '泰语',
    'ara': '阿拉伯语', 'ar': '阿拉伯语',
  };

  static String of(String? title, String? language, int index,
      {String fallback = '字幕'}) {
    final t = title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final l = language?.trim().toLowerCase() ?? '';
    if (l.isNotEmpty) return _languages[l] ?? language!.trim();
    return '$fallback ${index + 1}';
  }

  /// Two tracks called the same are told apart by their codec, or number.
  static String distinct(List<String> labels, int i, String? codec) {
    final label = labels[i];
    if (labels.where((l) => l == label).length < 2) return label;
    final c = codec?.trim() ?? '';
    return c.isNotEmpty && !c.startsWith('Unknown')
        ? '$label · ${c.toUpperCase()}'
        : '$label ${i + 1}';
  }
}
