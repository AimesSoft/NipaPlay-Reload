import 'package:nipaplay/themes/nipaplay/widgets/large_screen_network_status_stub.dart'
    if (dart.library.io)
        'package:nipaplay/themes/nipaplay/widgets/large_screen_network_status_io.dart'
    as impl;

enum LargeScreenNetworkKind {
  unavailable,
  wifi,
  cellular,
}

Future<LargeScreenNetworkKind> detectLargeScreenNetworkKind() {
  return impl.detectLargeScreenNetworkKind();
}
