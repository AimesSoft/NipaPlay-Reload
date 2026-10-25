import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Free and total bytes of the volume holding [path] (kernel32
/// GetDiskFreeSpaceExW; the free count is what the current user may use).
({int available, int total})? windowsDiskSpace(String path) {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final query = kernel.lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint64>),
      int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint64>)>('GetDiskFreeSpaceExW');
  final native = path.toNativeUtf16();
  final counts = calloc<Uint64>(3);
  try {
    if (query(native, counts, counts + 1, counts + 2) == 0) return null;
    return (available: counts[0], total: counts[1]);
  } finally {
    calloc.free(counts);
    malloc.free(native);
  }
}
