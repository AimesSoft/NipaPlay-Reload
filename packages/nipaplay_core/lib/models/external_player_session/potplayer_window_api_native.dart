import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _EnumWindowsProcNative = Int32 Function(IntPtr, IntPtr);
typedef _EnumWindowsNative = Int32 Function(
    Pointer<NativeFunction<_EnumWindowsProcNative>>, IntPtr);
typedef _EnumWindowsDart = int Function(
    Pointer<NativeFunction<_EnumWindowsProcNative>>, int);
typedef _GetWindowThreadProcessIdNative = Uint32 Function(
    IntPtr, Pointer<Uint32>);
typedef _GetWindowThreadProcessIdDart = int Function(int, Pointer<Uint32>);
typedef _SendMessageNative = IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr);
typedef _SendMessageDart = int Function(int, int, int, int);
typedef _PostMessageNative = Int32 Function(IntPtr, Uint32, IntPtr, IntPtr);
typedef _PostMessageDart = int Function(int, int, int, int);
typedef _IsWindowNative = Int32 Function(IntPtr);
typedef _IsWindowDart = int Function(int);
typedef _IsWindowVisibleNative = Int32 Function(IntPtr);
typedef _IsWindowVisibleDart = int Function(int);
typedef _GetClassNameNative = Int32 Function(IntPtr, Pointer<Uint16>, Int32);
typedef _GetClassNameDart = int Function(int, Pointer<Uint16>, int);
typedef _GetForegroundWindowNative = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();
typedef _SetForegroundWindowNative = Int32 Function(IntPtr);
typedef _SetForegroundWindowDart = int Function(int);
typedef _KeybdEventNative = Void Function(Uint8, Uint8, Uint32, IntPtr);
typedef _KeybdEventDart = void Function(int, int, int, int);

int _enumWindowForProcess(int windowHandle, int targetProcessId) {
  final processId = calloc<Uint32>();
  try {
    WindowsPotPlayerApi.instance._getWindowThreadProcessId(
      windowHandle,
      processId,
    );
    if (processId.value == targetProcessId &&
        WindowsPotPlayerApi.instance._isWindowVisible(windowHandle) != 0 &&
        WindowsPotPlayerApi.instance.isPotPlayerMainWindow(windowHandle)) {
      WindowsPotPlayerApi.enumeratedWindowHandle = windowHandle;
      return 0;
    }
    return 1;
  } finally {
    calloc.free(processId);
  }
}

class WindowsPotPlayerApi {
  WindowsPotPlayerApi._() {
    final user32 = DynamicLibrary.open('user32.dll');
    _enumWindows = user32.lookupFunction<_EnumWindowsNative, _EnumWindowsDart>(
      'EnumWindows',
    );
    _getWindowThreadProcessId = user32.lookupFunction<
        _GetWindowThreadProcessIdNative,
        _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');
    sendMessage = user32.lookupFunction<_SendMessageNative, _SendMessageDart>(
      'SendMessageW',
    );
    postMessage = user32.lookupFunction<_PostMessageNative, _PostMessageDart>(
      'PostMessageW',
    );
    isWindow = user32.lookupFunction<_IsWindowNative, _IsWindowDart>(
      'IsWindow',
    );
    _isWindowVisible =
        user32.lookupFunction<_IsWindowVisibleNative, _IsWindowVisibleDart>(
      'IsWindowVisible',
    );
    _getClassName =
        user32.lookupFunction<_GetClassNameNative, _GetClassNameDart>(
      'GetClassNameW',
    );
    getForegroundWindow = user32
        .lookupFunction<_GetForegroundWindowNative, _GetForegroundWindowDart>(
      'GetForegroundWindow',
    );
    setForegroundWindow = user32
        .lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>(
      'SetForegroundWindow',
    );
    _keybdEvent = user32.lookupFunction<_KeybdEventNative, _KeybdEventDart>(
      'keybd_event',
    );
  }

  static final WindowsPotPlayerApi instance = WindowsPotPlayerApi._();
  static int enumeratedWindowHandle = 0;
  static final Pointer<NativeFunction<_EnumWindowsProcNative>> _enumCallback =
      Pointer.fromFunction<_EnumWindowsProcNative>(_enumWindowForProcess, 0);

  late final _EnumWindowsDart _enumWindows;
  late final _GetWindowThreadProcessIdDart _getWindowThreadProcessId;
  late final int Function(int, int, int, int) sendMessage;
  late final int Function(int, int, int, int) postMessage;
  late final int Function(int) isWindow;
  late final _IsWindowVisibleDart _isWindowVisible;
  late final _GetClassNameDart _getClassName;
  late final int Function() getForegroundWindow;
  late final int Function(int) setForegroundWindow;
  late final _KeybdEventDart _keybdEvent;

  static const int _vkControl = 0x11;
  static const int _vkMenu = 0x12;
  static const int _vkL = 0x4C;
  static const int _keyEventKeyUp = 0x0002;

  void sendCtrlAltL() {
    _keybdEvent(_vkControl, 0, 0, 0);
    _keybdEvent(_vkMenu, 0, 0, 0);
    _keybdEvent(_vkL, 0, 0, 0);
    _keybdEvent(_vkL, 0, _keyEventKeyUp, 0);
    _keybdEvent(_vkMenu, 0, _keyEventKeyUp, 0);
    _keybdEvent(_vkControl, 0, _keyEventKeyUp, 0);
  }

  bool isPotPlayerMainWindow(int windowHandle) {
    final buffer = calloc<Uint16>(256);
    try {
      final length = _getClassName(windowHandle, buffer, 256);
      if (length <= 0) return false;
      final className =
          buffer.cast<Utf16>().toDartString(length: length).toLowerCase();
      return className == 'potplayer' ||
          className == 'potplayer32' ||
          className == 'potplayer64';
    } finally {
      calloc.free(buffer);
    }
  }

  int findWindowForProcess(int processId) {
    enumeratedWindowHandle = 0;
    _enumWindows(_enumCallback, processId);
    return enumeratedWindowHandle;
  }
}
