# desktop_multi_window (NipaPlay fork)

This fork creates additional desktop `FlutterView`s in the existing Flutter
engine and isolate. It intentionally does not start a second engine or invoke
`main()` again. As a result, widgets rendered in a secondary window can inherit
and use the same providers and service instances as the main window.

The implementation wraps Flutter 3.44's experimental desktop windowing API.
It is vendored with NipaPlay so API changes can be handled together with the
application.

On macOS the runner enables the engine's multiview mode before attaching the
first `FlutterViewController`, as required by Flutter 3.44's embedder.
