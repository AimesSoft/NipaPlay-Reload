import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../conversation/conversation.dart';
import '../data/services.dart';
import '../detail/work_route.dart';
import '../theme/tokens.dart';
import '../widgets/art_origin.dart';

enum NextSection { home, library, activity }

enum NextPopover { none, tasks, nipa }

/// Navigation and shared state of the Next shell. Rarely notifies; the
/// conversation and tasks are listened to where they are shown.
class NextShellController extends ChangeNotifier {
  NextShellController(this.services, {required this.onLeave}) {
    conversation = Conversation(port: services.chat, data: services.data);
    origins.reference =
        () => navigatorKey.currentContext?.findRenderObject() as RenderBox?;
    _tasks = services.data.tasks().listen((list) {
      tasks.value = list;
      if (activeTasks.isEmpty && popover == NextPopover.tasks) closePopover();
    });
  }

  final NextUiServices services;

  /// Leaves Next for Classic (turns the preference off).
  final VoidCallback onLeave;
  late final Conversation conversation;
  late final StreamSubscription<List<UiTask>> _tasks;
  final tasks = ValueNotifier<List<UiTask>>(const []);
  final navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'next');
  final askFocus = FocusNode(debugLabel: 'next.ask');
  final askText = TextEditingController();

  /// Pictures a work can open from (shared element transitions).
  final origins = ArtOrigins();

  /// The conversation side panel's slot (the panel itself is next stage).
  final panelOpen = ValueNotifier<bool>(false);

  /// Content scrolled under the top bar: show its scrim.
  final scrolled = ValueNotifier<bool>(false);

  NextSection section = NextSection.home;
  NextPopover popover = NextPopover.none;

  List<UiTask> get activeTasks => [
        for (final t in tasks.value)
          if (t.state == UiTaskState.running ||
              t.state == UiTaskState.queued ||
              t.state == UiTaskState.paused)
            t
      ];

  /// Overall progress of background work, 0..1.
  double get totalProgress {
    final active = activeTasks;
    if (active.isEmpty) return 0;
    final sum = active.fold<double>(0, (a, t) => a + (t.progress ?? 0));
    return sum / active.length;
  }

  void go(NextSection target) {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    popover = NextPopover.none;
    if (section != target) {
      section = target;
      scrolled.value = false;
    }
    notifyListeners();
  }

  /// ⌘K. On the home it focuses the input bar. Elsewhere it will open the
  /// conversation panel (next stage); until then it goes home and focuses.
  void ask() {
    if (section != NextSection.home ||
        (navigatorKey.currentState?.canPop() ?? false)) {
      go(NextSection.home);
    }
    popover = NextPopover.none;
    notifyListeners();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => askFocus.requestFocus());
  }

  /// Slot for the conversation side panel (next stage): until it exists,
  /// asking happens in the home's input bar. [about] is the work the
  /// conversation starts from (the detail page's “问 Nipa”).
  void openPanel({UiWork? about}) {
    panelOpen.value = true;
    ask();
  }

  void closePanel() => panelOpen.value = false;

  /// The work's detail page. The picture it was opened from (under the
  /// pointer, or the largest one on screen) grows into the page's backdrop;
  /// under reduced motion the page only fades in.
  void openWork(UiWork work) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    popover = NextPopover.none;
    notifyListeners();
    final origin =
        NextMotion.reduced(nav.context) ? null : origins.find(work.workId);
    if (origin != null && origin.lifts) origin.hidden = true;
    // The page draws its own bar scrim and title; the section's comes back
    // with it.
    final from = section, wasScrolled = scrolled.value;
    scrolled.value = false;
    nav
        .pushNamed('/work', arguments: WorkRouteArgs(work, origin: origin))
        .then((_) {
      if (section == from) scrolled.value = wasScrolled;
    });
  }

  void play(UiWork work, {UiEpisode? episode}) {
    unawaited(services.actions
        .play(work, episode: episode ?? work.next)
        .catchError((Object e) => debugPrint('[NextUi] play failed: $e')));
  }

  void togglePopover(NextPopover which) {
    popover = popover == which ? NextPopover.none : which;
    if (popover == NextPopover.nipa) conversation.markSeen();
    notifyListeners();
  }

  void closePopover() {
    if (popover == NextPopover.none) return;
    popover = NextPopover.none;
    notifyListeners();
  }

  /// Esc: closes what is on top, one layer at a time.
  bool escape() {
    if (panelOpen.value) {
      closePanel();
      return true;
    }
    if (popover != NextPopover.none) {
      closePopover();
      return true;
    }
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return true;
    }
    if (section == NextSection.home && conversation.staged) {
      conversation.dismiss();
      return true;
    }
    if (askFocus.hasFocus) {
      askFocus.unfocus();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _tasks.cancel();
    conversation.dispose();
    tasks.dispose();
    scrolled.dispose();
    askFocus.dispose();
    askText.dispose();
    panelOpen.dispose();
    super.dispose();
  }
}

class NextShellScope extends InheritedWidget {
  const NextShellScope(
      {super.key, required this.controller, required super.child});
  final NextShellController controller;

  static NextShellController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NextShellScope>()!.controller;

  @override
  bool updateShouldNotify(NextShellScope old) => old.controller != controller;
}

/// The shell's page transition: fade in while scaling 0.98 → 1, 320 ms
/// ease-out; fade only under reduced motion.
Widget nextPageTransition(
    BuildContext context, Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
  if (NextMotion.reduced(context)) {
    return FadeTransition(opacity: curved, child: child);
  }
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: Tween(begin: 0.98, end: 1.0).animate(curved),
      child: child,
    ),
  );
}
