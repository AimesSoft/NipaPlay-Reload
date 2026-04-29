import 'dart:io';

import 'package:nipaplay/themes/nipaplay/widgets/large_screen_network_status.dart';

Future<LargeScreenNetworkKind> detectLargeScreenNetworkKind() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: true,
      type: InternetAddressType.any,
    );

    for (final interface in interfaces) {
      final name = interface.name.toLowerCase();
      if (name.contains('wlan') ||
          name.contains('wifi') ||
          name.contains('wi-fi') ||
          name.contains('en0')) {
        return LargeScreenNetworkKind.wifi;
      }
    }

    for (final interface in interfaces) {
      if (interface.addresses.isNotEmpty) {
        return LargeScreenNetworkKind.cellular;
      }
    }
  } catch (_) {
    return LargeScreenNetworkKind.unavailable;
  }

  return LargeScreenNetworkKind.unavailable;
}
