import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:nipaplay/plugins/js_runtime_types.dart';

typedef _BridgeNative = Pointer<Utf8> Function(
    IntPtr, Pointer<Utf8>, Pointer<Utf8>);

typedef _CreateNative = Pointer<Void> Function(
    Pointer<NativeFunction<_BridgeNative>>, IntPtr);
typedef _CreateDart = Pointer<Void> Function(
    Pointer<NativeFunction<_BridgeNative>>, int);
typedef _EvaluateNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  IntPtr,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);
typedef _EvaluateDart = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
  Pointer<Pointer<Utf8>>,
  Pointer<Pointer<Utf8>>,
);

final Map<int, HarmonyQuickJsRuntimeAdapter> _runtimeById = {};
int _nextRuntimeId = 1;

@pragma('vm:entry-point')
Pointer<Utf8> _dispatchBridge(
  int runtimeId,
  Pointer<Utf8> channel,
  Pointer<Utf8> encodedArgs,
) {
  final runtime = _runtimeById[runtimeId];
  if (runtime == null) {
    return 'null'.toNativeUtf8();
  }
  return runtime._handleBridge(
    channel.toDartString(),
    encodedArgs.toDartString(),
  );
}

/// QuickJS runtime backed by the arm64 HarmonyOS library built with the entry
/// module. The bridge intentionally exposes only the synchronous API used by
/// NipaPlay plugins.
class HarmonyQuickJsRuntimeAdapter implements PluginJsRuntime {
  HarmonyQuickJsRuntimeAdapter() : _runtimeId = _nextRuntimeId++ {
    _runtimeById[_runtimeId] = this;
    _handle = _bindings.create(_bridgePointer, _runtimeId);
    if (_handle == nullptr) {
      _runtimeById.remove(_runtimeId);
      throw StateError('Unable to create HarmonyOS QuickJS runtime');
    }
  }

  static final _QuickJsBindings _bindings = _QuickJsBindings.open();
  static final Pointer<NativeFunction<_BridgeNative>> _bridgePointer =
      Pointer.fromFunction<_BridgeNative>(_dispatchBridge);

  final int _runtimeId;
  final Map<String, dynamic Function(dynamic args)> _bridges = {};
  late Pointer<Void> _handle;
  bool _disposed = false;

  Pointer<Utf8> _handleBridge(String channel, String encodedArgs) {
    try {
      final callback = _bridges[channel];
      final value = callback == null ? null : callback(jsonDecode(encodedArgs));
      return jsonEncode(value).toNativeUtf8();
    } catch (_) {
      return 'null'.toNativeUtf8();
    }
  }

  @override
  String evaluate(String code) {
    if (_disposed) {
      throw StateError('QuickJS runtime has been disposed');
    }

    final input = code.toNativeUtf8();
    final result = calloc<Pointer<Utf8>>();
    final error = calloc<Pointer<Utf8>>();
    try {
      final status = _bindings.evaluate(
        _handle,
        input,
        input.length,
        result,
        error,
      );
      if (status != 0) {
        final message = error.value == nullptr
            ? 'Unknown QuickJS evaluation error'
            : error.value.toDartString();
        throw StateError(message);
      }
      return result.value == nullptr ? 'null' : result.value.toDartString();
    } finally {
      if (result.value != nullptr) {
        _bindings.freeString(result.value);
      }
      if (error.value != nullptr) {
        _bindings.freeString(error.value);
      }
      malloc.free(input);
      calloc
        ..free(result)
        ..free(error);
    }
  }

  @override
  void setupBridge(String channelName, dynamic Function(dynamic args) fn) {
    if (_disposed) {
      throw StateError('QuickJS runtime has been disposed');
    }
    _bridges[channelName] = fn;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _runtimeById.remove(_runtimeId);
    _bindings.dispose(_handle);
    _handle = nullptr;
    _bridges.clear();
  }
}

class _QuickJsBindings {
  _QuickJsBindings(this.library)
      : create = library.lookupFunction<_CreateNative, _CreateDart>(
          'np_qjs_create',
        ),
        evaluate = library.lookupFunction<_EvaluateNative, _EvaluateDart>(
          'np_qjs_evaluate',
        ),
        dispose = library
            .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
              'np_qjs_dispose',
            )
            .asFunction(),
        freeString = library
            .lookup<NativeFunction<Void Function(Pointer<Utf8>)>>(
              'np_qjs_free_string',
            )
            .asFunction();

  factory _QuickJsBindings.open() {
    final override = Platform.environment['NIPAPLAY_QUICKJS_LIBRARY'];
    if (override != null && override.isNotEmpty) {
      return _QuickJsBindings(DynamicLibrary.open(override));
    }
    return _QuickJsBindings(
      DynamicLibrary.open('libquickjs_c_bridge_plugin.so'),
    );
  }

  final DynamicLibrary library;
  final _CreateDart create;
  final _EvaluateDart evaluate;
  final void Function(Pointer<Void>) dispose;
  final void Function(Pointer<Utf8>) freeString;
}
