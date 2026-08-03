import 'dart:io';

/// Flutter tvOS intentionally keeps iOS compatibility, so [Platform.isIOS]
/// is also true on Apple TV. Use the operating-system string when behavior
/// must differ between the two platforms.
bool get isTvOS => Platform.operatingSystem == 'tvos';

/// OpenHarmony follows the same pattern with its custom OS identifier.
bool get isHarmonyOS => Platform.operatingSystem == 'ohos';
