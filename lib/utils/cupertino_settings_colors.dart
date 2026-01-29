import 'package:flutter/cupertino.dart';

/// 设置页动态配色工具，保证深浅色模式都能获得一致体验。

Color resolveSettingsSectionBackground(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    const CupertinoDynamicColor.withBrightness(
      color: CupertinoColors.white,
      darkColor: CupertinoColors.darkBackgroundGray,
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
    CupertinoTheme.of(context).primaryColor,
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
