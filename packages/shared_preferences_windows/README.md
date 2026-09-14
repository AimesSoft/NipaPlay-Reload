# shared\_preferences\_windows

The Windows implementation of [`shared_preferences`][1].

## Usage

This package is [endorsed][2], which means you can simply use `shared_preferences`
normally. This package will be automatically included in your app when you do,
so you do not need to add it to your `pubspec.yaml`.

However, if you `import` this package to use any of its APIs directly, you
should add it to your `pubspec.yaml` as usual.

[1]: https://pub.dev/packages/shared_preferences
[2]: https://flutter.dev/to/endorsed-federated-plugin

## NipaPlay local patch (upstream 2.4.1)

The upstream Windows implementation uses synchronous file operations even though
its public setters return Futures. NipaPlay persists playback position every
2 seconds of media progress, so these calls can block the Flutter UI isolate.

This fork uses asynchronous file reads, existence checks, creation and writes.
Writes capture their preference snapshot and run in invocation order; reads wait
for pending writes. Public interfaces, filename, encoding and settings remain
compatible. JSON encoding still runs on the caller isolate.

Run `flutter test --no-pub packages/shared_preferences_windows/test` from the
application root. The slow-disk test blocks a write while proving the event loop
remains runnable and a newer position cannot be overwritten by an older write.
