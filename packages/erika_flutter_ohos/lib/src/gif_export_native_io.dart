import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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
final class _ErikaFrameExportOptions extends Struct {
  external Pointer<Utf8> inputUri;

  external Pointer<_ErikaHttpHeader> headers;

  @IntPtr()
  external int headerCount;

  @Uint64()
  external int positionMillis;

  @Uint64()
  external int httpReadAheadBytes;

  @Uint32()
  external int maxWidth;

  @Uint32()
  external int maxHeight;

  @Int32()
  external int format;

  @Uint32()
  external int reservedFlags;

  @Array(4)
  external Array<Uint64> reserved;
}

final class _ErikaFrameExportResult extends Struct {
  external Pointer<Uint8> data;

  @IntPtr()
  external int dataLen;

  @Uint64()
  external int timestampMicros;

  @Uint64()
  external int durationMicros;

  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @Uint32()
  external int sourceWidth;

  @Uint32()
  external int sourceHeight;

  @Int32()
  external int format;

  @Uint32()
  external int reservedFlags;

  @Array(2)
  external Array<Uint64> reserved;
}

typedef _ExportFrameNative = Int32 Function(
  Pointer<_ErikaFrameExportOptions>,
  Pointer<_ErikaFrameExportResult>,
);
typedef _ExportFrameDart = int Function(
  Pointer<_ErikaFrameExportOptions>,
  Pointer<_ErikaFrameExportResult>,
);
typedef _FrameResultFreeNative = Void Function(Pointer<_ErikaFrameExportResult>);
typedef _FrameResultFreeDart = void Function(Pointer<_ErikaFrameExportResult>);
final class _ErikaFrameExportSessionOptions extends Struct {
  external Pointer<Utf8> inputUri;

  external Pointer<_ErikaHttpHeader> headers;

  @IntPtr()
  external int headerCount;

  @Uint64()
  external int httpReadAheadBytes;

  @Uint32()
  external int reservedFlags;

  @Array(4)
  external Array<Uint64> reserved;
}

final class _ErikaFrameExportRequest extends Struct {
  @Uint64()
  external int positionMillis;

  @Uint32()
  external int maxWidth;

  @Uint32()
  external int maxHeight;

  @Int32()
  external int format;

  @Uint32()
  external int reservedFlags;

  @Array(4)
  external Array<Uint64> reserved;
}

typedef _SessionOpenNative = Int32 Function(
  Pointer<_ErikaFrameExportSessionOptions>,
  Pointer<Pointer<Void>>,
);
typedef _SessionOpenDart = int Function(
  Pointer<_ErikaFrameExportSessionOptions>,
  Pointer<Pointer<Void>>,
);
typedef _SessionFrameNative = Int32 Function(
  Pointer<Void>,
  Pointer<_ErikaFrameExportRequest>,
  Pointer<_ErikaFrameExportResult>,
);
typedef _SessionFrameDart = int Function(
  Pointer<Void>,
  Pointer<_ErikaFrameExportRequest>,
  Pointer<_ErikaFrameExportResult>,
);
typedef _SessionCloseNative = Void Function(Pointer<Void>);
typedef _SessionCloseDart = void Function(Pointer<Void>);

/// Bit 0 of `reserved_flags` in a frame export result.
const int _toneMappedFlag = 1;

typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _LastErrorDart = Pointer<Utf8> Function();
typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _StringFreeDart = void Function(Pointer<Utf8>);

Future<Map<String, Object?>> exportGifNative(Map<String, Object?> options) =>
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
      ..loopCount = arguments['loopCount'] as int
      ..overwrite = arguments['overwrite'] as bool
      ..headers = headers
      ..headerCount = headerMap.length
      ..httpReadAheadBytes = arguments['httpReadAheadBytes'] as int? ?? 0;

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

Future<Map<String, Object?>> exportFrameNative(Map<String, Object?> options) =>
    Isolate.run(() => _exportFrameSync(options));

Map<String, Object?> _exportFrameSync(Map<String, Object?> arguments) {
  final library = _openErikaLibrary();
  final _ExportFrameDart exportFrame;
  final _FrameResultFreeDart freeResult;
  try {
    exportFrame = library.lookupFunction<_ExportFrameNative, _ExportFrameDart>(
      'erika_export_frame',
    );
    freeResult =
        library.lookupFunction<_FrameResultFreeNative, _FrameResultFreeDart>(
      'erika_frame_export_result_free',
    );
  } on ArgumentError {
    throw UnsupportedError(
      'The bundled liberika native library has no erika_export_frame.',
    );
  }
  final lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
    'erika_last_error_message',
  );
  final stringFree = library.lookupFunction<_StringFreeNative, _StringFreeDart>(
    'erika_string_free',
  );

  final inputUri = (arguments['uri'] as String).toNativeUtf8();
  final headerMap = Map<String, String>.from(
    arguments['httpHeaders'] as Map? ?? const <String, String>{},
  );
  final headers = headerMap.isEmpty
      ? nullptr.cast<_ErikaHttpHeader>()
      : calloc<_ErikaHttpHeader>(headerMap.length);
  final headerStrings = <Pointer<Utf8>>[];
  final options = calloc<_ErikaFrameExportOptions>();
  final result = calloc<_ErikaFrameExportResult>();
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
      ..headers = headers
      ..headerCount = headerMap.length
      ..positionMillis = arguments['positionMillis'] as int
      ..httpReadAheadBytes = arguments['httpReadAheadBytes'] as int? ?? 0
      ..maxWidth = arguments['width'] as int? ?? 0
      ..maxHeight = arguments['height'] as int? ?? 0
      ..format = arguments['format'] as int? ?? 1;

    final status = exportFrame(options, result);
    if (status != 0) {
      final messagePointer = lastError();
      final message = messagePointer == nullptr
          ? 'ErikaStatus $status'
          : messagePointer.toDartString();
      if (messagePointer != nullptr) {
        stringFree(messagePointer);
      }
      throw StateError('Frame export failed: $message');
    }
    try {
      final frame = result.ref;
      return <String, Object?>{
        'width': frame.width,
        'height': frame.height,
        'format': frame.format,
        'bytes': Uint8List.fromList(frame.data.asTypedList(frame.dataLen)),
        'timestampMicros': frame.timestampMicros,
        'durationMicros': frame.durationMicros,
        'sourceWidth': frame.sourceWidth,
        'sourceHeight': frame.sourceHeight,
        'toneMapped': frame.reservedFlags & _toneMappedFlag != 0,
      };
    } finally {
      freeResult(result);
    }
  } finally {
    calloc.free(inputUri);
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

/// A frame export session living in its own isolate: the native session is a
/// plain C handle that must be used by one thread at a time, and every call
/// blocks, so the isolate owns it and Dart calls queue behind each other.
final class NativeFrameExportSession {
  NativeFrameExportSession._(this._isolate, this._commands);

  final Isolate _isolate;
  final SendPort _commands;
  bool _closed = false;

  /// Opens the media in a new isolate. Throws what opening it failed with.
  static Future<NativeFrameExportSession> open(
    Map<String, Object?> arguments,
  ) async {
    final handshake = ReceivePort();
    final isolate = await Isolate.spawn<SendPort>(
      _frameSessionMain,
      handshake.sendPort,
      debugName: 'erika-frame-export',
    );
    final commands = await handshake.first as SendPort;
    handshake.close();
    final session = NativeFrameExportSession._(isolate, commands);
    try {
      await session._request('open', arguments);
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
    return session;
  }

  Future<Map<String, Object?>> frame(Map<String, Object?> arguments) async {
    if (_closed) {
      throw StateError('The frame export session is closed.');
    }
    final reply = await _request('frame', arguments);
    final bytes = reply['bytes'];
    return <String, Object?>{
      ...reply,
      if (bytes is TransferableTypedData)
        'bytes': bytes.materialize().asUint8List(),
    };
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _request('close', const <String, Object?>{});
    } finally {
      _isolate.kill(priority: Isolate.immediate);
    }
  }

  Future<Map<String, Object?>> _request(
    String operation,
    Map<String, Object?> arguments,
  ) async {
    final port = ReceivePort();
    _commands.send(<Object?>[port.sendPort, operation, arguments]);
    final reply = await port.first as List<Object?>;
    port.close();
    if (reply[0] == 'ok') {
      return Map<String, Object?>.from(reply[1]! as Map);
    }
    final message = reply[2] as String;
    throw reply[1] == 'unsupported' ? UnsupportedError(message) : StateError(message);
  }
}

void _frameSessionMain(SendPort handshake) {
  final commands = ReceivePort();
  handshake.send(commands.sendPort);
  final worker = _FrameSessionWorker();
  commands.listen((Object? message) {
    final request = message! as List<Object?>;
    final reply = request[0]! as SendPort;
    final operation = request[1]! as String;
    final arguments = request[2]! as Map<String, Object?>;
    try {
      final Map<String, Object?> value;
      switch (operation) {
        case 'open':
          worker.open(arguments);
          value = const <String, Object?>{};
        case 'frame':
          value = worker.frame(arguments);
        default:
          worker.close();
          value = const <String, Object?>{};
      }
      reply.send(<Object?>['ok', value]);
    } on UnsupportedError catch (error) {
      reply.send(<Object?>['error', 'unsupported', error.message ?? '']);
    } catch (error) {
      reply.send(<Object?>[
        'error',
        'state',
        error is StateError ? error.message : '$error',
      ]);
    }
    if (operation == 'close') {
      commands.close();
    }
  });
}

final class _FrameSessionWorker {
  late final DynamicLibrary _library;
  late final _SessionFrameDart _frame;
  late final _SessionCloseDart _close;
  late final _FrameResultFreeDart _freeResult;
  late final _LastErrorDart _lastError;
  late final _StringFreeDart _stringFree;
  Pointer<Void> _session = nullptr;
  Pointer<_ErikaFrameExportRequest> _request = nullptr;
  Pointer<_ErikaFrameExportResult> _result = nullptr;

  void open(Map<String, Object?> arguments) {
    _library = _openErikaLibrary();
    final _SessionOpenDart open;
    try {
      open = _library.lookupFunction<_SessionOpenNative, _SessionOpenDart>(
        'erika_frame_export_session_open',
      );
      _frame = _library.lookupFunction<_SessionFrameNative, _SessionFrameDart>(
        'erika_frame_export_session_frame',
      );
      _close = _library.lookupFunction<_SessionCloseNative, _SessionCloseDart>(
        'erika_frame_export_session_close',
      );
      _freeResult =
          _library.lookupFunction<_FrameResultFreeNative, _FrameResultFreeDart>(
        'erika_frame_export_result_free',
      );
    } on ArgumentError {
      throw UnsupportedError(
        'The bundled liberika native library has no frame export session.',
      );
    }
    _lastError = _library.lookupFunction<_LastErrorNative, _LastErrorDart>(
      'erika_last_error_message',
    );
    _stringFree = _library.lookupFunction<_StringFreeNative, _StringFreeDart>(
      'erika_string_free',
    );

    final inputUri = (arguments['uri'] as String).toNativeUtf8();
    final headerMap = Map<String, String>.from(
      arguments['httpHeaders'] as Map? ?? const <String, String>{},
    );
    final headers = headerMap.isEmpty
        ? nullptr.cast<_ErikaHttpHeader>()
        : calloc<_ErikaHttpHeader>(headerMap.length);
    final headerStrings = <Pointer<Utf8>>[];
    final options = calloc<_ErikaFrameExportSessionOptions>();
    final out = calloc<Pointer<Void>>();
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
        ..headers = headers
        ..headerCount = headerMap.length
        ..httpReadAheadBytes = arguments['httpReadAheadBytes'] as int? ?? 0;
      final status = open(options, out);
      if (status != 0) {
        throw StateError('Frame export failed: ${_message(status)}');
      }
      _session = out.value;
      _request = calloc<_ErikaFrameExportRequest>();
      _result = calloc<_ErikaFrameExportResult>();
    } finally {
      calloc.free(inputUri);
      for (final value in headerStrings) {
        calloc.free(value);
      }
      if (headers != nullptr) {
        calloc.free(headers);
      }
      calloc.free(options);
      calloc.free(out);
    }
  }

  Map<String, Object?> frame(Map<String, Object?> arguments) {
    if (_session == nullptr) {
      throw StateError('The frame export session is closed.');
    }
    _request.ref
      ..positionMillis = arguments['positionMillis'] as int
      ..maxWidth = arguments['width'] as int? ?? 0
      ..maxHeight = arguments['height'] as int? ?? 0
      ..format = arguments['format'] as int? ?? 1;
    final status = _frame(_session, _request, _result);
    if (status != 0) {
      throw StateError('Frame export failed: ${_message(status)}');
    }
    try {
      final frame = _result.ref;
      return <String, Object?>{
        'width': frame.width,
        'height': frame.height,
        'format': frame.format,
        'bytes': TransferableTypedData.fromList(<Uint8List>[
          frame.data.asTypedList(frame.dataLen),
        ]),
        'timestampMicros': frame.timestampMicros,
        'durationMicros': frame.durationMicros,
        'sourceWidth': frame.sourceWidth,
        'sourceHeight': frame.sourceHeight,
        'toneMapped': frame.reservedFlags & _toneMappedFlag != 0,
      };
    } finally {
      _freeResult(_result);
    }
  }

  void close() {
    if (_session != nullptr) {
      _close(_session);
      _session = nullptr;
      calloc.free(_request);
      calloc.free(_result);
    }
  }

  String _message(int status) {
    final pointer = _lastError();
    if (pointer == nullptr) {
      return 'ErikaStatus $status';
    }
    final message = pointer.toDartString();
    _stringFree(pointer);
    return message;
  }
}

/// Names a liberika library to use for the headless exports instead of the
/// one the platform bundles, for running them against a build under test.
const String erikaLibraryEnvironmentVariable = 'ERIKA_FLUTTER_LIBRARY';

DynamicLibrary _openErikaLibrary() {
  final override = Platform.environment[erikaLibraryEnvironmentVariable];
  if (override != null && override.isNotEmpty) {
    return DynamicLibrary.open(override);
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('erika_capi.dll');
  }
  if (Platform.isAndroid || Platform.isLinux || Platform.operatingSystem == 'ohos') {
    return DynamicLibrary.open('liberika_capi.so');
  }
  throw UnsupportedError(
    'Erika headless export is not available on ${Platform.operatingSystem}.',
  );
}
