import 'subtitle_font_loader_impl_stub.dart'
    if (dart.library.io) 'subtitle_font_loader_impl_io.dart' as impl;

Future<Map<String, String>?> ensureSubtitleFontFromAsset({
  required String assetPath,
  String fileName = 'subfont.ttf',
}) {
  return impl.ensureSubtitleFontFromAssetImpl(
    assetPath: assetPath,
    fileName: fileName,
  );
}
