import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/words.dart';

/// 片库. The data contract has no library listing yet, so this shows every
/// work the home knows about, as posters.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<UiWork> _works = const [];
  StreamSubscription<void>? _changes;
  NextShellController? _shell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell = shell;
    _changes?.cancel();
    _changes = shell.services.data.changes.listen((_) => _load());
    _load();
  }

  Future<void> _load() async {
    final home = await _shell!.services.data.home();
    final seen = <String>{};
    final works = <UiWork>[
      if (home.hero != null && seen.add(home.hero!.work.workId))
        home.hero!.work,
      for (final shelf in home.shelves)
        for (final item in shelf.items)
          if (seen.add(item.work.workId)) item.work,
    ];
    if (mounted) setState(() => _works = works);
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = _shell!;
    return CustomScrollView(
      key: const PageStorageKey('library'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              NextMetrics.gutter, NextMetrics.topBar + 40, 56, 28),
          sliver: SliverToBoxAdapter(
            child:
                Text('片库', style: NextText.sans(28, weight: FontWeight.w600)),
          ),
        ),
        if (_works.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(left: NextMetrics.gutter),
            sliver: SliverToBoxAdapter(
              child: Text('这里还空着。',
                  style: NextText.sans(14.5, color: NextColors.p3)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(NextMetrics.gutter, 0, 56, 64),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 196,
                mainAxisSpacing: 28,
                crossAxisSpacing: 20,
                childAspectRatio: 176 / 300,
              ),
              delegate: SliverChildBuilderDelegate(
                childCount: _works.length,
                (context, i) {
                  final work = _works[i];
                  return LayoutBuilder(
                    builder: (context, c) => PosterCard(
                      workId: work.workId,
                      image: work.artwork.poster,
                      tint: work.artwork.tint,
                      title: work.title,
                      width: c.maxWidth,
                      height: c.maxWidth * 3 / 2,
                      onOpen: () => shell.openWork(work),
                      onPlay:
                          Words.canPlay(work) ? () => shell.play(work) : null,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
