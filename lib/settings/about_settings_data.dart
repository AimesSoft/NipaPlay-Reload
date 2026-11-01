import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/acknowledgements.dart';
import 'package:nipaplay/utils/platform_identity.dart' as platform_identity;

class AboutSettingsData {
  const AboutSettingsData._();

  // Apple desktop and TV builds must not offer external donation payments.
  static bool get showSponsorship =>
      kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.macOS &&
          !platform_identity.isTvOS);

  static const sponsorNames = kAcknowledgementNames;
  static const repositoryUrl =
      'https://www.github.com/AimesSoft/NipaPlay-Reload';
  static const qqGroupUrl = 'https://qm.qq.com/q/w9j09QJn4Q';
  static const officialWebsiteUrl = 'https://nipaplay.aimes-soft.com';
  static const afdianUrl = 'https://afdian.com/a/irigas';
}
