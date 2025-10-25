import 'package:flutter/cupertino.dart';

/// 设置页动态配色工具，保证深浅色模式都能获得一致体验。

Color resolveSettingsSectionBackground(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    const CupertinoDynamicColor.withBrightness(
      color: Color(0xFFF2F2F7),
      darkColor: Color(0xFF1C1C1E),
    ),
    context,
  );
}

Color resolveSettingsTileBackground(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    const CupertinoDynamicColor.withBrightness(
      color: Color(0xFFFFFFFF),
      darkColor: Color(0xFF2C2C2E),
    ),
    context,
  );
}

Color resolveSettingsCardBackground(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    const CupertinoDynamicColor.withBrightness(
      color: Color(0xFFFFFFFF),
      darkColor: Color(0xFF1C1C1E),
    ),
    context,
  );
}

Color resolveSettingsIconColor(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    CupertinoColors.systemBlue,
    context,
  );
}

Color resolveSettingsSeparatorColor(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    const CupertinoDynamicColor.withBrightness(
      color: Color(0x1F000000),
      darkColor: Color(0x33FFFFFF),
    ),
    context,
  );
}

Color resolveSettingsPrimaryTextColor(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    CupertinoColors.label,
    context,
  );
}

Color resolveSettingsSecondaryTextColor(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    CupertinoColors.secondaryLabel,
    context,
  );
}
