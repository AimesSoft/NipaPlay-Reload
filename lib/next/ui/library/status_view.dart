import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/library.dart';
import '../../ui_data/ui_data.dart';
import '../data/collections.dart';
import '../data/gui_calls.dart';
import '../settings/controls.dart' show PillButton;
import '../shell/shell_controller.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import 'batch_bar.dart' show batchBarRoom;
import 'category_grid.dart';

/// The library's works the person marked [status] on their accounts, as
/// the library's grid of posters (a sliver), or the accounts to sign in to
/// when none is. Read again when the library, a standing or the accounts
/// change.
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

  /// No account is signed in to list by.
  bool _signedOut = false;
  String? _signing;

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
      ..add(shell.services.collections.changes.listen((_) => _load()))
      // Signing in or out changes which account lists.
      ..add(shell.services.settings.changes.listen((_) => _load()));
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
      final ids = await services.collections.works(widget.status);
      final works = await Future.wait((ids ?? const []).map(services.data.work));
      if (!mounted || read != _reads) return;
      // Bindings of one work on several devices are one work here.
      final seen = <String>{};
      setState(() {
        _signedOut = ids == null;
        _works = [
          for (final w in works.whereType<UiWork>())
            if (seen.add(w.workId)) w
        ];
        _said = null;
      });
    } catch (error) {
      if (!mounted || read != _reads) return;
      setState(() => _said = callFailure(error));
    }
  }

  Future<void> _login(String provider) async {
    setState(() {
      _signing = provider;
      _said = null;
    });
    try {
      await _shell!.services.settings.login(provider);
    } catch (error) {
      if (mounted) setState(() => _said = callFailure(error));
    }
    if (mounted) setState(() => _signing = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_signedOut) {
      return SliverPadding(
        padding: EdgeInsets.only(left: NextLayout.gutter(context)),
        sliver: SliverToBoxAdapter(
          child: Row(children: [
            for (final (provider, name) in const [
              ('bangumi', 'Bangumi'),
              ('dandanplay', '弹弹play'),
            ]) ...[
              PillButton(
                label: '登录 $name',
                busy: _signing == provider,
                onTap: _signing == null ? () => _login(provider) : null,
              ),
              const SizedBox(width: 10),
            ],
            if (_said != null)
              Text(_said!, style: NextText.sans(12, color: NextColors.amber)),
          ]),
        ),
      );
    }
    final works = _works;
    final said = _said ?? (works != null && works.isEmpty ? '这里还空着。' : null);
    return SliverAnimatedOpacity(
      opacity: works == null && said == null ? 0 : 1,
      duration: const Duration(milliseconds: 280),
      sliver: switch ((said, works)) {
        (final said?, _) => SliverPadding(
            padding: EdgeInsets.only(left: NextLayout.gutter(context)),
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
      padding: EdgeInsets.fromLTRB(
          NextLayout.gutter(context), 0, NextLayout.end(context), batchBarRoom),
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
