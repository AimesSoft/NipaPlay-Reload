# HarmonyOS numeric preference compatibility

Source: openharmony-tpc/flutter_packages, br_shared_preferences-v2.5.4_ohos,
commit a671ca01767309608b643587746e486c176107e3,
packages/shared_preferences/shared_preferences (2.5.4).

Used only by pubspec_overrides.ohos.yaml. The HarmonyOS preferences bridge
returns whole-valued doubles as Dart ints after process restart. getDouble
accepts num and converts to double, retaining existing on-device values.
Non-numeric values still throw. Other platform dependency graphs are unchanged.
