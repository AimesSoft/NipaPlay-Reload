# Upstream

This package is based on the OpenHarmony SIG
`fluttertpc_wakelock_plus` branch `br_wakelock_plus_1.2.8_ohos`.

NipaPlay keeps the HarmonyOS plugin local because the upstream ArkTS Pigeon
codec uses the old custom type IDs. The local version matches
`wakelock_plus_platform_interface` 1.3.x:

- `ToggleMessage`: 129
- `IsEnabledMessage`: 130

The upstream source is licensed under Apache-2.0.
