import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';

import 'package:nipaplay/services/smb_service.dart';

class Smb2NativeService {
  Smb2NativeService._();

  static final Smb2NativeService instance = Smb2NativeService._();

  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<List<SMBFileEntry>> listDirectory(
    SMBConnection connection,
    String path,
  ) async {
    final jsonString = await _worker.requestList(
      host: connection.host,
      port: connection.port,
      username: connection.username,
      password: connection.password,
      domain: connection.domain,
      path: path,
    );

    final decoded = json.decode(jsonString);
    if (decoded is! List) {
      throw StateError('Invalid SMB2 list response');
    }
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(
          (e) => SMBFileEntry(
            name: (e['name'] ?? '').toString(),
            path: (e['path'] ?? '').toString(),
            isDirectory: e['isDirectory'] == true,
            size: e['size'] is int
                ? e['size'] as int
                : int.tryParse(e['size']?.toString() ?? ''),
            isShare: e['isShare'] == true,
          ),
        )
        .toList();
  }

  Future<Smb2Stat> stat(
    SMBConnection connection,
    String path,
  ) async {
    final result = await _worker.requestStat(
      host: connection.host,
      port: connection.port,
      username: connection.username,
      password: connection.password,
      domain: connection.domain,
      path: path,
    );
    return Smb2Stat(
      type: result.type,
      size: result.size,
    );
  }

  Stream<Uint8List> openReadStream(
    SMBConnection connection,
    String path, {
    required int start,
    required int endExclusive,
    int chunkSize = 256 * 1024,
  }) {
    return _Smb2StreamReader.stream(
      host: connection.host,
      port: connection.port,
      username: connection.username,
      password: connection.password,
      domain: connection.domain,
      path: path,
      start: start,
      endExclusive: endExclusive,
      chunkSize: chunkSize,
    );
  }

  final _Smb2Worker _worker = _Smb2Worker();
}

class Smb2Stat {
  final int type;
  final int size;

  const Smb2Stat({
    required this.type,
    required this.size,
  });

  bool get isDirectory => type == 1;
}

class _Smb2Worker {
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _nextId = 1;

  Future<void> _ensureStarted() async {
    if (_sendPort != null) return;

    final completer = Completer<SendPort>();
    _receivePort.listen((message) {
      if (message is SendPort && !completer.isCompleted) {
        completer.complete(message);
        return;
      }
      if (message is Map) {
        final id = message['id'];
        if (id is! int) return;
        final pending = _pending.remove(id);
        if (pending == null) return;
        if (message['ok'] == true) {
          pending.complete(message['result']);
        } else {
          pending.completeError(message['error'] ?? 'SMB2 worker error');
        }
      }
    });

    await Isolate.spawn(_smb2WorkerMain, _receivePort.sendPort);
    _sendPort = await completer.future;
  }

  Future<String> requestList({
    required String host,
    required int port,
    required String username,
    required String password,
    required String domain,
    required String path,
  }) async {
    await _ensureStarted();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _sendPort!.send({
      'id': id,
      'op': 'list',
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'domain': domain,
      'path': path,
    });
    final result = await completer.future;
    if (result is! String) {
      throw StateError('Invalid SMB2 list result');
    }
    return result;
  }

  Future<({int type, int size})> requestStat({
    required String host,
    required int port,
    required String username,
    required String password,
    required String domain,
    required String path,
  }) async {
    await _ensureStarted();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _sendPort!.send({
      'id': id,
      'op': 'stat',
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'domain': domain,
      'path': path,
    });
    final result = await completer.future;
    if (result is! Map) {
      throw StateError('Invalid SMB2 stat result');
    }
    final type = result['type'];
    final size = result['size'];
    return (
      type: type is int ? type : int.tryParse(type?.toString() ?? '') ?? 0,
      size: size is int ? size : int.tryParse(size?.toString() ?? '') ?? 0,
    );
  }
}

void _smb2WorkerMain(SendPort mainPort) {
  final ReceivePort workerPort = ReceivePort();
  mainPort.send(workerPort.sendPort);

  final native = _Smb2Native();

  workerPort.listen((message) {
    if (message is! Map) return;
    final id = message['id'];
    final op = message['op'];
    if (id is! int || op is! String) return;

    try {
      if (op == 'list') {
        final result = native.listEntriesJson(
          host: (message['host'] ?? '').toString(),
          port: message['port'] is int
              ? message['port'] as int
              : int.tryParse(message['port']?.toString() ?? '') ?? 445,
          username: (message['username'] ?? '').toString(),
          password: (message['password'] ?? '').toString(),
          domain: (message['domain'] ?? '').toString(),
          path: (message['path'] ?? '').toString(),
        );
        mainPort.send({'id': id, 'ok': true, 'result': result});
        return;
      }
      if (op == 'stat') {
        final result = native.stat(
          host: (message['host'] ?? '').toString(),
          port: message['port'] is int
              ? message['port'] as int
              : int.tryParse(message['port']?.toString() ?? '') ?? 445,
          username: (message['username'] ?? '').toString(),
          password: (message['password'] ?? '').toString(),
          domain: (message['domain'] ?? '').toString(),
          path: (message['path'] ?? '').toString(),
        );
        mainPort.send({
          'id': id,
          'ok': true,
          'result': {'type': result.type, 'size': result.size},
        });
        return;
      }

      mainPort.send({
        'id': id,
        'ok': false,
        'error': 'Unknown SMB2 op: $op',
      });
    } catch (e) {
      mainPort.send({
        'id': id,
        'ok': false,
        'error': e.toString(),
      });
    }
  });
}

class _Smb2Native {
  _Smb2Native() : _dylib = _openDynamicLibrary() {
    _free = _dylib.lookupFunction<_np_smb2_free_c, _np_smb2_free_dart>(
      'np_smb2_free',
    );
    _listEntriesJson = _dylib
        .lookupFunction<_np_smb2_list_entries_c, _np_smb2_list_entries_dart>(
      'np_smb2_list_entries_json',
    );
    _stat = _dylib.lookupFunction<_np_smb2_stat_c, _np_smb2_stat_dart>(
      'np_smb2_stat',
    );
    _readerOpen =
        _dylib.lookupFunction<_np_smb2_reader_open_c, _np_smb2_reader_open_dart>(
      'np_smb2_reader_open',
    );
    _readerPread = _dylib
        .lookupFunction<_np_smb2_reader_pread_c, _np_smb2_reader_pread_dart>(
      'np_smb2_reader_pread',
    );
    _readerClose = _dylib
        .lookupFunction<_np_smb2_reader_close_c, _np_smb2_reader_close_dart>(
      'np_smb2_reader_close',
    );
  }

  final DynamicLibrary _dylib;

  late final _np_smb2_free_dart _free;
  late final _np_smb2_list_entries_dart _listEntriesJson;
  late final _np_smb2_stat_dart _stat;
  late final _np_smb2_reader_open_dart _readerOpen;
  late final _np_smb2_reader_pread_dart _readerPread;
  late final _np_smb2_reader_close_dart _readerClose;

  String listEntriesJson({
    required String host,
    required int port,
    required String username,
    required String password,
    required String domain,
    required String path,
  }) {
    final errBuf = calloc<Uint8>(1024);
    try {
      final resultPtr = _withUtf8(
        host,
        (hostPtr) => _withUtf8(
          username,
          (userPtr) => _withUtf8(
            password,
            (passPtr) => _withUtf8(
              domain,
              (domainPtr) => _withUtf8(
                path,
                (pathPtr) => _listEntriesJson(
                  hostPtr,
                  port,
                  userPtr,
                  passPtr,
                  domainPtr,
                  pathPtr,
                  errBuf,
                  1024,
                ),
              ),
            ),
          ),
        ),
      );

      if (resultPtr == nullptr) {
        throw StateError(_readErr(errBuf));
      }
      final jsonString = resultPtr.toDartString();
      _free(resultPtr.cast());
      return jsonString;
    } finally {
      calloc.free(errBuf);
    }
  }

  ({int type, int size}) stat({
    required String host,
    required int port,
    required String username,
    required String password,
    required String domain,
    required String path,
  }) {
    final errBuf = calloc<Uint8>(1024);
    final outType = calloc<Uint32>();
    final outSize = calloc<Uint64>();
    try {
      final rc = _withUtf8(
        host,
        (hostPtr) => _withUtf8(
          username,
          (userPtr) => _withUtf8(
            password,
            (passPtr) => _withUtf8(
              domain,
              (domainPtr) => _withUtf8(
                path,
                (pathPtr) => _stat(
                  hostPtr,
                  port,
                  userPtr,
                  passPtr,
                  domainPtr,
                  pathPtr,
                  outType,
                  outSize,
                  errBuf,
                  1024,
                ),
              ),
            ),
          ),
        ),
      );
      if (rc != 0) {
        throw StateError(_readErr(errBuf));
      }
      return (type: outType.value, size: outSize.value);
    } finally {
      calloc.free(outType);
      calloc.free(outSize);
      calloc.free(errBuf);
    }
  }

  ({int handle, int size}) openReader({
    required String host,
    required int port,
    required String username,
    required String password,
    required String domain,
    required String path,
  }) {
    final errBuf = calloc<Uint8>(1024);
    final outSize = calloc<Uint64>();
    try {
      final handle = _withUtf8(
        host,
        (hostPtr) => _withUtf8(
          username,
          (userPtr) => _withUtf8(
            password,
            (passPtr) => _withUtf8(
              domain,
              (domainPtr) => _withUtf8(
                path,
                (pathPtr) => _readerOpen(
                  hostPtr,
                  port,
                  userPtr,
                  passPtr,
                  domainPtr,
                  pathPtr,
                  outSize,
                  errBuf,
                  1024,
                ),
              ),
            ),
          ),
        ),
      );
      if (handle == 0) {
        throw StateError(_readErr(errBuf));
      }
      return (handle: handle, size: outSize.value);
    } finally {
      calloc.free(outSize);
      calloc.free(errBuf);
    }
  }

  int pread({
    required int readerHandle,
    required int offset,
    required Pointer<Uint8> buffer,
    required int count,
  }) {
    final errBuf = calloc<Uint8>(1024);
    try {
      final rc = _readerPread(
        readerHandle,
        offset,
        buffer,
        count,
        errBuf,
        1024,
      );
      if (rc < 0) {
        throw StateError(_readErr(errBuf));
      }
      return rc;
    } finally {
      calloc.free(errBuf);
    }
  }

  void closeReader(int readerHandle) {
    _readerClose(readerHandle);
  }
}

DynamicLibrary _openDynamicLibrary() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    return DynamicLibrary.open('nipaplay_smb2.framework/nipaplay_smb2');
  }
  throw UnsupportedError('libsmb2 is only wired on macOS for now.');
}

T _withUtf8<T>(String value, T Function(Pointer<Utf8>) fn) {
  final ptr = value.toNativeUtf8();
  try {
    return fn(ptr);
  } finally {
    calloc.free(ptr);
  }
}

String _readErr(Pointer<Uint8> errBuf) {
  final bytes = errBuf.asTypedList(1024);
  final end = bytes.indexOf(0);
  final slice = end == -1 ? bytes : bytes.sublist(0, end);
  final text = utf8.decode(slice, allowMalformed: true).trim();
  return text.isEmpty ? 'SMB2 native call failed' : text;
}

typedef _np_smb2_free_c = Void Function(Pointer<Void>);
typedef _np_smb2_free_dart = void Function(Pointer<Void>);

typedef _np_smb2_list_entries_c = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint8>,
  Int32,
);
typedef _np_smb2_list_entries_dart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint8>,
  int,
);

typedef _np_smb2_stat_c = Int32 Function(
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint32>,
  Pointer<Uint64>,
  Pointer<Uint8>,
  Int32,
);
typedef _np_smb2_stat_dart = int Function(
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint32>,
  Pointer<Uint64>,
  Pointer<Uint8>,
  int,
);

typedef _np_smb2_reader_open_c = IntPtr Function(
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint64>,
  Pointer<Uint8>,
  Int32,
);
typedef _np_smb2_reader_open_dart = int Function(
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint64>,
  Pointer<Uint8>,
  int,
);

typedef _np_smb2_reader_pread_c = Int32 Function(
  IntPtr,
  Uint64,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint8>,
  Int32,
);
typedef _np_smb2_reader_pread_dart = int Function(
  int,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
);

typedef _np_smb2_reader_close_c = Void Function(IntPtr);
typedef _np_smb2_reader_close_dart = void Function(int);

class _Smb2StreamReader {
  static Stream<Uint8List> stream({
    required String host,
    required int port,
    required String username,
    required String password,
    required String domain,
    required String path,
    required int start,
    required int endExclusive,
    required int chunkSize,
  }) {
    final controller = StreamController<Uint8List>();

    Isolate? isolate;
    ReceivePort? receivePort;

    Future<void> startIsolate() async {
      receivePort = ReceivePort();
      isolate = await Isolate.spawn<_Smb2StreamArgs>(
        _smb2StreamIsolateMain,
        _Smb2StreamArgs(
          sendPort: receivePort!.sendPort,
          host: host,
          port: port,
          username: username,
          password: password,
          domain: domain,
          path: path,
          start: start,
          endExclusive: endExclusive,
          chunkSize: chunkSize,
        ),
        errorsAreFatal: true,
      );

      receivePort!.listen((message) {
        if (message is Uint8List) {
          controller.add(message);
          return;
        }
        if (message is Map && message['type'] == 'error') {
          controller.addError(message['error'] ?? 'SMB2 stream error');
          controller.close();
          isolate?.kill(priority: Isolate.immediate);
          receivePort?.close();
          return;
        }
        if (message is Map && message['type'] == 'done') {
          controller.close();
          isolate?.kill(priority: Isolate.immediate);
          receivePort?.close();
          return;
        }
      });
    }

    controller.onListen = () {
      startIsolate();
    };
    controller.onCancel = () async {
      isolate?.kill(priority: Isolate.immediate);
      receivePort?.close();
    };

    return controller.stream;
  }
}

class _Smb2StreamArgs {
  final SendPort sendPort;
  final String host;
  final int port;
  final String username;
  final String password;
  final String domain;
  final String path;
  final int start;
  final int endExclusive;
  final int chunkSize;

  const _Smb2StreamArgs({
    required this.sendPort,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.domain,
    required this.path,
    required this.start,
    required this.endExclusive,
    required this.chunkSize,
  });
}

void _smb2StreamIsolateMain(_Smb2StreamArgs args) {
  final native = _Smb2Native();
  int readerHandle = 0;
  Pointer<Uint8>? buffer;
  try {
    final opened = native.openReader(
      host: args.host,
      port: args.port,
      username: args.username,
      password: args.password,
      domain: args.domain,
      path: args.path,
    );
    readerHandle = opened.handle;

    final total = args.endExclusive - args.start;
    if (total <= 0) {
      args.sendPort.send({'type': 'done'});
      native.closeReader(readerHandle);
      return;
    }

    final maxChunk = args.chunkSize <= 0 ? 256 * 1024 : args.chunkSize;
    buffer = malloc<Uint8>(maxChunk);

    int offset = args.start;
    while (offset < args.endExclusive) {
      final remaining = args.endExclusive - offset;
      final toRead = remaining < maxChunk ? remaining : maxChunk;
      final read = native.pread(
        readerHandle: readerHandle,
        offset: offset,
        buffer: buffer,
        count: toRead,
      );
      if (read <= 0) {
        break;
      }
      final chunk = Uint8List.fromList(buffer.asTypedList(read));
      args.sendPort.send(chunk);
      offset += read;
    }

    native.closeReader(readerHandle);
    args.sendPort.send({'type': 'done'});
  } catch (e) {
    if (readerHandle != 0) {
      try {
        native.closeReader(readerHandle);
      } catch (_) {}
    }
    args.sendPort.send({'type': 'error', 'error': e.toString()});
  } finally {
    if (buffer != null) {
      malloc.free(buffer);
    }
  }
}
