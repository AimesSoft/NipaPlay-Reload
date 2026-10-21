import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/search.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/devices.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/words.dart';
import 'search_controller.dart';

/// The search panel over everything (⌘F, the top bar's search): the box,
/// then 片库 · 在线 · 来源 as each answers, then Nipa. ↑↓ choose, ↵ opens,
/// Esc or a click outside closes.
class SearchLayer extends StatefulWidget {
  const SearchLayer(
      {super.key,
      required this.search,
      required this.onOpen,
      required this.onClose});
  final NextSearch search;

  /// A row was chosen (click or ↵).
  final ValueChanged<SearchEntry> onOpen;

  /// Esc, or a click outside.
  final VoidCallback onClose;

  @override
  State<SearchLayer> createState() => _SearchLayerState();
}

class _SearchLayerState extends State<SearchLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 140));
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _show, curve: NextMotion.ease);
  FocusNode? _before;
  bool _wasOpen = false;

  NextSearch get _search => widget.search;

  @override
  void initState() {
    super.initState();
    _search.addListener(_changed);
    if (_search.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _changed();
      });
    }
  }

  @override
  void didUpdateWidget(SearchLayer old) {
    super.didUpdateWidget(old);
    if (identical(old.search, widget.search)) return;
    old.search.removeListener(_changed);
    widget.search.addListener(_changed);
  }

  void _changed() {
    final open = _search.isOpen;
    if (open == _wasOpen) return;
    _wasOpen = open;
    if (open) {
      final focused = FocusManager.instance.primaryFocus;
      _before = identical(focused, _search.focus) ? null : focused;
      _show.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _search.isOpen) _search.focus.requestFocus();
      });
    } else {
      _show.reverse();
      final restore = _search.restoreFocus ? _before : null;
      _before = null;
      _search.focus.unfocus();
      if (restore != null && restore.context != null) restore.requestFocus();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _search.removeListener(_changed);
    _curve.dispose();
    _show.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Keys of an input method choosing characters are its own.
    final value = _search.text.value;
    if (value.composing.isValid && !value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _search.move(1);
      case LogicalKeyboardKey.arrowUp:
        _search.move(-1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        if (event is KeyDownEvent) _submit();
      case LogicalKeyboardKey.escape:
        widget.onClose();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool _submitting = false;

  /// ↵ once: a second press while the first waits for answers is dropped.
  Future<void> _submit() async {
    if (_submitting) return;
    _submitting = true;
    try {
      final entry = await _search.submit();
      if (entry != null && mounted && _search.isOpen) widget.onOpen(entry);
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _show,
      builder: (context, _) {
        if (_show.isDismissed) return const SizedBox.shrink();
        final size = MediaQuery.sizeOf(context);
        const top = NextMetrics.topBar + 36;
        final reduced = NextMotion.reduced(context);
        final t = _curve.value;
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: Opacity(
                opacity: _show.value,
                child: const ColoredBox(color: Color(0x9908080B)),
              ),
            ),
          ),
          Positioned(
            top: top,
            left: 0,
            right: 0,
            child: Center(
              child: Opacity(
                opacity: _show.value,
                child: Transform.translate(
                  offset: Offset(0, reduced ? 0 : (1 - t) * -10),
                  child: Transform.scale(
                    scale: reduced ? 1 : 0.98 + 0.02 * t,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (size.width - 48).clamp(320.0, 680.0),
                        maxHeight: (size.height - top - 48).clamp(120.0, 640.0),
                      ),
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: _key,
                        child: _Panel(
                            search: _search,
                            onOpen: widget.onOpen,
                            onSubmit: _submit),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel(
      {required this.search, required this.onOpen, required this.onSubmit});
  final NextSearch search;
  final ValueChanged<SearchEntry> onOpen;
  final VoidCallback onSubmit;

  static const _titles = {
    SearchGroupKind.library: '片库',
    SearchGroupKind.online: '在线',
    SearchGroupKind.sources: '来源',
  };

  @override
  Widget build(BuildContext context) => Glass(
        blur: 34,
        color: const Color(0xD912121A),
        borderColor: const Color(0x1FFFFFFF),
        radius: BorderRadius.circular(22),
        shadows: const [
          BoxShadow(
              color: Color(0x99000000), blurRadius: 70, offset: Offset(0, 28)),
        ],
        child: ListenableBuilder(
          listenable: search,
          builder: (context, _) {
            final rows = _rows();
            final nipa = search.entries.lastOrNull;
            final footer = search.typed.isNotEmpty && nipa is NipaEntry;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Input(search: search, onSubmit: onSubmit),
                SizedBox(
                  height: 1,
                  child: search.loading
                      ? const _Sweep()
                      : ColoredBox(
                          color: rows.isNotEmpty || footer
                              ? NextColors.line
                              : const Color(0x00000000)),
                ),
                Flexible(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: NextMotion.ease,
                    alignment: Alignment.topCenter,
                    child: rows.isEmpty
                        ? const SizedBox(width: double.infinity)
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: rows,
                            ),
                          ),
                  ),
                ),
                // Nipa, last and always in reach.
                if (footer) ...[
                  if (rows.isNotEmpty)
                    const SizedBox(
                        height: 1, child: ColoredBox(color: NextColors.line)),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _row(nipa),
                  ),
                ],
              ],
            );
          },
        ),
      );

  Widget _row(SearchEntry e) => _Row(
        key: ValueKey(e.key),
        entry: e,
        selected: e.key == search.selected?.key,
        search: search,
        onOpen: onOpen,
      );

  /// The recent terms, or each group's answer; what is not there says
  /// nothing, except a failed group (or source) and an empty search, in one
  /// quiet line.
  List<Widget> _rows() {
    if (search.typed.isEmpty) {
      if (search.recent.isEmpty) return const [];
      return [
        _Heading('最近', trailing: _QuietButton('清除', onTap: search.clearRecent)),
        ...search.entries.map(_row),
      ];
    }
    final rows = <Widget>[];
    for (final MapEntry(key: kind, value: group) in search.groups.entries) {
      final shown = search.shown(kind);
      if (shown.isNotEmpty || group.unanswered.isNotEmpty) {
        rows.add(_Heading(_titles[kind]!));
        if (shown.isNotEmpty) {
          rows.add(AnimatedOpacity(
            opacity: group.loading ? 0.5 : 1,
            duration: const Duration(milliseconds: 160),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: shown.map(_row).toList()),
          ));
        }
        for (final source in group.unanswered) {
          rows.add(_Quiet('暂时搜不了', about: source));
        }
      } else if (group.failed) {
        rows
          ..add(_Heading(_titles[kind]!))
          ..add(const _Quiet('暂时搜不了'));
      }
    }
    if (search.nothingFound) rows.add(const _Quiet('没有找到'));
    return rows;
  }
}

class _Input extends StatelessWidget {
  const _Input({required this.search, required this.onSubmit});
  final NextSearch search;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 60,
        child: Row(children: [
          const SizedBox(width: 22),
          const NextIcon(NextGlyph.search, size: 18, color: NextColors.p2),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: search.text,
              focusNode: search.focus,
              onSubmitted: (_) => onSubmit(),
              // Enter keeps the box focused; what it opens decides.
              onEditingComplete: () {},
              textInputAction: TextInputAction.search,
              maxLines: 1,
              cursorColor: NextColors.accent,
              cursorWidth: 1.5,
              cursorHeight: 20,
              style: NextText.sans(17),
              decoration: InputDecoration.collapsed(
                hintText: '搜索',
                hintStyle: NextText.sans(17, color: NextColors.p3),
              ),
            ),
          ),
          const SizedBox(width: 22),
        ]),
      );
}

/// A crimson glint along the box's lower edge while groups answer.
class _Sweep extends StatefulWidget {
  const _Sweep();

  @override
  State<_Sweep> createState() => _SweepState();
}

class _SweepState extends State<_Sweep> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (NextMotion.reduced(context)) {
      return const ColoredBox(color: NextColors.accentSoft);
    }
    return ClipRect(
      child: AnimatedBuilder(
        animation: _run,
        builder: (context, _) => FractionalTranslation(
          translation:
              Offset(-1 + 2 * Curves.easeInOut.transform(_run.value), 0),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Color(0x00FF2E55),
                NextColors.accent,
                Color(0x00FF2E55),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: NextText.sans(12,
                    weight: FontWeight.w500,
                    color: NextColors.p3,
                    letterSpacing: 1)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text, {this.about});
  final String text;

  /// What it is said of: a source, by its name.
  final String? about;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Text.rich(
          TextSpan(children: [
            if (about != null)
              TextSpan(
                  text: '$about  ',
                  style: NextText.sans(13.5, color: NextColors.p2)),
            TextSpan(text: text),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: NextText.sans(13.5, color: NextColors.p3),
        ),
      );
}

class _QuietButton extends StatelessWidget {
  const _QuietButton(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(label,
              style: NextText.sans(12,
                  color: hovered ? NextColors.paper : NextColors.p3)),
        ),
      );
}

/// One row; the selected one is tinted. Moving the pointer over a row
/// selects it; the keyboard's selection is scrolled into view.
class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.entry,
    required this.selected,
    required this.search,
    required this.onOpen,
  });
  final SearchEntry entry;
  final bool selected;
  final NextSearch search;
  final ValueChanged<SearchEntry> onOpen;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  @override
  void initState() {
    super.initState();
    _wantArtwork();
  }

  void _wantArtwork() {
    if (widget.entry case final SourceEntry e) widget.search.wantArtwork(e);
  }

  @override
  void didUpdateWidget(_Row old) {
    super.didUpdateWidget(old);
    _wantArtwork();
    if (widget.selected && !old.selected && widget.search.movedByKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(context,
            duration: const Duration(milliseconds: 120),
            alignmentPolicy: widget.search.movedUp
                ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
                : ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      });
    }
  }

  String get _label => switch (widget.entry) {
        RecentEntry(:final text) => text,
        WorkEntry(:final work) => work.title,
        EpisodeEntry(:final work, :final episode) =>
          '${work.title} ${Words.episode(episode.number)}',
        SourceEntry(:final hit) => '${hit.title} ${hit.source.name}',
        NipaEntry() => '让 Nipa 找',
      };

  @override
  Widget build(BuildContext context) {
    final on = widget.selected;
    return MouseRegion(
      onHover: (_) => widget.search.hover(widget.entry),
      child: Pressable(
        onTap: () => widget.onOpen(widget.entry),
        semanticLabel: _label,
        pressScale: 0.99,
        builder: (context, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              on ? const Color(0x33FF2E55) : const Color(0x00FF2E55),
              on ? const Color(0x0DFF2E55) : const Color(0x00FF2E55),
            ]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: switch (widget.entry) {
            RecentEntry(:final text) => _recent(text, on),
            final WorkEntry e => _work(e.work, on, inLibrary: e.inLibrary),
            EpisodeEntry(:final work, :final episode) =>
              _episode(work, episode, on),
            final SourceEntry e => _source(e, on),
            NipaEntry(:final text) => _nipa(text, on),
          },
        ),
      ),
    );
  }

  static TextStyle _title(bool on) => NextText.sans(14.5,
      weight: FontWeight.w600, color: on ? NextColors.paper : NextColors.p2);

  static final _meta = NextText.sans(12.5, color: NextColors.p3);

  Widget _recent(String text, bool on) => SizedBox(
        height: 40,
        child: Row(children: [
          const NextIcon(NextGlyph.search, size: 14, color: NextColors.p4),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(14,
                    color: on ? NextColors.paper : NextColors.p2)),
          ),
        ]),
      );

  /// [inLibrary]: found online, and the library has it. [workTitle]: a
  /// source's work, by the library's name for it.
  Widget _work(UiWork work, bool on,
      {String? source,
      String? poster,
      String? workTitle,
      bool inLibrary = false}) {
    final meta = <String>[
      if (workTitle != null && workTitle != work.title) workTitle,
      if (source != null) source,
      if (work.year case final year?) '$year',
      if (work.episodeCount case final n? when n > 1 && !work.film) '$n 集',
    ].join(' · ');
    return SizedBox(
      height: 68,
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 36,
            height: 54,
            child: NextImage(poster ?? work.artwork.poster,
                shape: ArtShape.poster, tint: work.artwork.tint),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(work.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _title(on)),
              if (meta.isNotEmpty || work.devices.isNotEmpty || inLibrary) ...[
                const SizedBox(height: 4),
                Row(children: [
                  if (meta.isNotEmpty) Text(meta, maxLines: 1, style: _meta),
                  if (meta.isNotEmpty && (work.devices.isNotEmpty || inLibrary))
                    const SizedBox(width: 12),
                  if (inLibrary) const _InLibrary(),
                  if (work.devices.isNotEmpty)
                    Flexible(child: DeviceMark(work.devices, size: 12)),
                ]),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  /// [file]: a share's file of it, marked as one.
  Widget _episode(UiWork work, UiEpisode episode, bool on,
      {String? source, String? image, bool file = false}) {
    final title = episode.title;
    // A source's episode may come without its number: its name alone.
    final name = episode.number <= 0
        ? title ?? ''
        : title == null || title.isEmpty
            ? Words.episode(episode.number)
            : '${Words.episode(episode.number)} · $title';
    final meta = [
      if (work.title.isNotEmpty && work.title != name) work.title,
      if (source != null) source,
    ].join(' · ');
    return _still(
      name,
      meta,
      on,
      image: image ?? episode.still ?? work.artwork.backdrop,
      tint: work.artwork.tint,
      file: file,
      playable: episode.playable,
    );
  }

  /// A row of a source: its works as the library's; an episode, a video or
  /// a file under a still, with the work it is bound to. Out of reach,
  /// what it held, dimmed.
  Widget _source(SourceEntry entry, bool on) {
    final hit = entry.hit;
    final source = hit.source.name;
    final image = widget.search.artworkOf(entry);
    final row = switch ((hit.kind, hit.work, hit.episode)) {
      (UiSourceHitKind.work, final work?, _) => _work(work, on,
          source: source, poster: image, workTitle: hit.workTitle),
      (final kind, final work?, final episode?) => _episode(work, episode, on,
          source: source, image: image, file: kind == UiSourceHitKind.file),
      _ => _still(
          hit.title,
          [if (hit.workTitle case final title?) title, source].join(' · '),
          on,
          image: image,
          file: true,
          playable: hit.playable),
    };
    return hit.reachable ? row : Opacity(opacity: 0.5, child: row);
  }

  /// A 16:9 picture (or, for a file without one, its mark), a name and a
  /// line under it; the play mark when it plays.
  Widget _still(String name, String meta, bool on,
      {String? image, int? tint, bool file = false, bool playable = false}) {
    return SizedBox(
      height: 60,
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 72,
            height: 40.5,
            child: Stack(fit: StackFit.expand, children: [
              NextImage(image, tint: tint),
              if (file && image == null)
                const Center(
                    child: NextIcon(NextGlyph.video,
                        size: 16, color: NextColors.p3)),
            ]),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _title(on)),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(meta,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _meta),
              ],
            ],
          ),
        ),
        if (playable) ...[
          const SizedBox(width: 12),
          NextIcon(NextGlyph.play,
              size: 14, color: on ? NextColors.paper : NextColors.p4),
          const SizedBox(width: 4),
        ],
      ]),
    );
  }

  Widget _nipa(String text, bool on) => SizedBox(
        height: 50,
        child: Row(children: [
          const SizedBox(width: 5),
          const NipaAvatar(size: 26),
          const SizedBox(width: 17),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '让 Nipa 找',
                    style: NextText.sans(14,
                        color: on ? NextColors.paper : NextColors.p2)),
                TextSpan(
                    text: '「$text」',
                    style: NextText.sans(14,
                        weight: FontWeight.w500,
                        color: on ? NextColors.paper : NextColors.p2)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      );
}

/// A work found online that the library has: a check and two words, as
/// quiet as a device's mark.
class _InLibrary extends StatelessWidget {
  const _InLibrary();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const NextIcon(NextGlyph.check,
              size: 11, color: NextColors.p2, stroke: 2),
          const SizedBox(width: 4),
          Text('已入库', style: NextText.sans(12, color: NextColors.p2)),
        ]),
      );
}
