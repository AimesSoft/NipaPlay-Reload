# NipaPlay HarmonyOS dependency

This directory vendors `permission_handler_ohos` 12.0.1 from the
OpenHarmony-SIG adaptation.

The upstream monorepo's `br_v12.0.1_ohos` branch currently references a
missing Git LFS object under its example application, so Dart Pub cannot check
out the otherwise usable plugin package. Keeping the standalone package here
avoids depending on that unrelated example asset.
