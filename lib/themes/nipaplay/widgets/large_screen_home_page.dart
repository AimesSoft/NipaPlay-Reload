import 'package:flutter/material.dart';
import 'package:nipaplay/pages/dashboard_home_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/directional_focus_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_home_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_input_controls.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_navigation_intents.dart';

class NipaplayLargeScreenContentPage extends StatelessWidget {
  const NipaplayLargeScreenContentPage({
    super.key,
    required this.child,
    this.closeOnBack = false,
  });

  final Widget child;
  final bool closeOnBack;

  void _handleBoundaryScroll(
      BuildContext context, TraversalDirection direction) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final scrollController =
        PrimaryScrollController.maybeOf(focusContext ?? context);
    if (scrollController == null || !scrollController.hasClients) {
      return;
    }
    final target = direction == TraversalDirection.up
        ? scrollController.position.minScrollExtent
        : scrollController.position.maxScrollExtent;
    scrollController.jumpTo(target);
  }

  KeyEventResult _handleKeyEvent(BuildContext context, KeyEvent event) {
    if (!closeOnBack) {
      return KeyEventResult.ignored;
    }
    final command = NipaplayLargeScreenInputControls.fromKeyEvent(event);
    if (command != NipaplayLargeScreenInputCommand.back &&
        command != NipaplayLargeScreenInputCommand.toggleMenu) {
      return KeyEventResult.ignored;
    }
    if (!Navigator.of(context).canPop()) {
      return KeyEventResult.ignored;
    }
    Navigator.of(context).maybePop();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return NipaplayLargeScreenHomeScope(
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) => _handleKeyEvent(context, event),
        child: Actions(
          actions: <Type, Action<Intent>>{
            NipaplayScrollBoundaryIntent:
                CallbackAction<NipaplayScrollBoundaryIntent>(
              onInvoke: (intent) {
                _handleBoundaryScroll(context, intent.direction);
                return null;
              },
            ),
          },
          child: NipaplayDirectionalFocusScope(
            onBoundaryReached: (direction) =>
                _handleBoundaryScroll(context, direction),
            child: child,
          ),
        ),
      ),
    );
  }
}

class NipaplayLargeScreenHomePage extends StatelessWidget {
  const NipaplayLargeScreenHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const NipaplayLargeScreenContentPage(
      child: DashboardHomePage(),
    );
  }
}
