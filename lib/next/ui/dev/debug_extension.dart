import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../detail/detail_page.dart';
import '../detail/episodes.dart';
import '../home/stage.dart';
import '../pages/library_page.dart';
import '../shell/shell_controller.dart';
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
/// - `home` `state=A|B|C` [`text=`]: A leaves the stage; B says [text]
///   (default “来点轻松的”); C wakes Nipa (scripted chat only).
/// - `fill` `text=`: put text in the input bar without sending; `send`.
/// - `hover` `index=N` [`area=stage|shelf|avatar|episodes|library`]: a
///   synthetic mouse hovers the N-th visible card (no OS pointer moves);
///   `index=-1` leaves.
/// - `tap` `index=N` `area=…|hero|menu`: the synthetic mouse clicks it
///   (`hero`: the hero's “详情”; `menu`: an open menu's items), e.g. to open
///   a work from where it is shown.
/// - `section` `name=home|library|activity`; `open` / `play` [`workId=`]
///   (default: the hero); `escape`.
/// - `detail` [`scroll=px`] [`season=N`] [`menu=true|false`]
///   [`seasons=true|false`] [`overview=true|false`]: the open detail page.
/// - `window` `width=` `height=`: resize the window (it is not activated).
/// - `dilate` `factor=`: slow animations down (1 is normal), to capture a
///   transition mid-way.
/// - `popover` `which=tasks|nipa|none`; `panel` `open=true|false`.
/// - `reduce` `on=true|false|system`.
abstract final class NextUiDebug {
  static NextShellController? _shell;
  static BuildContext? _context;
  static bool _installed = false;
  static bool _pointerAdded = false;
  static const _device = 7701;

  static void attach(NextShellController shell, BuildContext context) {
    if (!NextUiDev.enabled) return;
    _shell = shell;
    _context = context;
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
    final shell = _shell;
    if (shell == null) throw StateError('The Next shell is not showing');
    final c = shell.conversation;
    switch (p['op']) {
      case 'status':
        break;
      case 'home':
        shell.go(NextSection.home);
        switch (p['state']) {
          case 'A':
            c.dismiss();
          case 'B':
            await _settle();
            unawaited(c.say(p['text'] ?? '来点轻松的'));
          case 'C':
            c.dismiss();
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
        shell.go(NextSection.home);
        final text = p['text'] ?? '';
        shell.askFocus.requestFocus();
        await _settle();
        shell.askText.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length));
      case 'send':
        final text = shell.askText.text;
        shell.askText.clear();
        unawaited(c.say(text));
      case 'hover':
        await _settle();
        return _hover(int.parse(p['index'] ?? '0'), p['area']);
      case 'tap':
        await _settle();
        final result = _hover(int.parse(p['index'] ?? '0'), p['area']);
        _click(result['at'] as List<int>);
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
      case 'window':
        await windowManager.setSize(Size(double.parse(p['width'] ?? '1440'),
            double.parse(p['height'] ?? '900')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final size = await windowManager.getSize();
        return {'width': size.width, 'height': size.height};
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
      case 'popover':
        final which = NextPopover.values.byName(p['which'] ?? 'none');
        if (which == NextPopover.none) {
          shell.closePopover();
        } else if (shell.popover != which) {
          shell.togglePopover(which);
        }
      case 'panel':
        if (p['open'] == 'false') {
          shell.closePanel();
        } else {
          shell.openPanel();
        }
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

  static Map<String, Object?> _status(NextShellController shell) {
    final c = shell.conversation;
    return {
      'section': shell.section.name,
      'popover': shell.popover.name,
      'panelOpen': shell.panelOpen.value,
      'staged': c.staged,
      'mood': c.mood.name,
      'unseen': c.unseen,
      'said': c.said,
      'reply': c.reply,
      'cards': c.cards.length,
      'line': c.backgroundActive ? c.activity : c.latestLine,
      'tasks': shell.activeTasks.length,
      'reduced': _context != null && _context!.mounted
          ? NextMotion.reduced(_context!)
          : null,
      'askText': shell.askText.text,
    };
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
      'stage' => ConverseStage,
      'shelf' => Shelf,
      'episodes' => EpisodeRow,
      'library' => LibraryPage,
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

  static Offset _center(RenderBox box) =>
      box.localToGlobal(box.size.center(Offset.zero));

  /// A primary click of the synthetic mouse where it hovers.
  static void _click(List<int> at) {
    final binding = GestureBinding.instance;
    final viewId = View.of(_context!).viewId;
    final position = Offset(at[0].toDouble(), at[1].toDouble());
    binding.handlePointerEvent(PointerDownEvent(
        viewId: viewId,
        device: _device,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
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
