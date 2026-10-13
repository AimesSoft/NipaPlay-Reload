import 'dart:math' as math;

import 'package:flutter/material.dart' show ReorderableListView;
import 'package:flutter/widgets.dart';

import '../../ui_data/library.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/nipa_avatar.dart';
import 'fan_cover.dart';

/// The ⋯ panel: the page's categories, to drag into order or take away,
/// and Nipa for anything more.
class CategoryEditor extends StatefulWidget {
  const CategoryEditor({
    super.key,
    required this.categories,
    required this.onMove,
    required this.onRemove,
    required this.onAskNipa,
    this.original = false,
  });

  final List<UiCategory> categories;

  /// The source's own structure: taking a category away only hides it
  /// here; nothing on the server or share changes.
  final bool original;
  final void Function(String categoryId, int index) onMove;
  final void Function(String categoryId) onRemove;
  final VoidCallback onAskNipa;

  static const _row = 44.0;

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  /// Shown at once as dragged or removed; the page's next read agrees.
  late List<UiCategory> _order = [...widget.categories];

  @override
  void didUpdateWidget(CategoryEditor old) {
    super.didUpdateWidget(old);
    if (!identical(old.categories, widget.categories)) {
      _order = [...widget.categories];
    }
  }

  void _reorder(int from, int target) {
    final moved = _order[from];
    setState(() => _order
      ..removeAt(from)
      ..insert(target, moved));
    widget.onMove(moved.categoryId, target);
  }

  void _remove(UiCategory c) {
    setState(() => _order.remove(c));
    widget.onRemove(c.categoryId);
  }

  @override
  Widget build(BuildContext context) {
    final several = _order.length > 1;
    return MenuPanel(width: 300, children: [
      SizedBox(
        height: math.min(_order.length, 8) * CategoryEditor._row,
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: _order.length,
          onReorderItem: _reorder,
          proxyDecorator: (child, index, animation) => DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF21C1C24),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 6)),
              ],
            ),
            child: child,
          ),
          itemBuilder: (context, i) {
            final c = _order[i];
            return SizedBox(
              key: ValueKey(c.categoryId),
              height: CategoryEditor._row,
              child: Row(children: [
                if (several)
                  ReorderableDragStartListener(
                    index: i,
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: SizedBox(
                        width: 34,
                        height: CategoryEditor._row,
                        child: Center(
                          child: NextIcon(NextGlyph.grip,
                              size: 16, color: NextColors.p3),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                    child: CategoryName(
                        title: c.title, count: c.count, size: 13.5)),
                if (several)
                  NextIconButton(
                    glyph: NextGlyph.close,
                    size: 30,
                    label: widget.original ? '隐藏' : '移除',
                    onTap: () => _remove(c),
                  ),
                const SizedBox(width: 4),
              ]),
            );
          },
        ),
      ),
      Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        color: NextColors.line,
      ),
      MenuItem(
        label: '让 Nipa 整理',
        onTap: widget.onAskNipa,
        trailing: const NipaAvatar(size: 20),
      ),
    ]);
  }
}
