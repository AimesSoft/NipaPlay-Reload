import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Colours from `docs/next/design/visual/concept.html` (`:root`).
abstract final class NextColors {
  static const ink = Color(0xFF08080B);
  static const ink2 = Color(0xFF0F0F14);
  static const ink3 = Color(0xFF17171E);
  static const paper = Color(0xFFF5F1EA);
  static const p2 = Color(0xB8F5F1EA); // .72
  static const p3 = Color(0x7AF5F1EA); // .48
  static const p4 = Color(0x42F5F1EA); // .26
  static const line = Color(0x17F5F1EA); // .09
  static const line2 = Color(0x29F5F1EA); // .16
  static const accent = Color(0xFFFF2E55);
  static const accent2 = Color(0xFFFF6F8A);
  static const accentSoft = Color(0x24FF2E55); // .14
  static const mint = Color(0xFF5BE3B0);
  static const amber = Color(0xFFFFBF5C);
  static const glass = Color(0x8F14141A); // rgba(20,20,26,.56)
  static const glass2 = Color(0x9E202028); // rgba(32,32,40,.62)

  static Color inkAlpha(double a) => ink.withValues(alpha: a);
}

/// Font stacks. Titles of works use Songti SC, text PingFang SC, numbers the
/// system SF Pro with tabular figures.
abstract final class NextFonts {
  static const sans = 'PingFang SC';
  static const sansFallback = <String>['CupertinoSystemText', 'Helvetica Neue'];
  static const serif = 'Songti SC';
  static const serifFallback = <String>['STSong', 'Noto Serif SC', sans];
  static const num = 'CupertinoSystemDisplay';
  static const numFallback = <String>['.AppleSystemUIFont', sans];
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];
}

abstract final class NextText {
  static TextStyle sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = NextColors.paper,
    double? height,
    double letterSpacing = 0,
    List<Shadow>? shadows,
  }) =>
      TextStyle(
        fontFamily: NextFonts.sans,
        fontFamilyFallback: NextFonts.sansFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        shadows: shadows,
        decoration: TextDecoration.none,
        leadingDistribution: TextLeadingDistribution.even,
      );

  static TextStyle serif(double size,
          {FontWeight weight = FontWeight.w900,
          Color color = NextColors.paper,
          double? height,
          double letterSpacing = 0}) =>
      TextStyle(
        fontFamily: NextFonts.serif,
        fontFamilyFallback: NextFonts.serifFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        decoration: TextDecoration.none,
        leadingDistribution: TextLeadingDistribution.even,
      );

  static TextStyle num(double size,
          {FontWeight weight = FontWeight.w500,
          Color color = NextColors.paper,
          double letterSpacing = 0}) =>
      TextStyle(
        fontFamily: NextFonts.num,
        fontFamilyFallback: NextFonts.numFallback,
        fontFeatures: NextFonts.tabular,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        decoration: TextDecoration.none,
      );
}

abstract final class NextMotion {
  /// cubic-bezier(.22,1,.36,1)
  static const ease = Cubic(0.22, 1, 0.36, 1);
  static const page = Duration(milliseconds: 320);
  static const crossfade = Duration(milliseconds: 600);
  static const hoverFocus = Duration(milliseconds: 600);
  static const cardStagger = Duration(milliseconds: 60);
  static const kenBurns = Duration(seconds: 20);

  static bool? _forced;

  /// Debug experiments can force the reduced motion path.
  static set forceReduced(bool? value) => _forced = value;

  /// Follows the system setting: no push-in, parallax, focus-following
  /// backgrounds or shared element transitions; fades remain.
  static bool reduced(BuildContext context) {
    if (_forced case final forced?) return forced;
    final features =
        SchedulerBinding.instance.platformDispatcher.accessibilityFeatures;
    return MediaQuery.maybeDisableAnimationsOf(context) == true ||
        features.reduceMotion ||
        features.disableAnimations;
  }
}

abstract final class NextMetrics {
  /// Left edge of content, leaving room for the window's traffic lights.
  static const gutter = 96.0;
  static const topBar = 64.0;

  /// Height of the row the top bar's items sit in, centred on the native
  /// traffic lights of a hidden-title-bar macOS window (≈ 17 pt).
  static const chromeRow = 34.0;
}

const nextShadowCard = <BoxShadow>[
  BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 10)),
];
