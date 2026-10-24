import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/cards/card_views.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/data/discover.dart';
import 'package:nipaplay/next/ui/data/search.dart';
import 'package:nipaplay/next/ui/data/services.dart';
import 'package:nipaplay/next/ui/data/ui_actions.dart';
import 'package:nipaplay/next/ui/data/work_manage.dart';
import 'package:nipaplay/next/ui/detail/work_route.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui/theme/tokens.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

/// The whole window, for pictures of it.
final foundShotKey = GlobalKey(debugLabel: 'found shot');

/// Turned off and on, every picture is looked up again (for pictures
/// decoded outside the test's fake clock).
final foundTickers = ValueNotifier(true);

/// What a found page reads when it opens: the record's facts.
final class FoundDetails implements NextDiscoverData {
  FoundDetails([this.records = const {}]);
  final Map<String, Map<String, Object?>> records;
  final asked = <String>[];
  @override
  Future<UiDiscover> discover() async => const UiDiscover();
  @override
  Future<UiWork> details(UiWork work) async {
    asked.add(work.workId);
    return Found.withRecord(work, records[work.workId] ?? const {});
  }
}

/// A shell over [cards] in a conversation-wide column; opening a work
/// pushes the real `/work` page (a library work's from [data], which knows
/// none by default; [actions] and [manage] when it plays or is managed).
/// Dispose the returned shell after the tree.
Future<NextShellController> pumpFoundCards(
  WidgetTester tester, {
  required List<UiCard> cards,
  required NextDiscoverData discover,
  NextUiData? data,
  NextUiActions? actions,
  NextWorkManage? manage,
  Widget? above,
  void Function(UiWork work)? onPlay,
  double pixelRatio = 1,
}) async {
  tester.view.physicalSize = const Size(1440, 900) * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
  final unused = _Unused();
  final shell = NextShellController(
      NextUiServices(
        data: data ?? _Data(),
        actions: actions ?? unused,
        chat: _Port(),
        discover: discover,
        library: unused,
        libraryActions: unused,
        search: _Search(),
        settings: FakeSettings(),
        manage: manage,
      ),
      onLeave: () {});
  await tester.pumpWidget(RepaintBoundary(
    key: foundShotKey,
    child: ValueListenableBuilder<bool>(
      valueListenable: foundTickers,
      builder: (context, on, child) => TickerMode(enabled: on, child: child!),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: NextShellScope(
          controller: shell,
          child: ColoredBox(
            color: NextColors.ink,
            child: Navigator(
              key: shell.navigatorKey,
              onGenerateRoute: (settings) => settings.name == '/work'
                  ? workRoute(settings)
                  : PageRouteBuilder<void>(
                      settings: settings,
                      pageBuilder: (context, _, __) => ColoredBox(
                        color: NextColors.ink,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(56, 48, 56, 0),
                            child: SizedBox(
                              width: 700,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (above != null) ...[
                                    above,
                                    const SizedBox(height: 18),
                                  ],
                                  CardStack(
                                    cards: cards,
                                    posterWidth: 168,
                                    callbacks: CardCallbacks(
                                      onOpen: shell.openWork,
                                      onPlay: onPlay == null
                                          ? null
                                          : (work, _) => onPlay(work),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  ));
  return shell;
}

final class _Data implements NextUiData {
  @override
  Future<UiHome> home() async => const UiHome();
  @override
  Stream<List<UiTask>> tasks() => Stream.value(const []);
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<UiWork?> work(String workId) async => null;
  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async =>
      const [];
  @override
  Future<List<UiWork>> library() async => const [];
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      const [];
}

final class _Port implements ChatPort {
  @override
  bool get available => false;
  @override
  Future<String?> unavailableReason() async => null;
  @override
  bool get busy => false;
  @override
  bool busyOn(String threadId) => false;
  @override
  Stream<ChatEvent> get display => const Stream.empty();
  @override
  Stream<ChatEvent> get questions => const Stream.empty();
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Unused
    implements NextUiActions, NextLibraryData, NextLibraryActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Search implements NextSearchData {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
