# desktop_multi_window (NipaPlay fork)

This fork creates additional desktop `FlutterView`s in the existing Flutter
engine and isolate. It intentionally does not start a second engine or invoke
`main()` again. As a result, widgets rendered in a secondary window can inherit
and use the same providers and service instances as the main window.

The implementation wraps Flutter 3.47's experimental desktop windowing API.
This package is selected only by NipaPlay's Linux dependency profile so the
mainline and HarmonyOS Flutter pins remain independent.

The Linux runner enables the engine's multiview mode before attaching the first
secondary view.
