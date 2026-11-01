import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Edge where the system places toolbars and tab bars vertically.
///
/// Mirrors UIKit's `UITraitCollection.verticalBarEdge` (iOS 27.1+). iPhone Duo
/// reports [leading] or [trailing] when bars belong on the side of the window
/// (outer display, inner display in landscape, Split View); every other device
/// and pose reports [unspecified].
enum SystemVerticalBarEdge { unspecified, leading, trailing }

/// Mirrors `UIUserInterfaceSizeClass`.
enum SystemSizeClass { unspecified, compact, regular }

/// Where the phone shell places its primary navigation.
enum PhoneNavigationPlacement { bottom, left, right }

extension PhoneNavigationPlacementAxis on PhoneNavigationPlacement {
  bool get isVertical => this != PhoneNavigationPlacement.bottom;
}

/// Converts the system's leading/trailing preference into a physical side.
///
/// UIKit resolves leading and trailing with its own layout direction, which
/// can differ from the Flutter [Directionality] of the app.
PhoneNavigationPlacement resolvePhoneNavigationPlacement({
  required SystemVerticalBarEdge edge,
  required bool isRightToLeft,
}) {
  switch (edge) {
    case SystemVerticalBarEdge.unspecified:
      return PhoneNavigationPlacement.bottom;
    case SystemVerticalBarEdge.leading:
      return isRightToLeft
          ? PhoneNavigationPlacement.right
          : PhoneNavigationPlacement.left;
    case SystemVerticalBarEdge.trailing:
      return isRightToLeft
          ? PhoneNavigationPlacement.left
          : PhoneNavigationPlacement.right;
  }
}

/// Window traits the iOS phone shell lays out by: where the system puts bars,
/// what it reserves, and how much horizontal space it considers available.
@immutable
class SystemWindowTraits {
  const SystemWindowTraits({
    this.verticalBarEdge = SystemVerticalBarEdge.unspecified,
    this.isRightToLeft = false,
    this.occlusions = const <Rect>[],
    this.horizontalSizeClass = SystemSizeClass.unspecified,
  });

  /// Parses the `nipaplay/window_traits` reply. Unknown values fall back to
  /// the defaults, which keep the regular phone layout.
  factory SystemWindowTraits.fromPlatform(Map<Object?, Object?>? data) {
    final rawOcclusions = data?['occlusions'];
    return SystemWindowTraits(
      verticalBarEdge: switch (data?['verticalBarEdge']) {
        1 => SystemVerticalBarEdge.leading,
        2 => SystemVerticalBarEdge.trailing,
        _ => SystemVerticalBarEdge.unspecified,
      },
      isRightToLeft: data?['isRightToLeft'] == true,
      occlusions: [
        if (rawOcclusions is List)
          for (final frame in rawOcclusions)
            if (frame is List &&
                frame.length == 4 &&
                frame.every((value) => value is num))
              Rect.fromLTWH(
                (frame[0] as num).toDouble(),
                (frame[1] as num).toDouble(),
                (frame[2] as num).toDouble(),
                (frame[3] as num).toDouble(),
              ),
      ],
      horizontalSizeClass: switch (data?['horizontalSizeClass']) {
        1 => SystemSizeClass.compact,
        2 => SystemSizeClass.regular,
        _ => SystemSizeClass.unspecified,
      },
    );
  }

  final SystemVerticalBarEdge verticalBarEdge;
  final bool isRightToLeft;

  /// Window areas covered by hardware or system chrome that custom bars must
  /// avoid (`UIView.reservedRegions`), such as the iPhone Duo outer camera and
  /// the status bar column above the side controls.
  final List<Rect> occlusions;

  /// The window's horizontal size class: compact on iPhone displays, regular
  /// on the iPhone Duo inner display.
  final SystemSizeClass horizontalSizeClass;

  bool get isRegularWidth => horizontalSizeClass == SystemSizeClass.regular;

  PhoneNavigationPlacement get navigationPlacement =>
      resolvePhoneNavigationPlacement(
        edge: verticalBarEdge,
        isRightToLeft: isRightToLeft,
      );

  @override
  bool operator ==(Object other) =>
      other is SystemWindowTraits &&
      other.verticalBarEdge == verticalBarEdge &&
      other.isRightToLeft == isRightToLeft &&
      listEquals(other.occlusions, occlusions) &&
      other.horizontalSizeClass == horizontalSizeClass;

  @override
  int get hashCode => Object.hash(
        verticalBarEdge,
        isRightToLeft,
        Object.hashAll(occlusions),
        horizontalSizeClass,
      );
}

/// Tracks [SystemWindowTraits] for the root iOS window.
///
/// The traits change with the window's size, orientation, and multitasking
/// position, all of which also change the Flutter view metrics, so they are
/// re-read whenever the metrics change, and once more after the transition:
/// the status bar settles into its final region after the window has resized.
class SystemWindowTraitsObserver with WidgetsBindingObserver {
  SystemWindowTraitsObserver({
    MethodChannel channel = const MethodChannel('nipaplay/window_traits'),
    this.settleDelay = const Duration(milliseconds: 600),
  }) : _channel = channel;

  static final SystemWindowTraitsObserver instance =
      SystemWindowTraitsObserver();

  final MethodChannel _channel;
  final Duration settleDelay;
  final ValueNotifier<SystemWindowTraits> traits =
      ValueNotifier<SystemWindowTraits>(const SystemWindowTraits());
  bool _started = false;
  int _requestGeneration = 0;
  Timer? _settleTimer;

  /// Starts observing on iOS. Other platforms keep the default traits.
  void ensureStarted() {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  @override
  void didChangeMetrics() {
    unawaited(refresh());
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDelay, () => unawaited(refresh()));
  }

  Future<void> refresh() async {
    final generation = ++_requestGeneration;
    Map<Object?, Object?>? data;
    try {
      data = await _channel.invokeMapMethod<Object?, Object?>(
        'getWindowTraits',
      );
    } on MissingPluginException {
      data = null;
    } on PlatformException {
      data = null;
    }
    // A newer metrics change may have answered first; keep the latest reply.
    if (generation != _requestGeneration) return;
    traits.value = SystemWindowTraits.fromPlatform(data);
  }
}
