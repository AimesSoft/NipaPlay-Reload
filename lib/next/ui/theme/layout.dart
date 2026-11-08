import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

import 'tokens.dart';

/// How much room the shell has. A desktop window or an iPad lays the pages
/// out as they always were; a phone (a narrow room) takes one column with
/// narrow margins, its sections at the foot, and keeps clear of the
/// system's own edges (the status bar, the island, the home indicator).
/// One data layer either way: only the layout follows the width.
abstract final class NextLayout {
  /// Below this width the pages take a phone's column.
  static const compactWidth = 600.0;

  /// A phone's side margin, where a window has [NextMetrics.gutter].
  static const compactGutter = 20.0;

  /// The sections' glass bar at a phone's foot, above the home indicator.
  static const tabBar = 62.0;

  /// The line to Nipa above the sections, the gap between them, and the
  /// dock's side margin.
  static const dockLine = 50.0;
  static const dockGap = 10.0;
  static const dockSide = 16.0;

  static bool compact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactWidth;

  /// The sections, search and the line to Nipa are at the foot: on a
  /// phone, a tablet (as on a phone, whatever its width) and in a narrow
  /// window. A computer's window and a television keep the top bar's.
  static bool docked(BuildContext context) =>
      compact(context) ||
      (globals.isMobilePlatform && !globals.isTelevision);

  /// The content's left edge.
  static double gutter(BuildContext context) =>
      compact(context) ? compactGutter : NextMetrics.gutter;

  /// The content's right margin.
  static double end(BuildContext context) =>
      compact(context) ? compactGutter : 56;

  /// Where the top bar starts: under the status bar on a phone or a tablet;
  /// at the window's edge on a desktop (no inset there).
  static double barTop(BuildContext context) =>
      MediaQuery.paddingOf(context).top;

  /// The top bar's lower edge, where content may begin.
  static double underBar(BuildContext context) =>
      barTop(context) + NextMetrics.topBar;

  /// Room a page leaves at its foot for the sections' bar and the home
  /// indicator; none in a window.
  static double foot(BuildContext context) {
    if (!docked(context)) return 0;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return dockLine + dockGap + tabBar + (bottom > 0 ? bottom - 8 : 12) + 12;
  }
}
