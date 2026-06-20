import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'bindings/native_bindings.dart';
import 'types/native_types_io.dart';

/// FFI 内存 Arena — 统一管理一次 FFI 调用中的所有 native 分配。
///
/// 使用方式：
/// ```dart
/// final arena = NativeArena();
/// try {
///   final ptr = arena.allocUtf8('hello');
///   final out = arena.allocNpString();
///   final items = calloc<NpDanmakuItem>(count);
///   arena.registerCalloc(items.cast());
///   // ... FFI 调用 ...
/// } finally {
///   arena.freeAll(); // 自动先 np_string_free，再按分配器释放
/// }
/// ```
///
/// 解决的问题：
/// 1. H2: DanmakuLayoutEngine 缓存缓冲区在 Finalizer 中未被释放
/// 2. M1: malloc/calloc 混用释放不一致 — 按分配器匹配释放
/// 3. 避免每帧 calloc/free 引起堆碎片化
class NativeArena {
  /// calloc 分配的指针（用 calloc.free 释放）
  final List<Pointer> _callocPtrs = [];

  /// malloc 分配的指针（用 malloc.free 释放，如 toNativeUtf8）
  final List<Pointer> _mallocPtrs = [];

  /// NpString 结构指针（需要先 np_string_free 再 calloc.free）
  final List<Pointer<NpString>> _npStrings = [];

  /// 注册 calloc 分配的指针到 Arena（释放时使用 calloc.free）
  ///
  /// Dart AOT 不支持泛型方法内的 calloc<T>()，
  /// 因此调用方需使用具体类型分配后注册：
  /// ```dart
  /// final ptr = calloc<NpDanmakuItem>(count);
  /// arena.registerCalloc(ptr.cast());
  /// ```
  void registerCalloc(Pointer ptr) {
    _callocPtrs.add(ptr);
  }

  /// 注册 toNativeUtf8() 返回的指针
  /// 内部使用 malloc 分配，释放时使用 malloc.free（M1 修复：匹配分配器）
  Pointer<Utf8> allocUtf8(String text) {
    final ptr = text.toNativeUtf8();
    _mallocPtrs.add(ptr.cast());
    return ptr;
  }

  /// 分配 NpString 结构指针（使用 calloc）
  /// freeAll 会先调用 np_string_free 释放内部 data，再 calloc.free 结构体
  Pointer<NpString> allocNpString() {
    final ptr = calloc<NpString>();
    _npStrings.add(ptr);
    _callocPtrs.add(ptr.cast());
    return ptr;
  }

  /// 分配 Uint8List 到 native 内存（使用 calloc）
  /// 用于传递原始字节（字幕文件等可能是任意编码，不能用 toNativeUtf8）
  /// 返回 Pointer<Uint8>，生命周期由 NativeArena 管理
  Pointer<Uint8> allocUint8List(Uint8List bytes) {
    final ptr = calloc<Uint8>(bytes.length);
    registerCalloc(ptr.cast());
    // 使用 asTypedList 避免逐字节拷贝的开销
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    return ptr;
  }

  /// 释放所有已注册的指针
  ///
  /// 1. 先对所有 NpString 调用 np_string_free（释放内部 malloc data）
  /// 2. 再对所有 malloc 分配的指针使用 malloc.free（M1 修复）
  /// 3. 最后对所有 calloc 分配的指针使用 calloc.free
  void freeAll() {
    // Step 1: 释放 NpString 内部的 data 指针（由 C 侧 malloc 分配）
    for (final npStr in _npStrings) {
      NativeBindings.npStringFree(npStr);
    }
    // Step 2: 释放 malloc 分配的指针（toNativeUtf8 等）
    for (final ptr in _mallocPtrs) {
      malloc.free(ptr);
    }
    // Step 3: 释放 calloc 分配的指针
    for (final ptr in _callocPtrs) {
      calloc.free(ptr);
    }
    _callocPtrs.clear();
    _mallocPtrs.clear();
    _npStrings.clear();
  }
}
