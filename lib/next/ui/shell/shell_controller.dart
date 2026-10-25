import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../conversation/mesh_chat_port.dart';
import '../conversation/nipa_chat.dart';
import '../data/search.dart';
import '../data/services.dart';
import '../detail/work_route.dart';
import '../search/recent_searches.dart';
import '../search/search_controller.dart';
import '../settings/settings_layout.dart';
import '../settings/settings_page.dart';
import '../theme/tokens.dart';
import '../widgets/art_origin.dart';
import '../widgets/sheet.dart';
import 'nipa_setup.dart';

enum NextSection { home, discover, library, activity }

enum NextPopover { none, tasks, nipa }

/// Navigation and shared state of the Next shell. Rarely notifies; the
/// conversation and tasks are listened to where they are shown.
class NextShellController extends ChangeNotifier {
  NextShellController(this.services, {required this.onLeave}) {
    chat = NipaChat(
        port: services.chat,
        data: services.data,
        namesGuests: services.chat is! MeshChatPort);
    if (services.chat case final MeshChatPort port) {
      port.page = _pageName;
    }
    // A login card must be seen: the conversation comes up for it. Not over
    // a video: the player tells of it, and the conversation comes up when
    // the video is left.
    services.logins.onRequest = () {
      if (!_playing && !chatShown) openChat();
    };
    panelOpen.addListener(_syncVisible);
    homeChatOpen.addListener(_syncVisible);
    origins.reference =
        () => navigatorKey.currentContext?.findRenderObject() as RenderBox?;
    _tasks = services.data.tasks().listen((list) {
      tasks.value = list;
      if (activeTasks.isEmpty && popover == NextPopover.tasks) closePopover();
    });
  }

  final NextUiServices services;

  /// The page the person is on, as the conversation tells Nipa.
  String _pageName() => _playing
      ? '播放'
      : _settingsOpen
          ? '设置'
          : switch (section) {
              NextSection.home => '首页',
              NextSection.discover => '发现',
              NextSection.library => '片库',
              NextSection.activity => '动态',
            };

  /// Leaves Next for Classic (turns the preference off).
  final VoidCallback onLeave;
  /// The conversation with Nipa: on the home, expanded or folded away;
  /// on every other page, in the side panel.
  late final NipaChat chat;
  late final StreamSubscription<List<UiTask>> _tasks;
  final tasks = ValueNotifier<List<UiTask>>(const []);
  final navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'next');
  final askFocus = FocusNode(debugLabel: 'next.ask');

  /// What you are writing to Nipa, the same wherever the conversation is.
  final askText = TextEditingController();

  /// The home's conversation is expanded.
  final homeChatOpen = ValueNotifier<bool>(false);
  final homeChatFocus = FocusNode(debugLabel: 'next.homeChat');

  /// Files dropped on the home's input bar, going with what is said there.
  final askFiles = ValueNotifier<List<String>>(const []);

  /// Pictures a work can open from (shared element transitions).
  final origins = ArtOrigins();

  /// The conversation side panel (not on the home, which has its own).
  final panelOpen = ValueNotifier<bool>(false);
  final panelFocus = FocusNode(debugLabel: 'next.panel');

  /// Content scrolled under the top bar: show its scrim.
  final scrolled = ValueNotifier<bool>(false);

  /// Whether Nipa has a model yet (the rest of Next works either way).
  late final nipaSetup = NipaSetup(services.settings.host,
      peers: services.peers,
      port: services.chat is MeshChatPort
          ? services.chat as MeshChatPort
          : null);

  /// The search panel (⌘F, the top bar's search).
  late final search =
      NextSearch(services.search, store: const PreferenceRecentSearches());

  NextSection section = NextSection.home;
  NextPopover popover = NextPopover.none;

  /// Where the open settings page should go next (⌘, or a link while it
  /// is open); the page takes it and clears it.
  final settingsTarget = ValueNotifier<SettingsTarget?>(null);
  bool _settingsOpen = false;

  /// The settings page is on top.
  bool get settingsOpen => _settingsOpen;

  List<UiTask> get activeTasks => [
        for (final t in tasks.value)
          if (t.state == UiTaskState.running ||
              t.state == UiTaskState.queued ||
              t.state == UiTaskState.paused)
            t
      ];

  /// What the background panel lists: what runs, latest first, then the
  /// helpers that came back, the latest three.
  List<UiTask> get backgroundItems {
    int latest(UiTask a, UiTask b) => (b.startedAt ?? DateTime(0))
        .compareTo(a.startedAt ?? DateTime(0));
    final done = [
      for (final t in tasks.value)
        if (t.kind == UiTaskKind.helper &&
            (t.state == UiTaskState.finished || t.state == UiTaskState.failed))
          t
    ]..sort(latest);
    return [...activeTasks..sort(latest), ...done.take(3)];
  }

  /// A session's conversation, shown where the conversation is (a helper's,
  /// from the background panel).
  void openConversation(String threadId) {
    closePopover();
    unawaited(chat.select(threadId));
    openChat();
  }

  void go(NextSection target) {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    popover = NextPopover.none;
    // The home has the conversation itself: the panel's carries on there.
    if (target == NextSection.home && panelOpen.value) {
      _closePanel();
      homeChatOpen.value = true;
    }
    if (section != target) {
      section = target;
      scrolled.value = false;
    }
    notifyListeners();
    _syncVisible();
  }

  /// A video is open: the player is over every page, the conversation is
  /// the side panel over it.
  bool get playing => _playing;
  bool _playing = false;

  /// The player opens or closes over the pages. Whatever floated over the
  /// page goes; a conversation open over the video stays, and on the home
  /// becomes the home's own again. A login that waited through the video
  /// brings the conversation up once it is left.
  void setPlaying(bool value) {
    if (_playing == value) return;
    _playing = value;
    if (value) {
      popover = NextPopover.none;
      closeSearch(restoreFocus: false);
    } else if (panelOpen.value && onHome) {
      _closePanel();
      homeChatOpen.value = true;
    } else if (services.logins.pending.isNotEmpty && !chatShown) {
      openChat();
    }
    notifyListeners();
    _syncVisible();
  }

  /// On the home itself, not a page pushed over it.
  bool get onHome =>
      !_playing &&
      section == NextSection.home &&
      !(navigatorKey.currentState?.canPop() ?? false);

  /// The conversation is on screen.
  bool get chatShown => panelOpen.value || (onHome && homeChatOpen.value);

  void _syncVisible() => chat.setVisible(chatShown);

  /// ⌘K: the input where the conversation is: the home's bar, the
  /// expanded conversation, or the side panel.
  void ask() {
    closeSearch(restoreFocus: false);
    if (panelOpen.value) return panelFocus.requestFocus();
    if (!onHome) return openChat();
    popover = NextPopover.none;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        (homeChatOpen.value ? homeChatFocus : askFocus).requestFocus());
  }

  /// Opens the conversation: expanded on the home, the side panel
  /// elsewhere. With [about] (“问 Nipa” on a work's page) what you say goes
  /// with that work.
  void openChat({UiWork? about}) {
    closeSearch(restoreFocus: false);
    if (popover != NextPopover.none) {
      popover = NextPopover.none;
      notifyListeners();
    }
    if (about != null) chat.setAbout(about);
    if (onHome) {
      homeChatOpen.value = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => homeChatFocus.requestFocus());
      return;
    }
    panelOpen.value = true;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => panelFocus.requestFocus());
  }

  /// The avatar: opens the conversation, or puts it away.
  void toggleChat() {
    if (chatShown) {
      if (panelOpen.value) return closePanel();
      return foldHomeChat();
    }
    openChat();
  }

  /// Says [text] about [work] for you (the detail page's “下载全部”).
  void sayAbout(UiWork work, String text) {
    openChat(about: work);
    unawaited(chat.say(text));
  }

  /// The home's conversation folds away; it goes on, and the home tells
  /// how it ends.
  void foldHomeChat() {
    if (!homeChatOpen.value) return;
    homeChatOpen.value = false;
    homeChatFocus.unfocus();
  }

  void closePanel() {
    if (!panelOpen.value) return;
    _closePanel();
  }

  void _closePanel() {
    panelOpen.value = false;
    chat.closeMenu();
    if (chat.about != null) chat.setAbout(null);
    panelFocus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
  }

  /// The work's detail page. The picture it was opened from (under the
  /// pointer, or the largest one on screen) grows into the page's backdrop;
  /// under reduced motion the page only fades in.
  void openWork(UiWork work) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    popover = NextPopover.none;
    if (panelOpen.value) _closePanel();
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
      _syncVisible();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisible());
  }

  /// Settings (⌘, or the avatar's menu), at [section] or showing the
  /// setting [key]. Again while open: it goes there.
  void openSettings({SettingsSection? section, String? key}) {
    final nav = navigatorKey.currentState;
    if (nav == null || _playing) return;
    if (popover != NextPopover.none) {
      popover = NextPopover.none;
      notifyListeners();
    }
    if (_settingsOpen) {
      if (section != null || key != null) {
        settingsTarget.value = SettingsTarget(section: section, key: key);
      }
      return;
    }
    _settingsOpen = true;
    if (panelOpen.value) _closePanel();
    final wasScrolled = scrolled.value;
    final from = this.section;
    scrolled.value = false;
    nav
        .pushNamed('/settings',
            arguments: SettingsTarget(section: section, key: key))
        .then((_) {
      _settingsOpen = false;
      if (this.section == from) scrolled.value = wasScrolled;
      _syncVisible();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisible());
  }

  void play(UiWork work, {UiEpisode? episode}) {
    unawaited(services.actions
        .play(work, episode: episode ?? work.next)
        .catchError((Object e) => debugPrint('[NextUi] play failed: $e')));
  }

  /// ⌘F: the search panel, over whatever shows (not over a video).
  void openSearch() {
    if (_playing) return;
    closePopover();
    search.show();
  }

  void closeSearch({bool restoreFocus = true}) =>
      search.hide(restoreFocus: restoreFocus);

  /// A row of the search panel: a work opens its page; an episode plays;
  /// a file of a source no work holds plays from the source; Nipa gets the
  /// words to look for, in the conversation's input, not yet said.
  void openSearchEntry(SearchEntry entry) {
    if (entry case RecentEntry(:final text)) return search.searchNow(text);
    search.remember();
    closeSearch(restoreFocus: false);
    switch (entry) {
      case WorkEntry(:final work):
        openWork(work);
      case EpisodeEntry(:final work, :final episode):
        // One that cannot play yet opens its work, where it can be fetched.
        episode.playable ? play(work, episode: episode) : openWork(work);
      case SourceEntry(:final hit):
        switch ((hit.kind, hit.work, hit.episode)) {
          case (UiSourceHitKind.work, final work?, _):
            openWork(work);
          case (_, final work?, final episode?):
            episode.playable ? play(work, episode: episode) : openWork(work);
          case (_, final work?, null):
            openWork(work);
          case (_, null, _):
            unawaited(services.actions
                .playFromSource(
                    sourceId: hit.source.sourceId, itemId: hit.itemId)
                .catchError(
                    (Object e) => debugPrint('[NextUi] play failed: $e')));
        }
      case NipaEntry(:final text):
        final words = '帮我找「$text」';
        askText.value = TextEditingValue(
            text: words,
            selection: TextSelection.collapsed(offset: words.length));
        openChat();
      case RecentEntry():
        break;
    }
  }

  void togglePopover(NextPopover which) {
    popover = popover == which ? NextPopover.none : which;
    if (popover == NextPopover.nipa) chat.markSeen();
    notifyListeners();
  }

  void closePopover() {
    if (popover == NextPopover.none) return;
    popover = NextPopover.none;
    notifyListeners();
  }

  /// Esc: closes what is on top, one layer at a time.
  bool escape() {
    if (NextSheetLayer.closeTop()) return true;
    if (search.isOpen) {
      closeSearch();
      return true;
    }
    if (chat.menuOpen && chatShown) {
      chat.closeMenu();
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
    // The pages under the video stay as they were left.
    if (_playing) return false;
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return true;
    }
    if (onHome && homeChatOpen.value) {
      foldHomeChat();
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
    panelOpen.removeListener(_syncVisible);
    homeChatOpen.removeListener(_syncVisible);
    chat.dispose();
    search.dispose();
    settingsTarget.dispose();
    nipaSetup.dispose();
    tasks.dispose();
    scrolled.dispose();
    askFocus.dispose();
    askText.dispose();
    askFiles.dispose();
    services.logins.onRequest = null;
    panelFocus.dispose();
    panelOpen.dispose();
    homeChatOpen.dispose();
    homeChatFocus.dispose();
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
