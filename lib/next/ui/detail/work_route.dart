import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/art_origin.dart';
import 'detail_page.dart';

/// What `/work` is pushed with.
class WorkRouteArgs {
  const WorkRouteArgs(this.work, {this.origin});
  final UiWork work;

  /// The picture the work was opened from. It grows into the page's
  /// backdrop and shrinks back on return; without one the page fades in
  /// with the shell's page transition.
  final ArtOriginState? origin;
}

abstract final class WorkFlight {
  static const forward = Duration(milliseconds: 560);
  static const back = Duration(milliseconds: 460);
}

Route<void> workRoute(RouteSettings settings) {
  final args = settings.arguments as WorkRouteArgs;
  final flies = args.origin != null;
  return PageRouteBuilder<void>(
    settings: settings,
    transitionDuration: flies ? WorkFlight.forward : NextMotion.page,
    reverseTransitionDuration:
        flies ? WorkFlight.back : const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) =>
        WorkDetailPage(work: args.work, origin: args.origin),
    // A flying page animates its own layers (backdrop, then content).
    transitionsBuilder: (context, animation, _, child) =>
        flies && !NextMotion.reduced(context)
            ? child
            : nextPageTransition(context, animation, child),
  );
}
