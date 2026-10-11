import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../conversation/conversation.dart';
import '../conversation/panel_chat.dart';
import '../conversation/session_choice.dart';
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
    choice = SessionChoice(services.chat);
    conversation = Conversation(
        port: services.chat, data: services.data, choice: choice);
    panel = PanelChat(
        port: services.chat,
        data: services.data,
        home: conversation,
        choice: choice);
    // A login card must be seen: the panel comes up for it.
    services.logins.onRequest = () {
      if (!panelOpen.value) openPanel();
    };
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
  /// Where what you say goes: the main session unless you picked another.
  late final SessionChoice choice;
  late final Conversation conversation;
  late final StreamSubscription<List<UiTask>> _tasks;
  final tasks = ValueNotifier<List<UiTask>>(const []);
  final navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'next');
  final askFocus = FocusNode(debugLabel: 'next.ask');
  final askText = TextEditingController();

  /// Pictures a work can open from (shared element transitions).
  final origins = ArtOrigins();

  /// The conversation side panel.
  final panelOpen = ValueNotifier<bool>(false);
  late final PanelChat panel;
  final panelFocus = FocusNode(debugLabel: 'next.panel');
  final panelText = TextEditingController();

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

  /// ⌘K. On the home it focuses the input bar; on any other page (or with
  /// the panel already open) it opens the side panel.
  void ask() {
    if (panelOpen.value) return panelFocus.requestFocus();
    final onHome = section == NextSection.home &&
        !(navigatorKey.currentState?.canPop() ?? false);
    if (!onHome) return openPanel();
    popover = NextPopover.none;
    notifyListeners();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => askFocus.requestFocus());
  }

  /// Opens the side panel on the current session (the main one unless you
  /// picked another). With [about] (“问 Nipa” on a work's page) the input
  /// reads “问问《片名》” and the work goes to the agent with what you say.
  void openPanel({UiWork? about}) => _openPanel(about: about);

  /// Opens the side panel on one session (the home's “展开”).
  void openPanelOn(String threadId) => _openPanel(threadId: threadId);

  /// Opens the side panel about [work] and says [text] there for you, in
  /// the current session (the detail page's “下载全部”).
  void sayAbout(UiWork work, String text) =>
      _openPanel(about: work, say: text);

  void _openPanel({UiWork? about, String? threadId, String? say}) {
    if (popover != NextPopover.none) {
      popover = NextPopover.none;
      notifyListeners();
    }
    Future<void> open() async {
      await panel.show(threadId: threadId, about: about);
      if (say != null) await panel.say(say);
    }

    unawaited(open());
    panelOpen.value = true;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => panelFocus.requestFocus());
  }

  void closePanel() {
    if (!panelOpen.value) return;
    panelOpen.value = false;
    panel.hide();
    panelFocus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
  }

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
    if (panelOpen.value && panel.menuOpen) {
      panel.closeMenu();
      return true;
    }
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
    services.logins.onRequest = null;
    panel.dispose();
    choice.dispose();
    panelFocus.dispose();
    panelText.dispose();
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
