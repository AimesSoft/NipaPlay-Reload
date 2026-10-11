import 'dart:io' show Platform;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Where the window's own controls sit, as the native side reports them.
@immutable
class NextChromeLayout {
  const NextChromeLayout({this.leading = 0, this.fullScreen = false});

  /// Right edge of the traffic lights, in logical pixels from the window's
  /// left edge; 0 when the window shows none (full screen, other platforms).
  final double leading;
  final bool fullScreen;

  @override
  bool operator ==(Object other) =>
      other is NextChromeLayout &&
      other.leading == leading &&
      other.fullScreen == fullScreen;

  @override
  int get hashCode => Object.hash(leading, fullScreen);
}

/// The window around the Next shell. On macOS, `nipaplay/next_chrome`
/// (MainFlutterWindow.swift) gives the window a 52 pt title bar band with
/// the traffic lights centred in it while Next is on screen, and puts
/// Classic's window back when it is not.
abstract final class NextWindowChrome {
  static const _channel = MethodChannel('nipaplay/next_chrome');

  static final layout = ValueNotifier(const NextChromeLayout());

  /// Whether the Next shell is the interface on screen (Classic's lab badge
  /// steps aside while it is).
  static final showing = ValueNotifier(false);

  static Future<void> _set(bool on) async {
    showing.value = on;
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'layout') _apply(call.arguments as Map);
    });
    _apply((await _channel.invokeMethod<Map>('set', on))!);
  }

  static void _apply(Map reply) => layout.value = NextChromeLayout(
        leading: (reply['leading'] as num).toDouble(),
        fullScreen: reply['fullScreen'] as bool,
      );
}

/// Keeps the window chrome in step with whether Next is on screen.
class NextWindowChromeScope extends StatefulWidget {
  const NextWindowChromeScope(
      {super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<NextWindowChromeScope> createState() => _NextWindowChromeScopeState();
}

class _NextWindowChromeScopeState extends State<NextWindowChromeScope> {
  bool _disposed = false;

  // After the frame: the lab badge listens to [NextWindowChrome.showing]
  // and must not be marked dirty mid-build.
  void _sync() => SchedulerBinding.instance.addPostFrameCallback(
      (_) => NextWindowChrome._set(!_disposed && widget.active));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(NextWindowChromeScope old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void dispose() {
    _disposed = true;
    _sync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The lab profile's badge while Next is on screen: small, quiet, bottom
/// left, never over the top bar.
class NextLabBadge extends StatelessWidget {
  const NextLabBadge({super.key, required this.profile});
  final String profile;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x8C0A0A0E),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 7, 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Color(0xFFE0782F)),
              ),
              const SizedBox(width: 5),
              Text('LAB · $profile',
                  style: NextText.num(10, color: NextColors.p3)),
            ]),
          ),
        ),
      );
}
