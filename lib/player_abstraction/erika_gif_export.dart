import 'erika_gif_export_stub.dart'
    if (dart.library.io) 'erika_gif_export_io.dart' as implementation;

Future<Map<String, Object?>> exportGifWithErika(
  Map<String, Object?> options,
) =>
    implementation.exportGifWithErika(options);
