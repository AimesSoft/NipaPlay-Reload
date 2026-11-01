import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/acknowledgements.dart';
import 'package:nipaplay/utils/platform_identity.dart' as platform_identity;

class AboutSettingsData {
  const AboutSettingsData._();

  // Set only for App Store builds; public GitHub packages keep sponsorship.
  static const isAppStoreBuild =
      bool.fromEnvironment('NIPAPLAY_APP_STORE', defaultValue: false);

  static bool get showSponsorship =>
      kIsWeb ||
      !isAppStoreBuild ||
      (defaultTargetPlatform != TargetPlatform.macOS &&
          !platform_identity.isTvOS);

  static const sponsorNames = kAcknowledgementNames;
  static const repositoryUrl =
      'https://www.github.com/AimesSoft/NipaPlay-Reload';
  static const qqGroupUrl = 'https://qm.qq.com/q/w9j09QJn4Q';
  static const officialWebsiteUrl = 'https://nipaplay.aimes-soft.com';
  static const afdianUrl = 'https://afdian.com/a/irigas';
}
