const Map<String, String> _subtitleLanguageCodes = <String, String>{
  'chi': '中文',
  'zho': '中文',
  'eng': '英文',
  'jpn': '日语',
  'kor': '韩语',
  'fra': '法语',
  'deu': '德语',
  'ger': '德语',
  'spa': '西班牙语',
  'ita': '意大利语',
  'rus': '俄语',
  'ind': '印尼语',
};

final Map<RegExp, String> _subtitleLanguagePatterns = <RegExp, String>{
  RegExp(
    r'simplified|简体|chs|imp|zh-hans|zh-cn|zh-sg|(?:^|[^a-z])sc(?:$|[^a-z])|scjp|chsjpn',
    caseSensitive: false,
  ): '简体中文',
  RegExp(
    r'traditional|繁体|cht|rad|zh-hant|zh-tw|zh-hk|(?:^|[^a-z])tc(?:$|[^a-z])|tcjp|chtjpn',
    caseSensitive: false,
  ): '繁体中文',
  RegExp(r'chi|zho|chinese|中文|zh', caseSensitive: false): '中文',
  RegExp(r'eng|(?:^|[^a-z])en(?:$|[^a-z])|英文|english', caseSensitive: false):
      '英文',
  RegExp(r'jpn|(?:^|[^a-z])ja(?:$|[^a-z])|日文|japanese', caseSensitive: false):
      '日语',
  RegExp(r'kor|(?:^|[^a-z])ko(?:$|[^a-z])|韩文|korean', caseSensitive: false):
      '韩语',
  RegExp(r'fra|(?:^|[^a-z])fr(?:$|[^a-z])|法文|french', caseSensitive: false):
      '法语',
  RegExp(r'ger|deu|(?:^|[^a-z])de(?:$|[^a-z])|德文|german', caseSensitive: false):
      '德语',
  RegExp(
    r'spa|(?:^|[^a-z])es(?:$|[^a-z])|西班牙文|spanish',
    caseSensitive: false,
  ): '西班牙语',
  RegExp(
    r'ita|(?:^|[^a-z])it(?:$|[^a-z])|意大利文|italian',
    caseSensitive: false,
  ): '意大利语',
  RegExp(r'rus|(?:^|[^a-z])ru(?:$|[^a-z])|俄文|russian', caseSensitive: false):
      '俄语',
  RegExp(
    r'ind|(?:^|[^a-z])id(?:$|[^a-z])|印尼文|indonesian',
    caseSensitive: false,
  ): '印尼语',
};

String getSubtitleLanguageName(String language, {String unknownLabel = '未知'}) {
  final trimmed = language.trim();
  if (trimmed.isEmpty) {
    return unknownLabel;
  }

  final lower = trimmed.toLowerCase();
  final codeMapped = _subtitleLanguageCodes[lower];
  if (codeMapped != null) {
    return codeMapped;
  }

  for (final entry in _subtitleLanguagePatterns.entries) {
    if (entry.key.hasMatch(lower)) {
      return entry.value;
    }
  }

  return trimmed;
}
