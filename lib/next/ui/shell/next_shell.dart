import 'package:flutter/material.dart'
    show Material, MaterialType, TextSelectionThemeData, Theme, ThemeData;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/services.dart';
import '../dev/debug_extension.dart';
import '../home/home_page.dart';
import '../pages/activity_page.dart';
import '../pages/detail_slot.dart';
import '../pages/library_page.dart';
import '../theme/tokens.dart';
import '../widgets/grain.dart';
import 'shell_controller.dart';
import 'top_bar.dart';

/// The Next application shell: top bar, sections, pushed pages (detail,
/// next stage), popovers, ⌘K / Esc, grain over everything.
class NextShell extends StatefulWidget {
  const NextShell({super.key, required this.onLeave});

  /// Back to Classic.
  final VoidCallback onLeave;

  @override
  State<NextShell> createState() => _NextShellState();
}

class _NextShellState extends State<NextShell> {
  late final NextUiServices _services = NextUiServices.resolve(context);
  late final NextShellController _shell =
      NextShellController(_services, onLeave: widget.onLeave);
  final _focus = FocusNode(debugLabel: 'next.shell');

  @override
  void initState() {
    super.initState();
    if (kDebugMode) NextUiDebug.attach(_shell, context);
  }

  @override
  void dispose() {
    if (kDebugMode) NextUiDebug.detach(_shell);
    _shell.dispose();
    _services.dispose();
    _focus.dispose();
    super.dispose();
  }

  Route<void> _route(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      '/work' => DetailSlot(work: settings.arguments as UiWork),
      _ => const _Sections(),
    };
    return PageRouteBuilder<void>(
      settings: settings,
      opaque: settings.name != '/',
      transitionDuration: NextMotion.page,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, __) => page,
      transitionsBuilder: (context, animation, _, child) =>
          nextPageTransition(context, animation, child),
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical && n.depth == 0) {
      _shell.scrolled.value = n.metrics.pixels > 24;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: NextFonts.sans,
        fontFamilyFallback: NextFonts.sansFallback,
        scaffoldBackgroundColor: NextColors.ink,
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: NextColors.accent,
          selectionColor: Color(0x59FF2E55),
          selectionHandleColor: NextColors.accent,
        ),
        platform: base.platform,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: NextText.sans(14),
          child: NextShellScope(
            controller: _shell,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                    _shell.ask,
                const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                    _shell.ask,
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _shell.escape(),
              },
              child: Focus(
                focusNode: _focus,
                autofocus: true,
                child: ColoredBox(
                  color: NextColors.ink,
                  child: Stack(children: [
                    Positioned.fill(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: Navigator(
                          key: _shell.navigatorKey,
                          onGenerateRoute: _route,
                        ),
                      ),
                    ),
                    // Scrim under the bar once content scrolls beneath it.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 96,
                      child: IgnorePointer(
                        child: ValueListenableBuilder(
                          valueListenable: _shell.scrolled,
                          builder: (context, scrolled, _) => AnimatedOpacity(
                            opacity: scrolled ? 1 : 0,
                            duration: const Duration(milliseconds: 240),
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xE608080B),
                                    Color(0x0008080B)
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                        left: 0, right: 0, top: 0, child: NextTopBar()),
                    const Positioned.fill(child: Grain()),
                    const Positioned.fill(child: NextPopovers()),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Home, library and activity. Visited sections stay alive (scroll position
/// kept); the entering one fades in from 0.98.
class _Sections extends StatefulWidget {
  const _Sections();

  @override
  State<_Sections> createState() => _SectionsState();
}

class _SectionsState extends State<_Sections>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: NextMotion.page, value: 1);
  final _visited = <NextSection>{NextSection.home};
  NextSection? _current;
  NextShellController? _shell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (!identical(shell, _shell)) {
      _shell?.removeListener(_changed);
      _shell = shell..addListener(_changed);
      _current = shell.section;
    }
  }

  void _changed() {
    final next = _shell!.section;
    if (next == _current) return;
    setState(() {
      _current = next;
      _visited.add(next);
    });
    _enter.forward(from: 0);
  }

  @override
  void dispose() {
    _shell?.removeListener(_changed);
    _enter.dispose();
    super.dispose();
  }

  static Widget _page(NextSection s) => switch (s) {
        NextSection.home => const NextHomePage(),
        NextSection.library => const LibraryPage(),
        NextSection.activity => const ActivityPage(),
      };

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        for (final s in NextSection.values)
          if (_visited.contains(s))
            Offstage(
              key: ValueKey(s),
              offstage: s != _current,
              child: TickerMode(
                enabled: s == _current,
                child: nextPageTransition(
                    context,
                    s == _current ? _enter : kAlwaysCompleteAnimation,
                    _page(s)),
              ),
            ),
      ]);
}
