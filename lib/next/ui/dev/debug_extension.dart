import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart' show Failure;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../accounts/login_dialog.dart';
import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../chat/chat_frame.dart';
import '../chat/transcript.dart';
import '../conversation/nipa_chat.dart';
import '../detail/collection.dart';
import '../detail/detail_page.dart';
import '../detail/episodes.dart';
import '../home/ask_bar.dart';
import '../downloads/download_list.dart';
import '../downloads/download_sheet.dart';
import '../downloads/limits_sheet.dart';
import '../downloads/new_download.dart';
import '../pages/activity_page.dart';
import '../pages/history_view.dart';
import '../pages/discover_page.dart';
import '../panel/chat_panel.dart';
import '../widgets/drop_zone.dart';
import '../shell/next_ui_preference.dart';
import '../library/batch_bar.dart';
import '../library/batch_sheet.dart';
import '../library/category_page.dart';
import '../library/fan_cover.dart';
import '../pages/library_page.dart';
import '../search/search_controller.dart';
import '../search/search_overlay.dart';
import '../shell/shell_controller.dart';
import '../shell/window_chrome.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/menu.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/sheet.dart';
import '../widgets/shelf.dart';
import '../widgets/words.dart';
import 'dev_services.dart';
import 'fake_settings.dart';
import 'fake_world.dart';
import '../settings/settings_layout.dart';
import '../settings/settings_page.dart';

/// `ext.nipaplay.nextui`: a VM-service-only driver for experiments and
/// screenshots of the Next interface. Registered only in Debug builds with a
/// lab profile (see [NextUiDev.enabled]); it is not a harness Action and the
/// agent cannot reach it.
///
/// Ops (`op=`):
/// - `status`
/// - `home` `state=A|B|C` [`text=`]: A folds the conversation away; B says
///   [text] (default “来点轻松的”) and expands it; C folds it and wakes
///   Nipa (scripted chat only).
/// - `fill` `text=`: put text in the input without sending; `send` sends
///   it as Enter does where the conversation is.
/// - `hover` `index=N` [`area=stage|shelf|avatar|episodes|library`]: a
///   synthetic mouse hovers the N-th visible card (no OS pointer moves);
///   `index=-1` leaves.
/// - `tap` `index=N` `area=…|hero|menu` [`button=secondary`]: the synthetic
///   mouse clicks it (`hero`: the hero's “详情”; `menu`: an open menu's
///   items), e.g. to open a work from where it is shown; `secondary` is a
///   right click.
/// - `section` `name=home|library|activity`; `open` / `play` [`workId=`]
///   (default: the hero); `escape`; `ask` (what ⌘K does).
/// - `detail` [`scroll=px`] [`season=N`] [`menu=true|false`]
///   [`seasons=true|false`] [`overview=true|false`]: the open detail page.
/// - `dilate` `factor=`: slow animations down (1 is normal), to capture a
///   transition mid-way.
/// - `popover` `which=tasks|nipa|none`.
/// - `chat` `open=true|false` [`about=<workId>`] [`thread=<id>|main` |
///   `new=true`]: the conversation where it is (the home expanded, the
///   side panel elsewhere), about a work, on a session, or a fresh one.
/// - `say` `text=`: say it in the conversation; `stop`: the stop button;
///   `choose` `label=` (an option of the question shown); `sessions`
///   `open=true|false`.
/// - `steps` [`turn=-1`] [`fold=open|closed`] [`group=N|all`]
///   [`open=true|false`] [`output=N`]: a turn's folded work, its step
///   groups, the N-th command's output.
/// - `transcript` `to=top|bottom|<px>`: scroll the conversation.
/// - `stall`: the running scripted turn has been silent for three minutes;
///   `quiet` `do=wait|resend` presses “再等等” / “重新发”.
/// - `new`: starts a new conversation, as “新的对话” in the sessions menu
/// - `type` `index=` `text=` [`submit=1`]: fills a field of the frontmost
///   page, then presses Return in it
/// - `login` `do=fake|open|cancel` [`platform=`]: a scripted login card
///   (fake opens NipaPlay's real login window on demand, no account), press
///   the first card's button, or cancel the scripted one.
/// - `reduce` `on=true|false|system`.
/// - `interface` `next=true|false`: “使用 Next 界面” on or off.
/// - `window` [`size=WxH` | `width=` `height=`] [`at=X,Y`]
///   [`maximize=true|false`] [`fullscreen=true|false`]: resize, move, zoom,
///   or enter / leave full screen without activating it.
/// - `chrome`: where the top bar's items are and where the traffic lights
///   end.
/// - `scroll` `to=px`: the page showing scrolls (its outermost scroller).
/// - `discover` [`day=0..6`] [`source=`] [`list=N`]: the 发现 page's tabs
///   (0 = Sunday), as tapping them would.
/// - `press` `label=` [`area=panel|discover|hero|dialog|…`]: the synthetic
///   mouse clicks the first visible button or menu item with that label;
///   `dialog` looks only in the window open over the page (a question).
/// - `drag` `target=panel|ask` [`do=enter|exit`] and `drop` `target=panel|ask`
///   `paths=a|b`: a file drag from Finder as the native drop plugin reports
///   it (entered → updated → performOperation), over the middle of the
///   panel or the home's input bar; nothing moves the OS pointer.
/// - `device` `name=` [`online=true|false`]: one of the scripted world's
///   other devices leaves or comes back (flips without `online`); the
///   interface hears it as a change.
/// - `library` [`workId=`]: the library as the interface reads it, where
///   each work is and whether its next episode plays; with `workId`, that
///   work's episodes.
/// - `lib` [`source=<id>`] [`form=shelves|cards`] [`arranged=true|false`]
///   [`menu=sources|sort|edit|none`] [`open=<categoryId>`] [`sort=<id>`]
///   [`move=<categoryId>,<index>`] [`remove=<categoryId>`]: the 片库 page,
///   as its controls would; returns what it shows.
/// - `settings` [`open=false`] [`section=<name>`] [`key=<setting>`]
///   [`query=`] [`more=true|false`] [`source=<id>|new|none`]
///   [`memory=<path>|none`] [`check=true`] [`advanced=true|false`]
///   [`scroll=px|end`] [`reload=true`], and for the scripted world
///   [`model=key|nokey|codex|nocodex`] [`mesh=online|offline|unavailable`]
///   [`account=<provider>:in|out`]: the settings page, opened as ⌘, opens
///   it, then as its rail, search and rows would; returns what it shows.
/// - `cat` [`sort=<id>`] [`scroll=top|end|<px>` [`ms=`]]: the category
///   page on top; a timed scroll also reports how long its frames took.
///   `scroll` takes `ms=` too, for the page showing.
/// - `search` [`open=true|false`] [`text=`] [`key=down|up|enter|escape,…`]
///   [`fail=library,online,sources,<source id>…|none`] [`clear=true`]
///   [`wait=ms`]: the search panel (what ⌘F opens), typed into as the
///   keyboard would (the debounce applies; `wait`, 300 by default, lets
///   groups answer before the keys), its keys, the scripted groups or
///   sources that fail (`sources`: their list; by default the unreachable
///   Emby), its recent terms cleared; returns what it shows.
/// - `manage` [`open=work|episode|none`] [`section=`] [`episode=N`]
///   [`tileMenu=N|none`] [`fail=read,search,…|none`] [`conflict=true`]
///   [`stale=true`] …: the detail page's management sheets (see
///   `WorkDetailDebug.debugManage`); `fail` makes the scripted world
///   refuse those operations, `stale` the next previewed match find
///   things changed.
/// - `batch` [`select=N|all`] [`menu=N`] [`open=refresh|match|unmatch`]
///   [`end=true`], then for the sheet up [`confirm=true`] [`provider=`]
///   [`expand=N|none`] [`pick=N:K|N:skip`] [`query=N:text`] [`back=true`]
///   [`wait=ms`], and for the scripted world
///   [`fault=refresh,conflict,bind,unbind|none`]: picking works on the
///   片库 page (or the category on top) and the batch sheets (see
///   `BatchDebug`, `BatchSheetDebug`).
abstract final class NextUiDebug {
  static NextShellController? _shell;
  static BuildContext? _context;
  static NextUiPreference? _preference;
  static bool _installed = false;
  static bool _pointerAdded = false;
  static const _device = 7701;

  static void attach(NextShellController shell, BuildContext context) {
    if (!NextUiDev.enabled) return;
    _shell = shell;
    _context = context;
    _preference = context.read<NextUiPreference>();
    if (_installed) return;
    _installed = true;
    registerExtension('ext.nipaplay.nextui', (_, params) async {
      try {
        final result = await _run(params);
        return ServiceExtensionResponse.result(jsonEncode(result));
      } catch (error) {
        return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError, error.toString());
      }
    });
  }

  static void detach(NextShellController shell) {
    if (identical(_shell, shell)) {
      _shell = null;
      _context = null;
    }
  }

  static Future<Map<String, Object?>> _run(Map<String, String> p) async {
    // These also work from Classic, once Next has been shown.
    switch (p['op']) {
      case 'interface':
        await _preference!.setEnabled(p['next'] != 'false');
        await _settle();
        return {'next': _preference!.enabled};
      case 'window':
        if (p['size'] case final size?) {
          final [w, h] = size.split('x').map(double.parse).toList();
          await windowManager.setSize(Size(w, h));
        } else if (p['width'] != null || p['height'] != null) {
          await windowManager.setSize(Size(double.parse(p['width'] ?? '1440'),
              double.parse(p['height'] ?? '900')));
        }
        if (p['at'] case final at?) {
          final [x, y] = at.split(',').map(double.parse).toList();
          await windowManager.setPosition(Offset(x, y));
        }
        if (p['maximize'] case final on?) {
          await (on == 'true'
              ? windowManager.maximize()
              : windowManager.unmaximize());
        }
        if (p['fullscreen'] case final on?) {
          await windowManager.setFullScreen(on == 'true');
        }
        await _settle();
        return {
          'size': (await windowManager.getSize()).toString(),
          'at': (await windowManager.getPosition()).toString(),
        };
      case 'chrome':
        await _settle();
        return _chrome();
    }
    final shell = _shell;
    if (shell == null) throw StateError('The Next shell is not showing');
    final c = shell.chat;
    switch (p['op']) {
      case 'status':
        break;
      case 'home':
        shell.go(NextSection.home);
        switch (p['state']) {
          case 'A':
            shell.foldHomeChat();
          case 'B':
            await _settle();
            unawaited(c.say(p['text'] ?? '来点轻松的'));
            shell.openChat();
          case 'C':
            shell.foldHomeChat();
            final chat = shell.services.chat;
            if (chat is! FakeChatPort) {
              throw StateError('C needs background work; only the scripted '
                  'chat can wake Nipa on demand');
            }
            chat.wake();
          default:
            throw ArgumentError('state must be A, B or C');
        }
      case 'fill':
        final text = p['text'] ?? '';
        shell.askText.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length));
      case 'send':
        final text = shell.askText.text;
        shell.askText.clear();
        unawaited(c.say(text));
        if (shell.onHome) shell.openChat();
      case 'say':
        unawaited(c.say(p['text'] ?? ''));
        if (shell.onHome) shell.openChat();
      case 'stop':
        unawaited(c.stop());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      case 'steps':
        final index = int.tryParse(p['turn'] ?? '-1') ?? -1;
        final turns = c.turns;
        if (turns.isEmpty) throw StateError('No turns');
        final turn = turns[index < 0 ? turns.length + index : index];
        if (p['fold'] case final fold?) turn.unfolded = fold == 'open';
        final groups = turn.parts.whereType<StepsPart>().toList();
        final which = p['group'];
        final open = p['open'];
        if (open != null) {
          for (final (i, g) in groups.indexed) {
            if (which == null || which == 'all' || int.tryParse(which) == i) {
              g.open = open == 'true';
            }
          }
        }
        if (int.tryParse(p['output'] ?? '') case final n?) {
          turn.steps.whereType<CommandStep>().toList()[n].outputShown = true;
        }
        // Rebuild what shows them.
        c.viewChanged();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      case 'transcript':
        final scroll = ChatTranscript.debugController;
        if (scroll == null || !scroll.hasClients) {
          throw StateError('No conversation is showing');
        }
        final max = scroll.position.maxScrollExtent;
        final to = switch (p['to']) {
          'top' => 0.0,
          'bottom' || null => max,
          final px => double.parse(px).clamp(0.0, max),
        };
        await scroll.animateTo(to,
            duration: const Duration(milliseconds: 300), curve: NextMotion.ease);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return {
          'offset': scroll.offset,
          'max': scroll.position.maxScrollExtent,
          ..._status(shell)
        };
      case 'hover':
        await _settle();
        return _hover(int.parse(p['index'] ?? '0'), p['area']);
      case 'tap':
        await _settle();
        final result = _hover(int.parse(p['index'] ?? '0'), p['area']);
        _click(result['at'] as List<int>,
            secondary: p['button'] == 'secondary');
        await _settle();
        return {...result, ..._status(shell)};
      case 'manage':
        final page = _detail();
        if (page == null) throw StateError('No detail page is showing');
        if (shell.services.manage case final FakeManage fake) {
          if (p['fail'] case final f?) {
            fake.fail
              ..clear()
              ..addAll(f == 'none' ? const [] : f.split(','));
          }
          if (p['conflict'] case final c?) fake.conflict = c == 'true';
          if (p['stale'] case final c?) fake.stale = c == 'true';
        }
        final result = await page.debugManage({...p}
          ..removeWhere(
              (k, _) => k == 'fail' || k == 'conflict' || k == 'stale'));
        await _settle();
        return {...result, ..._status(shell)};
      case 'detail':
        final page = _detail();
        if (page == null) throw StateError('No detail page is showing');
        if (p['season'] case final season?) {
          page.debugSeason(int.tryParse(season));
        }
        if (p['menu'] case final menu?) page.debugMenu(menu == 'true');
        if (p['overview'] case final open?) page.debugOverview(open == 'true');
        if (p['seasons'] case final open?) page.debugSeasons(open == 'true');
        if (p['scroll'] case final to?) {
          final scroll = page.debugScroll;
          await scroll.animateTo(
              double.parse(to).clamp(0, scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 400),
              curve: NextMotion.ease);
        }
        await _settle();
        return {...page.debugStatus(), ..._status(shell)};
      case 'dilate':
        timeDilation = double.parse(p['factor'] ?? '1');
      case 'section':
        shell.go(NextSection.values.byName(p['name'] ?? 'home'));
      case 'open':
        final id = p['workId'];
        final UiWork? work = id == null
            ? (await shell.services.data.home()).hero?.work
            : await shell.services.data.work(id);
        if (work == null) throw StateError('No such work');
        shell.openWork(work);
      case 'play':
        final id = p['workId'];
        final UiWork? work = id == null
            ? (await shell.services.data.home()).hero?.work
            : await shell.services.data.work(id);
        if (work == null) throw StateError('No such work');
        shell.play(work);
      case 'escape':
        shell.escape();
      case 'ask':
        shell.ask();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      case 'popover':
        final which = NextPopover.values.byName(p['which'] ?? 'none');
        if (which == NextPopover.none) {
          shell.closePopover();
        } else if (shell.popover != which) {
          shell.togglePopover(which);
        }
      case 'chat' || 'panel':
        final about = p['about'];
        final thread = p['thread'];
        if (p['open'] == 'false') {
          shell.closePanel();
          shell.foldHomeChat();
          break;
        }
        UiWork? work;
        if (about != null) {
          work = await shell.services.data.work(about);
          if (work == null) throw StateError('No such work');
        }
        shell.openChat(about: work);
        if (thread == 'main') {
          unawaited(c.selectMain());
        } else if (thread != null) {
          unawaited(c.select(thread));
        } else if (p['new'] == 'true') {
          c.startNew();
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      case 'choose':
        final label = p['label'];
        final q = c.questionItems.firstOrNull;
        if (q == null || label == null) throw StateError('No question');
        unawaited(c.choose(q['id'] as String, label));
      case 'new':
        // “新的对话” from the sessions menu.
        c.startNew();
        await _settle();
      case 'sessions':
        if ((p['open'] != 'false') != c.menuOpen) c.toggleMenu();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      case 'quiet':
        switch (p['do']) {
          case 'wait':
            c.keepWaiting();
          case 'resend':
            unawaited(c.resend());
          default:
            throw ArgumentError('do must be wait or resend');
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      case 'stall':
        final chat = shell.services.chat;
        if (chat is! FakeChatPort) {
          throw StateError('stall needs the scripted chat; use a silent '
              'model service with the real host');
        }
        chat.stall();
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      case 'login':
        final logins = shell.services.logins;
        switch (p['do']) {
          case 'fake':
            final stopped = Completer<void>();
            _fakeLoginStop = stopped;
            unawaited(logins.request<Object>(p['platform'] ?? '弹弹play',
                () => showAccountLogin({'provider': 'dandanplay'}, stopped.future),
                stopped.future));
          case 'open':
            final first = logins.pending.firstOrNull;
            if (first == null) throw StateError('No login waits');
            unawaited(logins.open(first));
          case 'cancel':
            final stop = _fakeLoginStop;
            if (stop != null && !stop.isCompleted) stop.complete();
          default:
            throw ArgumentError('do must be fake, open or cancel');
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      case 'scroll':
        final position = _find<ScrollableState>()?.position;
        if (position == null) throw StateError('Nothing scrolls here');
        final frames = await _scrollTimed(
            position, p['to'] ?? '0', int.tryParse(p['ms'] ?? ''));
        await _settle();
        return {
          'scroll': position.pixels,
          if (p['ms'] != null) 'frames': frames,
          ..._status(shell)
        };
      case 'discover':
        final page = _find<DiscoverDebug>();
        if (page == null) throw StateError('The 发现 page is not showing');
        page.debugChoose(
            day: int.tryParse(p['day'] ?? ''),
            source: p['source'],
            list: int.tryParse(p['list'] ?? ''));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return {...page.debugStatus(), ..._status(shell)};
      case 'type':
        // Text into the [index]th field of the frontmost page (a login
        // window), as typing would; the text is never echoed back.
        await _settle();
        final all = <EditableTextState>[];
        void visit(Element e) {
          if (e is StatefulElement && e.state is EditableTextState) {
            all.add(e.state as EditableTextState);
          }
          e.visitChildren(visit);
        }
        WidgetsBinding.instance.rootElement?.visitChildren(visit);
        // With a window open over the page (a dialog), only its fields: the
        // conversation's own field sits under it.
        bool inDialog(EditableTextState s) {
          final route = ModalRoute.of(s.context);
          return route is PopupRoute && route.isCurrent;
        }
        // area=dialog: a window must be open; never the conversation's field.
        if (p['area'] == 'dialog' && !all.any(inDialog)) {
          throw StateError('No window open');
        }
        final fields =
            all.any(inDialog) ? all.where(inDialog).toList() : all;
        final index = int.parse(p['index'] ?? '0');
        if (index >= fields.length) {
          throw StateError('${fields.length} fields on the front page');
        }
        final text = p['text'] ?? '';
        fields[index].widget.controller.value = TextEditingValue(
            text: text, selection: TextSelection.collapsed(offset: text.length));
        // Return, as the field handles it.
        if (p['submit'] == '1') fields[index].widget.onSubmitted?.call(text);
        await _settle();
        return {'fields': fields.length, ..._status(shell)};
      case 'guicall':
        // What the person does in the interface: an action called as the GUI
        // (a folder added in settings, not by Nipa). A failure comes back as
        // its facts, as the caller would read them.
        final input = p['input'];
        try {
          return {
            'result': await shell.services.calls.call(
                p['action']!,
                input == null
                    ? {}
                    : Map<String, Object?>.from(jsonDecode(input) as Map))
          };
        } on Failure catch (failure) {
          return {'failure': failure.toJson()};
        }
      case 'key':
        // A key pressed and let go, as the keyboard would.
        final (physical, logical) = switch (p['key']) {
          'space' => (PhysicalKeyboardKey.space, LogicalKeyboardKey.space),
          'left' => (PhysicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft),
          'right' =>
            (PhysicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowRight),
          'escape' => (PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape),
          _ => throw ArgumentError('key: space, left, right or escape'),
        };
        final stamp = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);
        final handled = HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(
            physicalKey: physical, logicalKey: logical, timeStamp: stamp));
        HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(
            physicalKey: physical, logicalKey: logical, timeStamp: stamp));
        await _settle();
        return {'handled': handled, ..._status(shell)};
      case 'click':
        // A click at x,y (logical pixels of the window); two with double.
        final [x, y] = p['at']!.split(',').map(int.parse).toList();
        _hoverAt(Offset(x.toDouble(), y.toDouble()));
        _click([x, y]);
        if (p['double'] == 'true') {
          await Future<void>.delayed(const Duration(milliseconds: 90));
          _click([x, y]);
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _settle();
        return {..._status(shell)};
      case 'press':
        await _settle();
        final label = p['label'] ?? '';
        final buttons = _pressables(label, p['area']);
        if (buttons.isEmpty) throw StateError('No visible “$label”');
        // Several of the same name (a tab and a button both “匹配”): index
        // picks one, in tree order.
        final index = int.parse(p['index'] ?? '0');
        if (index >= buttons.length) {
          throw RangeError('Only ${buttons.length} visible “$label”');
        }
        final at = _center(buttons[index]);
        _hoverAt(at);
        _click([at.dx.round(), at.dy.round()]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return {
          'at': [at.dx.round(), at.dy.round()],
          'matches': buttons.length,
          ..._status(shell)
        };
      case 'drag':
        final at = _dropPoint(p['target']);
        if (p['do'] == 'exit') {
          await _native('exited', null);
        } else {
          await _native('entered', [at.dx, at.dy]);
          await _native('updated', [at.dx, at.dy + 1]);
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return {
          'at': [at.dx.round(), at.dy.round()],
          'claimed': NextDropZones.claims(at),
          ..._status(shell)
        };
      case 'drop':
        final at = _dropPoint(p['target']);
        final paths = (p['paths'] ?? '').split('|').where((s) => s.isNotEmpty);
        await _native('entered', [at.dx, at.dy]);
        await _native('updated', [at.dx, at.dy + 1]);
        final claimed = NextDropZones.claims(at);
        await _native('performOperation_macos', [
          for (final path in paths) {'path': path}
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return {
          'at': [at.dx.round(), at.dy.round()],
          'claimed': claimed,
          ..._status(shell)
        };
      case 'device':
        final world = shell.services.data;
        if (world is! FakeWorld) {
          throw StateError('device needs the scripted world');
        }
        final devices = world.setOnline(p['name'] ?? '',
            switch (p['online']) { null => null, final on => on == 'true' });
        // Long enough for the pages to re-read.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return {'devices': devices, ..._status(shell)};
      case 'lib':
        final page = _find<LibraryDebug>();
        if (page == null) throw StateError('The 片库 page is not showing');
        await page.debug(p);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await _settle();
        return {...page.debugStatus(), ..._status(shell)};
      case 'cat':
        final page = _find<CategoryDebug>();
        if (page == null) throw StateError('No category page is showing');
        if (p['sort'] case final id?) page.debugSort(id);
        Map<String, Object?>? frames;
        if (p['scroll'] case final to?) {
          frames = await _scrollTimed(
              page.debugScroll.position, to, int.tryParse(p['ms'] ?? ''));
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await _settle();
        return {...page.debugStatus(), if (frames != null) 'frames': frames};
      case 'library':
        final data = shell.services.data;
        String where(UiDevice? d) =>
            d == null ? 'here' : '${d.name}${d.online ? '' : ' (offline)'}';
        if (p['workId'] case final id?) {
          return {
            'episodes': [
              for (final e in await data.episodes(id))
                '${e.season ?? '-'}/${e.number ?? '-'} ${where(e.device)}'
                    '${e.playable ? ' playable' : ''}'
            ],
          };
        }
        return {
          'works': [
            for (final w in await data.library())
              '${w.title} [${w.devices.map(where).join(', ')}] next '
                  '${w.next?.number} ${where(w.next?.device)}'
                  '${Words.canPlay(w) ? ' playable' : ''}'
          ],
        };
      case 'search':
        final search = shell.search;
        if (p['fail'] case final fail?) {
          final data = shell.services.search;
          if (data is! FakeSearch) {
            throw StateError('Only the scripted world fails on demand');
          }
          data.failing
            ..clear()
            ..addAll(fail == 'none' ? const [] : fail.split(','));
        }
        if (p['open'] == 'false') {
          shell.closeSearch();
        } else if (p['open'] == 'true' || p['text'] != null) {
          shell.openSearch();
        }
        if (p['clear'] == 'true') search.clearRecent();
        await _settle();
        if (p['text'] case final text?) {
          search.text.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length));
        }
        // The groups answer before the keys choose.
        await Future<void>.delayed(
            Duration(milliseconds: int.tryParse(p['wait'] ?? '') ?? 300));
        for (final key in (p['key'] ?? '').split(',')) {
          switch (key) {
            case 'down' || 'up':
              search.move(key == 'down' ? 1 : -1);
            case 'enter':
              final entry = await search.submit();
              if (entry != null) shell.openSearchEntry(entry);
            case 'escape':
              shell.escape();
            case '':
              break;
            default:
              throw ArgumentError('key must be down, up, enter or escape');
          }
          await _settle();
        }
        if (p['key'] != null) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        await _settle();
        return {..._status(shell), 'search': _search(shell)};
      case 'settings':
        final settings = shell.services.settings;
        Map<String, Object?>? world;
        if (const ['model', 'mesh', 'account', 'keys', 'remote', 'trusted',
          'remember', 'codex'].any(p.containsKey)) {
          if (settings is! FakeSettings) {
            throw StateError('model, mesh and account need the scripted world');
          }
          world = settings.scenario(p);
        }
        if (p['syncpass'] case final saved?) {
          final data = shell.services.data;
          if (data is! FakeWorld) throw StateError('Needs the scripted world');
          data.calls.syncPassword = saved == 'true';
        }
        if (p['open'] == 'false') {
          if (shell.settingsOpen) shell.navigatorKey.currentState?.pop();
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return _status(shell);
        }
        if (!shell.settingsOpen) {
          shell.openSettings(
              section: switch (p['section']) {
            null => null,
            final name => SettingsSection.values.byName(name),
          });
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final page = _find<SettingsDebug>();
        if (page == null) throw StateError('The settings page is not showing');
        await page.debug(p);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await _settle();
        return {...page.debugStatus(), ...?world, ..._status(shell)};
      // Y12: sheets, 动态, downloads, the scripted Actions.
      case 'sheet':
        if (p['close'] == 'true') NextSheetLayer.closeTop();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      case 'activity':
        if (shell.section != NextSection.activity) {
          shell.go(NextSection.activity);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        final page = _find<ActivityDebug>();
        if (page == null) throw StateError('动态 is not showing');
        await page.debug(p);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await _settle();
        return {...page.debugStatus(), ..._status(shell)};
      case 'downloads':
        final list = _find<DownloadListDebug>();
        if (list == null) throw StateError('The downloads are not showing');
        await list.debug(p);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await _settle();
        return {...list.debugStatus(), ..._status(shell)};
      case 'download':
        if (p['jobId'] case final id?) {
          unawaited(openDownload(shell.services, id));
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
        final sheet = _find<DownloadSheetDebug>();
        if (sheet == null) throw StateError('No download sheet is showing');
        await sheet.debug(p);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await _settle();
        return {...sheet.debugStatus(), ..._status(shell)};
      case 'newdl':
        if (_find<NewDownloadDebug>() == null) {
          unawaited(newDownload(shell.services,
              onSettings: () =>
                  shell.openSettings(section: SettingsSection.downloads)));
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final sheet = _find<NewDownloadDebug>()!;
        await sheet.debug(p);
        await Future<void>.delayed(
            Duration(milliseconds: int.tryParse(p['wait'] ?? '') ?? 1400));
        await _settle();
        return {...sheet.debugStatus(), ..._status(shell)};
      case 'history':
        if (shell.section != NextSection.activity) {
          shell.go(NextSection.activity);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        await _find<ActivityDebug>()?.debug(const {'tab': 'history'});
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final view = _find<HistoryDebug>();
        if (view == null) throw StateError('观看记录 is not showing');
        await view.debug(p);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await _settle();
        return {...view.debugStatus(), ..._status(shell)};
      case 'collection':
        final button = _find<CollectionDebug>();
        if (button == null) throw StateError('No collection button is showing');
        await button.debug(p);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await _settle();
        return {...button.debugStatus(), ..._status(shell)};
      case 'limits':
        unawaited(openLimits(shell.services));
        await Future<void>.delayed(const Duration(milliseconds: 700));
      case 'fake':
        final world = shell.services.data;
        if (world is! FakeWorld) throw StateError('Needs the scripted world');
        final calls = world.calls;
        if (p['fail'] case final fail?) {
          calls.failing
            ..clear()
            ..addAll(fail.split(',').where((a) => a.isNotEmpty));
        }
        if (p['limits'] case final mode?) calls.limitsMode = mode;
        if (p['ask'] == 'delete') calls.askToDelete();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return {
          'failing': calls.failing.toList(),
          'limits': calls.limitsMode,
          ..._status(shell)
        };
      // Y13: picking works in the library, doing things to them together.
      case 'batch':
        final world = shell.services.data;
        if (p['fault'] case final fault?) {
          if (world is! FakeWorld) throw StateError('Needs the scripted world');
          world.calls.batchFaults
            ..clear()
            ..addAll(
                fault.split(',').where((f) => f.isNotEmpty && f != 'none'));
        }
        final host = _find<BatchDebug>();
        if (host == null && _find<BatchSheetDebug>() == null) {
          throw StateError('No library grid is showing');
        }
        await host?.debug(p);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (p['open'] == null) {
          if (_find<BatchSheetDebug>() case final sheet?) {
            await sheet.debug(p);
            await Future<void>.delayed(Duration(
                milliseconds: int.tryParse(p['wait'] ?? '') ?? 900));
          }
        }
        await _settle();
        return {
          ...?host?.debugStatus(),
          if (_find<BatchSheetDebug>() case final sheet?)
            'sheet': sheet.debugStatus(),
          if (world is FakeWorld) 'faults': world.calls.batchFaults.toList(),
          ..._status(shell),
        };
      case 'reduce':
        NextMotion.forceReduced = switch (p['on']) {
          'true' => true,
          'false' => false,
          _ => null,
        };
        WidgetsBinding.instance.reassembleApplication();
      default:
        throw ArgumentError('Unknown op');
    }
    await _settle();
    return _status(shell);
  }

  static Future<void> _settle() => WidgetsBinding.instance.endOfFrame;

  /// Scrolls [position] to `top`, `end` or a pixel offset over [ms]
  /// (400 by default) and sums up the frames drawn meanwhile.
  static Future<Map<String, Object?>> _scrollTimed(
      ScrollPosition position, String to, int? ms) async {
    final target = switch (to) {
      'top' => 0.0,
      'end' => position.maxScrollExtent,
      final px => double.parse(px),
    }
        .clamp(0.0, position.maxScrollExtent);
    final frames = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> t) => frames.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    await position.animateTo(target,
        duration: Duration(milliseconds: ms ?? 400), curve: Curves.easeInOut);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    SchedulerBinding.instance.removeTimingsCallback(collect);
    double milli(Duration d) => d.inMicroseconds / 1000;
    final build = [for (final f in frames) milli(f.buildDuration)];
    final raster = [for (final f in frames) milli(f.rasterDuration)];
    double avg(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
    double most(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
    String r(double v) => v.toStringAsFixed(1);
    return {
      'count': frames.length,
      'buildAvgMs': r(avg(build)),
      'buildMaxMs': r(most(build)),
      'rasterAvgMs': r(avg(raster)),
      'rasterMaxMs': r(most(raster)),
      'over16ms': frames.where((f) => milli(f.totalSpan) > 16.7).length,
    };
  }
  static Completer<void>? _fakeLoginStop;

  static Map<String, Object?> _search(NextShellController shell) {
    final s = shell.search;
    String row(SearchEntry e) => switch (e) {
          RecentEntry(:final text) => text,
          WorkEntry(:final work, :final inLibrary) =>
            inLibrary ? '${work.title} (in library)' : work.title,
          final SourceEntry e => '${e.hit.kind.name} ${e.hit.title} '
              '(${e.hit.source.name}'
              '${e.hit.workTitle == null ? '' : ', ${e.hit.workTitle}'}'
              '${s.artworkOf(e) == null ? '' : ', pictured'}'
              '${e.hit.playable ? ', plays' : ''}'
              '${e.hit.reachable ? '' : ', unreachable'})',
          EpisodeEntry(:final work, :final episode) =>
            '${work.title} ${episode.number ?? ''} ${episode.title ?? ''}',
          NipaEntry(:final text) => 'nipa: $text',
        };
    return {
      'open': s.isOpen,
      'typed': s.typed,
      'query': s.query,
      'loading': s.loading,
      'nothingFound': s.nothingFound,
      'recent': s.recent,
      'selected': s.selected == null ? null : row(s.selected!),
      'groups': {
        for (final MapEntry(key: kind, value: g) in s.groups.entries)
          kind.name: {
            'state': g.state.name,
            'rows': [for (final e in s.shown(kind)) row(e)],
            if (g.unanswered.isNotEmpty) 'unanswered': g.unanswered,
          }
      },
    };
  }

  static Map<String, Object?> _status(NextShellController shell) {
    final c = shell.chat;
    String part(TurnPart p) => switch (p) {
          SaidPart(
            :final text,
            :final about,
            :final watched,
            :final files,
            :final echoed
          ) =>
            'you${echoed ? '' : ' (sending)'}: $text'
                '${about == null ? '' : ' (about $about)'}'
                '${watched == null ? '' : ' (watching $watched)'}'
                '${files.isEmpty ? '' : ' +files ${files.join(', ')}'}',
          ReplyPart(:final text) => 'nipa: $text',
          StepsPart() => 'steps${p.open ? ' (open)' : ''}: '
              '${ChatTurn.summary(p)}',
        };
    return {
      'section': shell.section.name,
      'popover': shell.popover.name,
      'sheets': NextSheetLayer.open,
      'nipaNeedsModel': shell.nipaSetup.needsModel,
      'panelOpen': shell.panelOpen.value,
      'homeChatOpen': shell.homeChatOpen.value,
      'visible': c.visible,
      'mood': c.mood.name,
      'unseen': c.unseen,
      'doing': c.doing,
      'line': c.doing ?? c.latestLine,
      'tasks': shell.activeTasks.length,
      'reduced': _context != null && _context!.mounted
          ? NextMotion.reduced(_context!)
          : null,
      'askText': shell.askText.text,
      'search': shell.search.isOpen ? shell.search.typed : null,
      'chat': {
        'main': c.main,
        'thread': c.thread,
        'onMain': c.onMain,
        'fresh': c.fresh,
        'title': c.title,
        'about': c.about?.title,
        'watched': c.watched,
        'loading': c.loading,
        'turns': [
          for (final t in c.turns)
            {
              'status': t.status,
              if (t.followup) 'followup': true,
              'elapsed': ChatTurn.span(t.elapsed()),
              if (t.foldable) 'folded': !t.unfolded,
              'parts': [
                for (final p in t.parts)
                  if (!t.folded(p)) part(p) else '(folded) ${part(p)}'
              ],
              if (t.cards.isNotEmpty) 'cards': t.cards.length,
            }
        ],
        'attachments': c.attachments,
        'underway': [for (final u in c.underway) '${u.title}: ${u.line}'],
        'running': c.running,
        'quiet': c.quiet,
        'question': c.question != null,
        'hint': c.hint,
        'sessions': [for (final s in c.sessions) s.title],
        'menuOpen': c.menuOpen,
        'logins': [for (final l in shell.services.logins.pending) l.platform],
        'trouble': c.trouble,
      },
    };
  }

  /// The first state of type [T] on a page that is showing.
  static T? _find<T>() {
    T? found;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is TickerMode && !widget.enabled) return;
      if (widget is Offstage && widget.offstage) return;
      if (element is StatefulElement && element.state is T) {
        found ??= element.state as T;
      }
      element.visitChildren(visit);
    }

    final context = _context;
    if (context == null || !context.mounted) return null;
    (context as Element).visitChildren(visit);
    return found;
  }

  /// Visible buttons and menu items labelled [label], optionally under the
  /// side panel or the 发现 page only.
  static List<RenderBox> _pressables(String label, String? area) {
    final found = <RenderBox>[];
    if (area == 'dialog') {
      // Questions open on the root navigator, outside the shell.
      void visit(Element element) {
        final widget = element.widget;
        if (widget is Pressable && widget.semanticLabel == label) {
          final route = ModalRoute.of(element);
          final box = element.findRenderObject();
          if (route is PopupRoute &&
              route.isCurrent &&
              box is RenderBox &&
              box.attached &&
              box.hasSize) {
            found.add(box);
          }
          return;
        }
        element.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
      return found;
    }
    final scope = switch (area) {
      'panel' || 'chat' => ChatFrame,
      'discover' => DiscoverPage,
      'search' => SearchLayer,
      'sheet' => NextSheetLayer,
      _ => null,
    };
    void visit(Element element, bool inArea) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is TickerMode && !widget.enabled) return;
      inArea = inArea || widget.runtimeType == scope;
      if (widget is Pressable && widget.semanticLabel == label && inArea) {
        final box = element.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) found.add(box);
        return;
      }
      element.visitChildren((child) => visit(child, inArea));
    }

    final context = _context;
    if (context == null || !context.mounted) return found;
    (context as Element).visitChildren((child) => visit(child, scope == null));
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    return found.where((b) => screen.contains(_center(b))).toList();
  }

  /// The middle of the side panel or of the home's input bar.
  static Offset _dropPoint(String? target) {
    final scope = switch (target) {
      'panel' => ChatPanelLayer,
      'ask' => AskBar,
      _ => throw ArgumentError('target must be panel or ask'),
    };
    RenderBox? box;
    void visit(Element element, bool inArea) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is TickerMode && !widget.enabled) return;
      inArea = inArea || widget.runtimeType == scope;
      if (widget is NextDropZone && inArea) {
        box ??= element.findRenderObject() as RenderBox?;
        return;
      }
      element.visitChildren((child) => visit(child, inArea));
    }

    (_context! as Element).visitChildren((child) => visit(child, false));
    if (box == null) throw StateError('No $target to drop on');
    return _center(box!);
  }

  /// A message from the native drop plugin, as Finder's drag produces it.
  static Future<void> _native(String method, Object? arguments) {
    final done = Completer<void>();
    ui.channelBuffers.push(
        'desktop_drop',
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, arguments)),
        (_) => done.complete());
    return done.future;
  }

  /// The synthetic mouse moves to [at] first, so hover effects follow.
  static void _hoverAt(Offset at) {
    final binding = GestureBinding.instance;
    final viewId = View.of(_context!).viewId;
    if (!_pointerAdded) {
      binding.handlePointerEvent(PointerAddedEvent(
          viewId: viewId,
          device: _device,
          kind: PointerDeviceKind.mouse,
          position: at));
      _pointerAdded = true;
    }
    binding.handlePointerEvent(PointerHoverEvent(
        viewId: viewId,
        device: _device,
        kind: PointerDeviceKind.mouse,
        position: at));
  }

  /// The detail page on top, if one is showing.
  static WorkDetailDebug? _detail() {
    WorkDetailDebug? found;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is TickerMode && !widget.enabled) return;
      if (element is StatefulElement && element.state is WorkDetailDebug) {
        found = element.state as WorkDetailDebug;
      }
      element.visitChildren(visit);
    }

    final context = _context;
    if (context == null || !context.mounted) return null;
    (context as Element).visitChildren(visit);
    return found;
  }

  /// Visible work cards in paint order, optionally under the stage, a
  /// shelf, the detail's episodes or the library only.
  static List<RenderBox> _cards(String? area) {
    final found = <RenderBox>[];
    final scope = switch (area) {
      'stage' || 'chat' => ChatFrame,
      'shelf' => Shelf,
      'episodes' => EpisodeRow,
      'library' => LibraryPage,
      'category' => CategoryPage,
      'discover' => DiscoverPage,
      'panel' => ChatPanelLayer,
      _ => null,
    };
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is TickerMode && !widget.enabled) return;
      final wanted = switch (area) {
        'avatar' => widget is NipaAvatar,
        'hero' => widget is NextButton && widget.label == '详情',
        'menu' => widget is MenuItem,
        _ => widget is WideCard ||
            widget is PosterCard ||
            widget is WorkRowCard ||
            widget is CategoryCard ||
            widget is FolderTile,
      };
      if (wanted) {
        final box = element.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          var inArea = scope == null;
          if (!inArea) {
            element.visitAncestorElements((a) {
              if (a.widget.runtimeType == scope) {
                inArea = true;
                return false;
              }
              return true;
            });
          }
          if (inArea) found.add(box);
        }
        return;
      }
      element.visitChildren(visit);
    }

    final context = _context;
    if (context == null || !context.mounted) return found;
    (context as Element).visitChildren(visit);
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    return found.where((b) => screen.contains(_center(b))).toList();
  }

  /// The top bar's items and the traffic lights' edge, in logical pixels.
  static Map<String, Object?> _chrome() {
    final items = <String, List<double>>{};
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      final box = element.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        final name = switch (widget) {
          RichText(:final text)
              when const {'首页', '发现', '片库', '动态'}
                  .contains(text.toPlainText()) =>
            text.toPlainText(),
          NipaAvatar() => 'avatar',
          NextIconButton() => 'search',
          _ => null,
        };
        if (name != null && rect.top < NextMetrics.topBar) {
          items[name] = [rect.left, rect.top, rect.width, rect.height]
              .map((v) => (v * 100).round() / 100)
              .toList();
        }
      }
      element.visitChildren(visit);
    }

    if (_context case final Element context? when context.mounted) {
      context.visitChildren(visit);
    }
    final layout = NextWindowChrome.layout.value;
    return {
      'leading': layout.leading,
      'fullScreen': layout.fullScreen,
      'items': items,
    };
  }

  static Offset _center(RenderBox box) =>
      box.localToGlobal(box.size.center(Offset.zero));

  /// A click of the synthetic mouse where it hovers (a right click with
  /// [secondary]).
  static void _click(List<int> at, {bool secondary = false}) {
    final binding = GestureBinding.instance;
    final viewId = View.of(_context!).viewId;
    final position = Offset(at[0].toDouble(), at[1].toDouble());
    binding.handlePointerEvent(PointerDownEvent(
        viewId: viewId,
        device: _device,
        kind: PointerDeviceKind.mouse,
        buttons: secondary ? kSecondaryMouseButton : kPrimaryButton,
        position: position));
    binding.handlePointerEvent(PointerUpEvent(
        viewId: viewId,
        device: _device,
        kind: PointerDeviceKind.mouse,
        position: position));
  }

  static Map<String, Object?> _hover(int index, String? area) {
    final binding = GestureBinding.instance;
    final viewId = View.of(_context!).viewId;
    if (index < 0) {
      if (_pointerAdded) {
        binding.handlePointerEvent(PointerRemovedEvent(
            viewId: viewId, device: _device, kind: PointerDeviceKind.mouse));
        _pointerAdded = false;
      }
      return {'hovered': false};
    }
    final cards = _cards(area);
    if (index >= cards.length) {
      throw RangeError('Only ${cards.length} visible cards');
    }
    final at = _center(cards[index]);
    if (!_pointerAdded) {
      binding.handlePointerEvent(PointerAddedEvent(
          viewId: viewId,
          device: _device,
          kind: PointerDeviceKind.mouse,
          position: at));
      _pointerAdded = true;
      // A freshly added device only enters regions once it moves.
      binding.handlePointerEvent(PointerHoverEvent(
          viewId: viewId,
          device: _device,
          kind: PointerDeviceKind.mouse,
          position: at + const Offset(1, 0)));
    }
    binding.handlePointerEvent(PointerHoverEvent(
        viewId: viewId,
        device: _device,
        kind: PointerDeviceKind.mouse,
        position: at));
    final hit = HitTestResult();
    RendererBinding.instance.hitTestInView(hit, at, viewId);
    return {
      'hovered': true,
      'cards': cards.length,
      'at': [at.dx.round(), at.dy.round()],
      'viewId': viewId,
      'mouseRegions':
          hit.path.where((e) => e.target is RenderMouseRegion).length,
    };
  }
}
