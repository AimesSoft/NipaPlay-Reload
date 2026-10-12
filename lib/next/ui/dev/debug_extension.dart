import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../accounts/login_dialog.dart';
import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../chat/chat_frame.dart';
import '../chat/transcript.dart';
import '../conversation/nipa_chat.dart';
import '../detail/detail_page.dart';
import '../detail/episodes.dart';
import '../home/ask_bar.dart';
import '../pages/discover_page.dart';
import '../panel/chat_panel.dart';
import '../widgets/drop_zone.dart';
import '../shell/next_ui_preference.dart';
import '../pages/library_page.dart';
import '../shell/shell_controller.dart';
import '../shell/window_chrome.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/menu.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/shelf.dart';
import 'dev_services.dart';
import 'fake_world.dart';

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
/// - `login` `do=fake|open|cancel` [`platform=`]: a scripted login card
///   (fake opens NipaPlay's real login window on demand, no account), press
///   the first card's button, or cancel the scripted one.
/// - `reduce` `on=true|false|system`.
/// - `interface` `next=true|false`: “使用 Next 界面” on or off.
/// - `window` [`size=WxH` | `width=` `height=`] [`maximize=true|false`]
///   [`fullscreen=true|false`]:
///   resize, zoom, or enter / leave full screen without activating it.
/// - `chrome`: where the top bar's items are and where the traffic lights
///   end.
/// - `scroll` `to=px`: the page showing scrolls (its outermost scroller).
/// - `discover` [`day=0..6`] [`source=`] [`list=N`]: the 发现 page's tabs
///   (0 = Sunday), as tapping them would.
/// - `press` `label=` [`area=panel|discover|hero|…`]: the synthetic mouse
///   clicks the first visible button or menu item with that label.
/// - `drag` `target=panel|ask` [`do=enter|exit`] and `drop` `target=panel|ask`
///   `paths=a|b`: a file drag from Finder as the native drop plugin reports
///   it (entered → updated → performOperation), over the middle of the
///   panel or the home's input bar; nothing moves the OS pointer.
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
        if (p['maximize'] case final on?) {
          await (on == 'true'
              ? windowManager.maximize()
              : windowManager.unmaximize());
        }
        if (p['fullscreen'] case final on?) {
          await windowManager.setFullScreen(on == 'true');
        }
        await _settle();
        return {'size': (await windowManager.getSize()).toString()};
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
        await position.animateTo(
            double.parse(p['to'] ?? '0').clamp(0, position.maxScrollExtent),
            duration: const Duration(milliseconds: 400),
            curve: NextMotion.ease);
        await _settle();
        return {'scroll': position.pixels, ..._status(shell)};
      case 'discover':
        final page = _find<DiscoverDebug>();
        if (page == null) throw StateError('The 发现 page is not showing');
        page.debugChoose(
            day: int.tryParse(p['day'] ?? ''),
            source: p['source'],
            list: int.tryParse(p['list'] ?? ''));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return {...page.debugStatus(), ..._status(shell)};
      case 'press':
        await _settle();
        final label = p['label'] ?? '';
        final buttons = _pressables(label, p['area']);
        if (buttons.isEmpty) throw StateError('No visible “$label”');
        final at = _center(buttons.first);
        _hoverAt(at);
        _click([at.dx.round(), at.dy.round()]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return {'at': [at.dx.round(), at.dy.round()], ..._status(shell)};
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
  static Completer<void>? _fakeLoginStop;

  static Map<String, Object?> _status(NextShellController shell) {
    final c = shell.chat;
    String part(TurnPart p) => switch (p) {
          SaidPart(:final text, :final about, :final files, :final echoed) =>
            'you${echoed ? '' : ' (sending)'}: $text'
                '${about == null ? '' : ' (about $about)'}'
                '${files.isEmpty ? '' : ' +files ${files.join(', ')}'}',
          ReplyPart(:final text) => 'nipa: $text',
          StepsPart() => 'steps${p.open ? ' (open)' : ''}: '
              '${ChatTurn.summary(p)}',
        };
    return {
      'section': shell.section.name,
      'popover': shell.popover.name,
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
      'chat': {
        'main': c.main,
        'thread': c.thread,
        'onMain': c.onMain,
        'fresh': c.fresh,
        'title': c.title,
        'about': c.about?.title,
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
        'nextSayings': c.nextSayings,
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
    final scope = switch (area) {
      'panel' || 'chat' => ChatFrame,
      'discover' => DiscoverPage,
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
        _ =>
          widget is WideCard || widget is PosterCard || widget is WorkRowCard,
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
