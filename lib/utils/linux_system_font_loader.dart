import 'linux_system_font_loader_impl_stub.dart'
    if (dart.library.io) 'linux_system_font_loader_impl_io.dart' as impl;

const String linuxSystemCjkFontFamily = 'NipaPlayLinuxSystemCjk';

Future<void> ensureLinuxSystemFontLoaded() {
  return impl.ensureLinuxSystemFontLoadedImpl(linuxSystemCjkFontFamily);
}

List<String>? get linuxSystemFontFallback {
  if (!impl.isLinuxSystemFontLoaded) {
    return null;
  }
  return const <String>[linuxSystemCjkFontFamily];
}
