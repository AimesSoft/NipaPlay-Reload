import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart';

@visibleForTesting
bool procMapsUsesNvidiaGraphicsStack(String procMaps) {
  final lower = procMaps.toLowerCase();
  return lower.contains('libnvidia-eglcore') ||
      lower.contains('libegl_nvidia') ||
      lower.contains('libglx_nvidia');
}

@visibleForTesting
bool environmentRequestsNvidiaGraphicsStack(Map<String, String> environment) {
  final glxVendor = environment['__GLX_VENDOR_LIBRARY_NAME']?.toLowerCase();
  return glxVendor == 'nvidia' ||
      environment['__NV_PRIME_RENDER_OFFLOAD'] == '1';
}

/// Returns true only when this process appears to be using NVIDIA's GL/EGL
/// stack, rather than merely observing that the NVIDIA kernel module is loaded.
/// This avoids selecting CUDA for an Intel/AMD-rendered process on hybrid GPUs.
bool isLinuxNvidiaGraphicsStackActive() {
  if (kIsWeb || !Platform.isLinux) return false;
  try {
    final maps = File('/proc/self/maps');
    if (maps.existsSync() &&
        procMapsUsesNvidiaGraphicsStack(maps.readAsStringSync())) {
      return true;
    }

    if (environmentRequestsNvidiaGraphicsStack(Platform.environment)) {
      return File('/proc/driver/nvidia/version').existsSync();
    }
  } catch (_) {
    return false;
  }
  return false;
}
