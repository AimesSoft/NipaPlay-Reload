import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Shows the lab window named [title] without taking the foreground (Windows
/// only; the other platforms do it natively): found by its title, shown
/// without activation and put at the bottom of the stack.
void showWindowWithoutActivating(String title) {
  final user32 = DynamicLibrary.open('user32.dll');
  final find = user32.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
  final show = user32.lookupFunction<Int32 Function(IntPtr, Int32),
      int Function(int, int)>('ShowWindow');
  final position = user32.lookupFunction<
      Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
      int Function(int, int, int, int, int, int, int)>('SetWindowPos');
  final native = title.toNativeUtf16();
  try {
    final window = find(nullptr, native);
    if (window == 0) throw StateError('The lab window was not found.');
    show(window, 4); // SW_SHOWNOACTIVATE
    // HWND_BOTTOM; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
    position(window, 1, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
  } finally {
    malloc.free(native);
  }
}
