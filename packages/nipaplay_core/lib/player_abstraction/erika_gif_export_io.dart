import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

final class _ErikaHttpHeader extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Utf8> value;
}

final class _ErikaGifExportOptions extends Struct {
  external Pointer<Utf8> inputUri;
  external Pointer<Utf8> outputPath;

  @Uint64()
  external int startMillis;

  @Uint64()
  external int endMillis;

  @Uint32()
  external int framesPerSecond;

  @Uint32()
  external int outputWidth;

  @Uint32()
  external int outputHeight;

  @Int32()
  external int quality;

  @Int32()
  external int loopCount;

  @Bool()
  external bool overwrite;

  external Pointer<_ErikaHttpHeader> headers;

  @IntPtr()
  external int headerCount;

  @Uint64()
  external int httpReadAheadBytes;

  @Array(3)
  external Array<Uint64> reserved;
}

final class _ErikaGifExportResult extends Struct {
  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @Uint64()
  external int frameCount;

  @Uint64()
  external int fileSize;
}

typedef _ExportGifNative = Int32 Function(
  Pointer<_ErikaGifExportOptions>,
  Pointer<_ErikaGifExportResult>,
);
typedef _ExportGifDart = int Function(
  Pointer<_ErikaGifExportOptions>,
  Pointer<_ErikaGifExportResult>,
);
typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _LastErrorDart = Pointer<Utf8> Function();
typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _StringFreeDart = void Function(Pointer<Utf8>);

Future<Map<String, Object?>> exportGifWithErika(
  Map<String, Object?> options,
) =>
    Isolate.run(() => _exportGifSync(options));

Map<String, Object?> _exportGifSync(Map<String, Object?> arguments) {
  final library = _openErikaLibrary();
  final exportGif = library.lookupFunction<_ExportGifNative, _ExportGifDart>(
    'erika_export_gif',
  );
  final lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
    'erika_last_error_message',
  );
  final stringFree = library.lookupFunction<_StringFreeNative, _StringFreeDart>(
    'erika_string_free',
  );

  final inputUri = (arguments['inputUri'] as String).toNativeUtf8();
  final outputPath = (arguments['outputPath'] as String).toNativeUtf8();
  final headerMap = Map<String, String>.from(
    arguments['httpHeaders'] as Map? ?? const <String, String>{},
  );
  final headers = headerMap.isEmpty
      ? nullptr.cast<_ErikaHttpHeader>()
      : calloc<_ErikaHttpHeader>(headerMap.length);
  final headerStrings = <Pointer<Utf8>>[];
  final options = calloc<_ErikaGifExportOptions>();
  final result = calloc<_ErikaGifExportResult>();
  try {
    var index = 0;
    for (final entry in headerMap.entries) {
      final name = entry.key.toNativeUtf8();
      final value = entry.value.toNativeUtf8();
      headerStrings.addAll(<Pointer<Utf8>>[name, value]);
      headers[index]
        ..name = name
        ..value = value;
      index += 1;
    }
    options.ref
      ..inputUri = inputUri
      ..outputPath = outputPath
      ..startMillis = arguments['startMillis'] as int
      ..endMillis = arguments['endMillis'] as int
      ..framesPerSecond = arguments['framesPerSecond'] as int
      ..outputWidth = arguments['outputWidth'] as int
      ..outputHeight = arguments['outputHeight'] as int
      ..quality = arguments['quality'] as int
      ..loopCount = 0
      ..overwrite = true
      ..headers = headers
      ..headerCount = headerMap.length
      ..httpReadAheadBytes = 0;

    final status = exportGif(options, result);
    if (status != 0) {
      final messagePointer = lastError();
      final message = messagePointer == nullptr
          ? 'ErikaStatus $status'
          : messagePointer.toDartString();
      if (messagePointer != nullptr) {
        stringFree(messagePointer);
      }
      throw StateError('GIF export failed: $message');
    }
    return <String, Object?>{
      'outputPath': arguments['outputPath'] as String,
      'width': result.ref.width,
      'height': result.ref.height,
      'frameCount': result.ref.frameCount,
      'fileSize': result.ref.fileSize,
    };
  } finally {
    calloc.free(inputUri);
    calloc.free(outputPath);
    for (final value in headerStrings) {
      calloc.free(value);
    }
    if (headers != nullptr) {
      calloc.free(headers);
    }
    calloc.free(options);
    calloc.free(result);
  }
}

DynamicLibrary _openErikaLibrary() {
  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }
  if (Platform.isMacOS) {
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final candidates = <String>[
      if (Platform.environment['ERIKA_CAPI_DYLIB'] case final path?) path,
      '${executableDirectory.parent.path}/Frameworks/liberika_capi.dylib',
      '${executableDirectory.path}/liberika_capi.dylib',
      'liberika_capi.dylib',
    ];
    Object? lastError;
    for (final candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Unable to load Erika C API: $lastError');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('erika_capi.dll');
  }
  if (Platform.isAndroid || Platform.operatingSystem == 'ohos') {
    return DynamicLibrary.open('liberika_capi.so');
  }
  throw UnsupportedError(
    'Erika GIF export is unavailable on ${Platform.operatingSystem}.',
  );
}
