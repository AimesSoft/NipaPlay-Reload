import 'package:flutter/widgets.dart';

class AppLocaleUtils {
  AppLocaleUtils._();

  static const Locale simplifiedChinese =
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
  static const Locale traditionalChinese =
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  static const Locale english = Locale('en');

  static const List<Locale> supportedLocales = [
    simplifiedChinese,
    traditionalChinese,
    english,
  ];

  static bool isTraditionalChineseLocale(Locale locale) {
    if (locale.languageCode.toLowerCase() != 'zh') {
      return false;
    }

    final scriptCode = locale.scriptCode?.toLowerCase();
    if (scriptCode == 'hant') {
      return true;
    }
    if (scriptCode == 'hans') {
      return false;
    }

    final countryCode = locale.countryCode?.toUpperCase();
    return countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO';
  }

  static Locale resolveLocaleFromSystem(Locale systemLocale) {
    if (systemLocale.languageCode.toLowerCase() == 'en') {
      return english;
    }
    return isTraditionalChineseLocale(systemLocale)
        ? traditionalChinese
        : simplifiedChinese;
  }
}
