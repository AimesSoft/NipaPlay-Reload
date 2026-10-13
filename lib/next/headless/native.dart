import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:nipa_harness/nipa_harness.dart';

/// Each blocking native call runs off the endpoint isolate. The library owns
/// the shared Rust runtimes; mesh_next may wait while other calls respond.
final class HeadlessNative {
  HeadlessNative(this.library);
  final String library;
  Future<Object?> call(String operation, [JsonMap input = const {}]) {
    final path = library;
    final request = jsonEncode({'operation': operation, ...input});
    return Isolate.run(() {
      final lib = DynamicLibrary.open(path);
      final call = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('nipaplay_headless_call');
      final free = lib.lookupFunction<Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('nipaplay_headless_free');
      final data = request.toNativeUtf8();
      Pointer<Utf8>? output;
      try {
        output = call(data);
        final envelope = jsonDecode(output.toDartString()) as JsonMap;
        if (envelope.containsKey('error')) {
          throw Failure(FailureCode.unavailable, envelope['error'] as String);
        }
        return envelope['result'];
      } finally {
        calloc.free(data);
        if (output != null) free(output);
      }
    });
  }
  static String defaultLibrary() {
    final filename = Platform.isWindows ? 'nipaplay_headless_native.dll'
        : Platform.isMacOS ? 'libnipaplay_headless_native.dylib'
        : 'libnipaplay_headless_native.so';
    return '${File(Platform.resolvedExecutable).parent.path}/$filename';
  }
}
