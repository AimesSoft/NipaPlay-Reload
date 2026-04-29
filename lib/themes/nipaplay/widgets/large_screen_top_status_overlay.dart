import 'dart:async';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_network_status.dart';

class NipaplayLargeScreenTopStatusOverlay extends StatefulWidget {
  const NipaplayLargeScreenTopStatusOverlay({super.key, required this.isDarkMode});

  final bool isDarkMode;

  @override
  State<NipaplayLargeScreenTopStatusOverlay> createState() =>
      _NipaplayLargeScreenTopStatusOverlayState();
}

class _NipaplayLargeScreenTopStatusOverlayState
    extends State<NipaplayLargeScreenTopStatusOverlay> {
  final Battery _battery = Battery();
  Timer? _timer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;

  DateTime _now = DateTime.now();
  int? _batteryLevel;
  BatteryState? _batteryState;
  LargeScreenNetworkKind _networkKind = LargeScreenNetworkKind.unavailable;
  bool _batteryAvailable = true;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _refreshAll();
    });
    _listenBatteryState();
  }

  void _listenBatteryState() {
    if (kIsWeb) {
      _batteryAvailable = false;
      return;
    }
    try {
      _batteryStateSubscription =
          _battery.onBatteryStateChanged.listen((BatteryState state) {
        if (!mounted) return;
        setState(() {
          _batteryState = state;
        });
      });
    } catch (_) {
      _batteryAvailable = false;
    }
  }

  Future<void> _refreshAll() async {
    _now = DateTime.now();
    await Future.wait<void>([
      _refreshBattery(),
      _refreshNetworkKind(),
    ]);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshBattery() async {
    if (!_batteryAvailable || kIsWeb) {
      return;
    }
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      _batteryLevel = level.clamp(0, 100);
      _batteryState = state;
    } catch (_) {
      _batteryAvailable = false;
      _batteryLevel = null;
      _batteryState = null;
    }
  }

  Future<void> _refreshNetworkKind() async {
    _networkKind = await detectLargeScreenNetworkKind();
  }

  String _formatClock(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _dandanAvatarUrl() {
    final username = DandanplayService.userName ?? '';
    if (username.endsWith('@qq.com')) {
      final qqNumber = username.split('@').first;
      if (qqNumber.isNotEmpty) {
        return 'http://q.qlogo.cn/headimg_dl?dst_uin=$qqNumber&spec=640';
      }
    }
    return '';
  }

  IconData _resolveBatteryIcon() {
    final level = _batteryLevel;
    if (_batteryState == BatteryState.charging ||
        _batteryState == BatteryState.connectedNotCharging) {
      return CupertinoIcons.battery_charging;
    }
    if (level == null || _batteryState == BatteryState.unknown) {
      return CupertinoIcons.battery_25;
    }
    if (level <= 20) return CupertinoIcons.battery_0;
    if (level <= 60) return CupertinoIcons.battery_25;
    return CupertinoIcons.battery_100;
  }

  Widget _buildAvatar(Color textColor) {
    final avatarUrl = _dandanAvatarUrl();
    if (!DandanplayService.isLoggedIn) {
      return Icon(Icons.account_circle_rounded, size: 20, color: textColor);
    }
    if (avatarUrl.isEmpty) {
      return Icon(Icons.account_circle_rounded, size: 20, color: textColor);
    }
    return ClipOval(
      child: Image.network(
        avatarUrl,
        width: 20,
        height: 20,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.account_circle_rounded,
          size: 20,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildNetworkIcon(Color textColor) {
    switch (_networkKind) {
      case LargeScreenNetworkKind.wifi:
        return Icon(Icons.wifi_rounded, size: 18, color: textColor);
      case LargeScreenNetworkKind.cellular:
        return Icon(Icons.network_cell_rounded, size: 18, color: textColor);
      case LargeScreenNetworkKind.unavailable:
        return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _batteryStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : Colors.black87;
    final backgroundTint = widget.isDarkMode
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.14);
    final clockText = _formatClock(_now);

    return SizedBox(
      height: kNipaplayLargeScreenBottomHintHeight,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: ColoredBox(
            color: backgroundTint,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_networkKind != LargeScreenNetworkKind.unavailable) ...[
                      _buildNetworkIcon(textColor),
                      const SizedBox(width: 10),
                    ],
                    if (_batteryLevel != null) ...[
                      Icon(_resolveBatteryIcon(), size: 18, color: textColor),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      clockText,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildAvatar(textColor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
