import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/control_shadow.dart';

class MobilePlaybackStatus extends StatefulWidget {
  const MobilePlaybackStatus({
    super.key,
    this.compact = false,
    this.withBackground = false,
  });

  final bool compact;
  final bool withBackground;

  @override
  State<MobilePlaybackStatus> createState() => _MobilePlaybackStatusState();
}

class _MobilePlaybackStatusState extends State<MobilePlaybackStatus> {
  static const Duration _refreshInterval = Duration(seconds: 30);

  final Battery _battery = Battery();

  Timer? _refreshTimer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;

  DateTime _now = DateTime.now();
  int? _batteryLevel;
  BatteryState? _batteryState;
  int _tickCount = 0;
  bool _batteryAvailable = true;

  @override
  void initState() {
    super.initState();
    _refreshBatteryInfo();
    _listenBatteryState();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!mounted) return;
      _refreshClock();
      _tickCount += 1;
      if (_tickCount % 2 == 0) {
        _refreshBatteryInfo();
      }
    });
  }

  void _listenBatteryState() {
    if (kIsWeb) {
      _batteryAvailable = false;
      return;
    }
    try {
      _batteryStateSubscription =
          _battery.onBatteryStateChanged.listen((state) {
        if (!mounted) return;
        setState(() {
          _batteryState = state;
        });
        _refreshBatteryInfo();
      });
    } catch (_) {
      _batteryAvailable = false;
    }
  }

  void _refreshClock() {
    setState(() {
      _now = DateTime.now();
    });
  }

  Future<void> _refreshBatteryInfo() async {
    if (!_batteryAvailable || kIsWeb) return;
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      if (!mounted) return;
      setState(() {
        _batteryLevel = level.clamp(0, 100);
        _batteryState = state;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _batteryAvailable = false;
      });
    }
  }

  String _formatClock(DateTime time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  IconData _resolveBatteryIcon() {
    final int? level = _batteryLevel;
    if (_batteryState == BatteryState.charging ||
        _batteryState == BatteryState.connectedNotCharging) {
      return CupertinoIcons.battery_charging;
    }
    if (_batteryState == BatteryState.unknown || level == null) {
      return CupertinoIcons.battery_charging;
    }
    if (level <= 20) {
      return CupertinoIcons.battery_0;
    }
    if (level <= 60) {
      return CupertinoIcons.battery_25;
    }
    return CupertinoIcons.battery_100;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _batteryStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: widget.compact ? 11 : 13,
      fontWeight: FontWeight.normal,
      height: 1.0,
    );

    final double iconSize = widget.compact ? 13.0 : 16.0;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ControlTextShadow(
          child: Text(
            _formatClock(_now),
            style: textStyle,
            softWrap: false,
          ),
        ),
        const SizedBox(width: 8),
        ControlIconShadow(
          child: Icon(
            _resolveBatteryIcon(),
            size: iconSize,
            color: Colors.white,
          ),
        ),
      ],
    );

    return IgnorePointer(
      child: widget.withBackground
          ? Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10.0 : 12.0,
                vertical: widget.compact ? 7.0 : 8.0,
              ),
              decoration: BoxDecoration(
                color: const Color.fromARGB(95, 0, 0, 0),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color.fromARGB(90, 255, 255, 255),
                ),
              ),
              child: content,
            )
          : content,
    );
  }
}
