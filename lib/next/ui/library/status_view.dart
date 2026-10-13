import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/library.dart';
import '../../ui_data/ui_data.dart';
import '../data/collections.dart';
import '../data/gui_calls.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import 'category_grid.dart';

/// The library's works the person marked [status] on their accounts, as
/// the library's grid of posters (a sliver). Read again when the library
/// or a standing changes.
class StatusView extends StatefulWidget {
  const StatusView({super.key, required this.status, required this.on});
  final UiWatchStatus status;
  final LibraryCallbacks on;

  @override
  State<StatusView> createState() => _StatusViewState();
}

class _StatusViewState extends State<StatusView> {
  NextShellController? _shell;
  final _changes = <StreamSubscription<void>>[];
  List<UiWork>? _works;
  String? _said;
  int _reads = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell = shell;
    for (final c in _changes) {
      c.cancel();
    }
    _changes
      ..clear()
      ..add(shell.services.data.changes.listen((_) => _load()))
      ..add(shell.services.collections.changes.listen((_) => _load()));
    _load();
  }

  @override
  void didUpdateWidget(StatusView old) {
    super.didUpdateWidget(old);
    if (old.status == widget.status) return;
    _works = null;
    _said = null;
    _load();
  }

  @override
  void dispose() {
    for (final c in _changes) {
      c.cancel();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final read = ++_reads;
    final services = _shell!.services;
    try {
      final ids = await services.collections.works(widget.status) ?? const [];
      final works = await Future.wait(ids.map(services.data.work));
      if (!mounted || read != _reads) return;
      setState(() {
        _works = works.whereType<UiWork>().toList();
        _said = null;
      });
    } catch (error) {
      if (!mounted || read != _reads) return;
      setState(() => _said = callFailure(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final works = _works;
    final said = _said ?? (works != null && works.isEmpty ? '这里还空着。' : null);
    return SliverAnimatedOpacity(
      opacity: works == null && said == null ? 0 : 1,
      duration: const Duration(milliseconds: 280),
      sliver: switch ((said, works)) {
        (final said?, _) => SliverPadding(
            padding: const EdgeInsets.only(left: NextMetrics.gutter),
            sliver: SliverToBoxAdapter(
              child:
                  Text(said, style: NextText.sans(14.5, color: NextColors.p3)),
            ),
          ),
        (null, final works?) => _grid(works),
        (null, null) => const SliverToBoxAdapter(),
      },
    );
  }

  Widget _grid(List<UiWork> works) {
    final deviceLine = works.any((w) => w.devices.isNotEmpty);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(NextMetrics.gutter, 0, 56, 64),
      sliver: SliverLayoutBuilder(builder: (context, constraints) {
        const gap = CategoryGrid.gap;
        final width = constraints.crossAxisExtent;
        final columns = ((width + gap) / (CategoryGrid.maxTile + gap)).ceil();
        final tile = (width - gap * (columns - 1)) / columns;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 28,
            crossAxisSpacing: gap,
            // Poster, title, and the device line when there may be one.
            mainAxisExtent: tile * 3 / 2 + 12 + 22 + (deviceLine ? 21 : 0),
          ),
          itemCount: works.length,
          itemBuilder: (context, i) =>
              libraryTile(UiWorkItem(works[i]), tile, widget.on),
        );
      }),
    );
  }
}
