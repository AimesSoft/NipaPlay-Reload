import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/linux_nvidia_gpu.dart';

void main() {
  test('detects NVIDIA only from process graphics libraries', () {
    expect(
      procMapsUsesNvidiaGraphicsStack(
        '7f00-7f01 r-xp /usr/lib/libnvidia-eglcore.so.595.71.05',
      ),
      isTrue,
    );
    expect(
      procMapsUsesNvidiaGraphicsStack(
        '7f00-7f01 r-xp /usr/lib/x86_64-linux-gnu/libEGL_mesa.so.0',
      ),
      isFalse,
    );
  });

  test('recognizes explicit PRIME and GLX NVIDIA selection', () {
    expect(
      environmentRequestsNvidiaGraphicsStack({
        '__NV_PRIME_RENDER_OFFLOAD': '1',
      }),
      isTrue,
    );
    expect(
      environmentRequestsNvidiaGraphicsStack({
        '__GLX_VENDOR_LIBRARY_NAME': 'nvidia',
      }),
      isTrue,
    );
    expect(environmentRequestsNvidiaGraphicsStack(const {}), isFalse);
  });
}
