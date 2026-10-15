import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/progress.dart';
import 'batch_sheet.dart';
import 'category_grid.dart';
import 'selection.dart';

/// Handles for `ext.nipaplay.nextui` in lab profiles.
abstract interface class BatchDebug {
  /// Applies `end=true`, `select=N|all` (the first N tiles built, or
  /// everything 全选 would pick), `menu=N` (the Nth tile's right-click
  /// menu) and `open=refresh|match|unmatch`.
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

/// What a page leaves under its last row, for the bar of a picking
/// [SelectionHost] to float over without covering it.
const batchBarRoom = 108.0;

/// A page whose works can be picked together: the selection its tiles
/// read, their right-click menu, and while picking, the bar of what to do
/// with the picked works floating at the bottom. Esc ends picking.
class SelectionHost extends StatefulWidget {
  const SelectionHost({
    super.key,
    required this.selection,
    required this.child,
    this.everything,
  });

  final LibrarySelection selection;

  /// Every work the page shows, for 全选; null where it has none to give.
  final Future<List<UiWork>> Function()? everything;
  final Widget child;

  @override
  State<SelectionHost> createState() => _SelectionHostState();
}

class _SelectionHostState extends State<SelectionHost> implements BatchDebug {
  final _focus = FocusNode(debugLabel: 'library.selection');
  (UiWork, Offset)? _menu;
  bool _gathering = false;

  LibrarySelection get _selection => widget.selection;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_changed);
  }

  @override
  void didUpdateWidget(SelectionHost old) {
    super.didUpdateWidget(old);
    if (!identical(old.selection, widget.selection)) {
      old.selection.removeListener(_changed);
      widget.selection.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _selection.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (_selection.active && !_focus.hasFocus) _focus.requestFocus();
    setState(() {});
  }

  void _openMenu(UiWork work, Offset at) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(at);
    _focus.requestFocus();
    setState(() => _menu = (
          work,
          Offset(math.min(local.dx, box.size.width - 176),
              math.min(local.dy, box.size.height - 110)),
        ));
  }

  void _closeMenu() => setState(() => _menu = null);

  Future<void> _all() async {
    setState(() {
      _menu = null;
      _gathering = true;
    });
    try {
      _selection.add(await widget.everything!());
    } finally {
      if (mounted) setState(() => _gathering = false);
    }
  }

  Future<void> _open(BatchOp op) async {
    await openBatch(
        NextShellScope.of(context).services.batch, op, _selection.works);
    if (mounted && _selection.active) _focus.requestFocus();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_menu != null) {
        _closeMenu();
      } else if (_selection.active) {
        _selection.end();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    final keys = HardwareKeyboard.instance;
    if (_selection.active &&
        widget.everything != null &&
        event.logicalKey == LogicalKeyboardKey.keyA &&
        (keys.isMetaPressed || keys.isControlPressed)) {
      _all();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = _selection;
    final menu = _menu;
    return SelectionScope(
      selection: s,
      menu: _openMenu,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: Stack(children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Center(
              child: IgnorePointer(
                ignoring: !s.active,
                child: AnimatedSlide(
                  offset: Offset(0, s.active ? 0 : 0.6),
                  duration: const Duration(milliseconds: 280),
                  curve: NextMotion.ease,
                  child: AnimatedOpacity(
                    opacity: s.active ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: _Bar(
                      count: s.count,
                      gathering: _gathering,
                      onAll: widget.everything == null ? null : _all,
                      onOp: _open,
                      onEnd: s.end,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (menu case (final work, final at)) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenu,
                onSecondaryTap: _closeMenu,
              ),
            ),
            Positioned(
              left: at.dx,
              top: at.dy,
              child: MenuPanel(width: 168, children: [
                MenuItem(
                  label: s.contains(work) ? '取消选择' : '选择',
                  onTap: () {
                    _closeMenu();
                    s.toggle(work);
                  },
                ),
                if (widget.everything != null)
                  MenuItem(label: '全选', onTap: _all),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  // —— Debug ——

  List<Element> _tiles() {
    final found = <Element>[];
    void visit(Element e) {
      if (e.widget is WorkTile) {
        found.add(e);
        return;
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  Future<void> debug(Map<String, String> p) async {
    if (p['end'] == 'true') _selection.end();
    switch (p['select']) {
      case null:
        break;
      case 'all':
        await _all();
      case final n:
        _selection
          ..end()
          ..add([
            for (final e in _tiles().take(int.parse(n)))
              (e.widget as WorkTile).work
          ]);
    }
    if (p['menu'] case final n?) {
      final tile = _tiles()[int.parse(n)];
      final box = tile.findRenderObject()! as RenderBox;
      _openMenu((tile.widget as WorkTile).work,
          box.localToGlobal(box.size.center(Offset.zero)));
    }
    if (p['open'] case final op?) unawaited(_open(BatchOp.values.byName(op)));
  }

  @override
  Map<String, Object?> debugStatus() => {
        'picking': _selection.active,
        'picked': [for (final w in _selection.works) w.title],
        'menu': _menu?.$1.title,
        'canPickAll': widget.everything != null,
      };
}

/// What to do with the picked works, how many there are, and the way out.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.count,
    required this.gathering,
    required this.onAll,
    required this.onOp,
    required this.onEnd,
  });

  final int count;
  final bool gathering;
  final VoidCallback? onAll;
  final ValueChanged<BatchOp> onOp;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Glass(
        blur: 30,
        color: const Color(0xC2121218),
        borderColor: const Color(0x1FFFFFFF),
        radius: BorderRadius.circular(24),
        shadows: const [
          BoxShadow(
              color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 20))
        ],
        padding: const EdgeInsets.fromLTRB(20, 6, 6, 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('已选', style: NextText.sans(13, color: NextColors.p3)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 30),
            child: Text('$count',
                maxLines: 1,
                style: NextText.num(15, weight: FontWeight.w600)),
          ),
          if (onAll != null)
            gathering
                ? const SizedBox(
                    width: 58, child: Center(child: ThinkingDots(size: 4)))
                : _BarButton(label: '全选', onTap: onAll),
          const _Rule(),
          for (final op in BatchOp.values)
            _BarButton(
                label: op.label, onTap: count == 0 ? null : () => onOp(op)),
          const _Rule(),
          NextIconButton(glyph: NextGlyph.close, label: '取消', onTap: onEnd),
        ]),
      );
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.97,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered && onTap != null
                ? const Color(0x17FFFFFF)
                : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(label,
              style: NextText.sans(13.5,
                  weight: FontWeight.w500,
                  color: onTap == null ? NextColors.p4 : NextColors.paper)),
        ),
      );
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: NextColors.line2,
      );
}
