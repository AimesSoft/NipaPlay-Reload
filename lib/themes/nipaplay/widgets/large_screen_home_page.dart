import 'package:flutter/material.dart';
import 'package:nipaplay/pages/dashboard_home_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/directional_focus_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_home_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_navigation_intents.dart';

class NipaplayLargeScreenHomePage extends StatelessWidget {
  const NipaplayLargeScreenHomePage({super.key});

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

  @override
  Widget build(BuildContext context) {
    return NipaplayLargeScreenHomeScope(
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
          child: const DashboardHomePage(),
        ),
      ),
    );
  }
}
