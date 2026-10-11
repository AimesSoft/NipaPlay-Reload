import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../home/stage.dart';
import '../shell/next_ui_preference.dart';
import '../shell/shell_controller.dart';
import '../shell/window_chrome.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
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
/// - `hover` `index=N` [`area=stage|shelf|avatar`]: a synthetic mouse hovers the
///   N-th visible card (no OS pointer moves); `index=-1` leaves.
/// - `section` `name=home|library|activity`; `open` / `play` [`workId=`]
///   (default: the hero); `escape`.
/// - `popover` `which=tasks|nipa|none`; `panel` `open=true|false`.
/// - `reduce` `on=true|false|system`.
/// - `interface` `next=true|false`: “使用 Next 界面” on or off.
/// - `window` [`size=WxH`] [`maximize=true|false`] [`fullscreen=true|false`]:
///   resize, zoom, or enter / leave full screen without activating it.
/// - `chrome`: where the top bar's items are and where the traffic lights
///   end.
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

  /// Visible work cards in paint order, optionally under the stage or a
  /// shelf only.
  static List<RenderBox> _cards(String? area) {
    final found = <RenderBox>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      final wanted = area == 'avatar'
          ? widget is NipaAvatar
          : (widget is WideCard ||
              widget is PosterCard ||
              widget is WorkRowCard);
      if (wanted) {
        final box = element.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          var inArea = area == null || area == 'avatar';
          if (!inArea) {
            element.visitAncestorElements((a) {
              if ((area == 'stage' && a.widget is ConverseStage) ||
                  (area == 'shelf' && a.widget is Shelf)) {
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
              when const {'首页', '片库', '动态'}.contains(text.toPlainText()) =>
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
