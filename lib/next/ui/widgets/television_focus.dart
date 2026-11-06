import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// Remote input only; callers reuse their existing hover appearance.
/// Television visual design stays in those callers' builders.
class TelevisionFocusable extends StatelessWidget {
  const TelevisionFocusable(
      {super.key, required this.child, this.onActivate, this.onFocusChange});
  final Widget child;
  final VoidCallback? onActivate;
  final ValueChanged<bool>? onFocusChange;

  @visibleForTesting
  static bool Function() isTelevision = () => globals.isTvOS;

  @override
  Widget build(BuildContext context) {
    if (!isTelevision() || onActivate == null) return child;
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          onActivate?.call();
          return null;
        }),
      },
      onFocusChange: (focused) {
        onFocusChange?.call(focused);
      },
      child: child,
    );
  }
}

/// The top bar and the page navigator have separate FocusScopes. A remote's
/// directions must cross that boundary, while dialogs keep their own policy.
/// Scan live traversal nodes once per key, with no parallel focus state.
class TelevisionTraversalPolicy extends FocusTraversalPolicy {
  const TelevisionTraversalPolicy(this.root);
  final FocusNode root;

  @override
  FocusNode? findFirstFocusInDirection(
          FocusNode currentNode, TraversalDirection direction) =>
      WidgetOrderTraversalPolicy()
          .findFirstFocusInDirection(currentNode, direction);

  @override
  Iterable<FocusNode> sortDescendants(
          Iterable<FocusNode> descendants, FocusNode currentNode) =>
      descendants;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final horizontal = direction == TraversalDirection.left ||
        direction == TraversalDirection.right;
    final positive = direction == TraversalDirection.right ||
        direction == TraversalDirection.down;
    final from = currentNode.rect;
    FocusNode? best;
    var bestBeam = false;
    var bestDistance = double.infinity;
    for (final node in root.traversalDescendants) {
      if (node == currentNode || node is FocusScopeNode) continue;
      // Retained Navigator routes still have laid-out boxes. They must not
      // compete with the detail/settings page that covers them.
      final context = node.context;
      if (context == null || ModalRoute.of(context)?.isCurrent == false) continue;
      final target = node.context?.findRenderObject();
      if (target is! RenderBox || !target.attached || !target.hasSize) continue;
      final rect = node.rect;
      if (rect.isEmpty) continue;
      if (currentNode == root) {
        final distance = rect.top * 10000 + rect.left;
        if (distance < bestDistance) {
          best = node;
          bestDistance = distance;
        }
        continue;
      }
      final delta = rect.center - from.center;
      final primary = horizontal ? delta.dx : delta.dy;
      if (positive ? primary <= 0.5 : primary >= -0.5) continue;
      final beam = horizontal
          ? rect.top < from.bottom && rect.bottom > from.top
          : rect.left < from.right && rect.right > from.left;
      final distance = delta.distanceSquared;
      if (best == null ||
          (beam && !bestBeam) ||
          (beam == bestBeam && distance < bestDistance)) {
        best = node;
        bestBeam = beam;
        bestDistance = distance;
      }
    }
    if (best == null) return false;
    FocusTraversalPolicy.defaultTraversalRequestFocusCallback(best,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 180));
    return true;
  }
}
