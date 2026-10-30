import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/shelf.dart';

/// What a work's page shows below its episodes (`UiWorkMore`), in the order
/// its rule gives: characters and who voices them, cast, crew, pictures,
/// facts and links. A section with nothing in it is left out, and the page
/// shows nothing more than it has.
class WorkMoreSections extends StatelessWidget {
  const WorkMoreSections({
    super.key,
    required this.more,
    required this.gallery,
    required this.onPerson,
    required this.onLink,
  });

  final UiWorkMore more;

  /// The work's pictures, read when the section is built.
  final Future<UiGallery>? gallery;
  final ValueChanged<UiCredit> onPerson;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    for (final section in more.sections) {
      final block = switch (section) {
        'characters' when more.characters.isNotEmpty =>
          _Characters(more.characters, onPerson: onPerson),
        'cast' when more.cast.isNotEmpty =>
          _People('演员', more.cast, onPerson: onPerson, key: const Key('cast')),
        'crew' when more.crew.isNotEmpty => _People('制作人员', more.crew,
            onPerson: onPerson, key: const Key('crew')),
        'gallery' when gallery != null => _Gallery(gallery!),
        'facts' when more.facts.isNotEmpty || more.tags.isNotEmpty =>
          _Facts(more.facts, more.tags),
        'links' when more.links.isNotEmpty =>
          _Links(more.links, onLink: onLink),
        _ => null,
      };
      if (block != null) blocks.add(block);
    }
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, block) in blocks.indexed) ...[
          if (i > 0) const SizedBox(height: 52),
          block,
        ],
      ],
    );
  }
}

/// A heading as the shelves have it, for sections that are not rows.
class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: NextLayout.gutter(context), bottom: 18),
        child: Text(text,
            style:
                NextText.sans(19, weight: FontWeight.w600, letterSpacing: 0.4)),
      );
}

/// Scales a little under the pointer, as cards do; a pointer that cannot
/// open anything leaves it still.
class _Hover extends StatefulWidget {
  const _Hover({required this.onTap, required this.child, this.scale = 1.04});
  final VoidCallback? onTap;
  final Widget child;
  final double scale;
  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.onTap != null;
    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => active ? setState(() => _hovered = true) : null,
      onExit: (_) => active ? setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _hovered && !NextMotion.reduced(context) ? widget.scale : 1,
          duration: const Duration(milliseconds: 320),
          curve: NextMotion.ease,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A round portrait; without a picture, the name's first letter.
class _Portrait extends StatelessWidget {
  const _Portrait(this.image, this.name, {this.size = 96});
  final String? image;
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: NextColors.ink3,
          boxShadow: [
            BoxShadow(
                color: Color(0x80000000),
                blurRadius: 24,
                offset: Offset(0, 10)),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: ClipOval(
          child: image == null
              ? Center(
                  child: Text(name.characters.firstOrNull ?? '',
                      style: NextText.serif(size * 0.36,
                          weight: FontWeight.w700, color: NextColors.p3)),
                )
              : NextImage(image, shape: ArtShape.poster),
        ),
      );
}

class _People extends StatelessWidget {
  const _People(this.title, this.people, {required this.onPerson, super.key});
  final String title;
  final List<UiCredit> people;
  final ValueChanged<UiCredit> onPerson;

  @override
  Widget build(BuildContext context) => Shelf(
        title: title,
        height: 168,
        gap: 20,
        itemCount: people.length,
        storageKey: 'work-$title',
        itemBuilder: (context, i) {
          final p = people[i];
          return SizedBox(
            width: 104,
            child: _Hover(
              onTap: p.person == null ? null : () => onPerson(p),
              child: Column(children: [
                _Portrait(p.image, p.name),
                const SizedBox(height: 12),
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: NextText.sans(13, weight: FontWeight.w500)),
                if (p.role case final role?) ...[
                  const SizedBox(height: 3),
                  Text(role,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: NextText.sans(12,
                          color: NextColors.p3, height: 1.35)),
                ],
              ]),
            ),
          );
        },
      );
}

class _Characters extends StatelessWidget {
  const _Characters(this.characters, {required this.onPerson});
  final List<UiCharacter> characters;
  final ValueChanged<UiCredit> onPerson;

  @override
  Widget build(BuildContext context) => Shelf(
        title: '角色',
        height: 252,
        gap: 18,
        itemCount: characters.length,
        storageKey: 'work-characters',
        itemBuilder: (context, i) {
          final c = characters[i];
          final voice = c.actors.firstOrNull;
          final radius = BorderRadius.circular(12);
          return SizedBox(
            width: 128,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Hover(
                  scale: 1.03,
                  onTap: voice?.person == null ? null : () => onPerson(voice!),
                  child: Container(
                    height: 176,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      color: NextColors.ink3,
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 30,
                            offset: Offset(0, 14)),
                      ],
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: const Color(0x14FFFFFF)),
                    ),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: Stack(fit: StackFit.expand, children: [
                        NextImage(c.image,
                            shape: ArtShape.poster,
                            alignment: Alignment.topCenter),
                        if (voice != null)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: _Portrait(voice.image, voice.name, size: 34),
                          ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(13, weight: FontWeight.w500)),
                if (voice != null) ...[
                  const SizedBox(height: 3),
                  Text(c.actors.map((a) => a.name).join('、'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NextText.sans(12, color: NextColors.p3)),
                ],
              ],
            ),
          );
        },
      );
}

/// Backdrops and stills wide, then posters; any of them opens full size.
class _Gallery extends StatelessWidget {
  const _Gallery(this.pictures);
  final Future<UiGallery> pictures;

  @override
  Widget build(BuildContext context) => FutureBuilder<UiGallery>(
        future: pictures,
        builder: (context, snapshot) {
          final gallery = snapshot.data;
          if (gallery == null || gallery.isEmpty)
            return const SizedBox.shrink();
          final all = [...gallery.wide, ...gallery.posters];
          Widget tile(String url, int index, ArtShape shape, double width,
              double height) {
            final radius =
                BorderRadius.circular(shape == ArtShape.wide ? 10 : 12);
            return _Hover(
              scale: 1.03,
              onTap: () => PictureViewer.open(context, all, index),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: NextColors.ink3,
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x80000000),
                        blurRadius: 30,
                        offset: Offset(0, 14)),
                  ],
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: ClipRRect(
                    borderRadius: radius, child: NextImage(url, shape: shape)),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (gallery.wide.isNotEmpty)
                Shelf(
                  title: '图片',
                  height: 180,
                  itemCount: gallery.wide.length,
                  storageKey: 'work-gallery',
                  itemBuilder: (context, i) =>
                      tile(gallery.wide[i], i, ArtShape.wide, 320, 180),
                ),
              if (gallery.posters.isNotEmpty) ...[
                if (gallery.wide.isNotEmpty) const SizedBox(height: 28),
                Shelf(
                  title: gallery.wide.isEmpty ? '图片' : '海报',
                  height: 210,
                  itemCount: gallery.posters.length,
                  storageKey: 'work-posters',
                  itemBuilder: (context, i) => tile(gallery.posters[i],
                      gallery.wide.length + i, ArtShape.poster, 140, 210),
                ),
              ],
            ],
          );
        },
      );
}

class _Facts extends StatelessWidget {
  const _Facts(this.facts, this.tags);
  final List<UiFact> facts;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final gutter = NextLayout.gutter(context);
    final width =
        MediaQuery.sizeOf(context).width - gutter - NextLayout.end(context);
    // Two columns where there is room for them, one on a phone.
    final columns = width >= 720 ? 2 : 1;
    final cell = columns == 2 ? (width.clamp(0.0, 920.0) - 48) / 2 : width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Heading('信息'),
        Padding(
          padding:
              EdgeInsets.only(left: gutter, right: NextLayout.end(context)),
          child: Wrap(
            spacing: 48,
            runSpacing: 14,
            children: [
              for (final f in facts)
                SizedBox(
                  width: cell,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(f.label,
                            style: NextText.sans(13,
                                color: NextColors.p3,
                                height: 1.5,
                                letterSpacing: 0.6)),
                      ),
                      Expanded(
                        child: Text(f.value,
                            style: NextText.sans(13,
                                color: NextColors.p2, height: 1.5)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (tags.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
                left: gutter, right: NextLayout.end(context), top: 22),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: NextColors.line2),
                    ),
                    child: Text(tag,
                        style: NextText.sans(12,
                            color: NextColors.p2, letterSpacing: 0.3)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Links extends StatelessWidget {
  const _Links(this.links, {required this.onLink});
  final List<UiLink> links;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
            left: NextLayout.gutter(context), right: NextLayout.end(context)),
        child: Wrap(
          spacing: 26,
          runSpacing: 10,
          children: [
            for (final link in links)
              _LinkText(link, onTap: () => onLink(link.url)),
          ],
        ),
      );
}

class _LinkText extends StatefulWidget {
  const _LinkText(this.link, {required this.onTap});
  final UiLink link;
  final VoidCallback onTap;
  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: NextText.sans(13,
                weight: FontWeight.w500,
                color: _hovered ? NextColors.paper : NextColors.p3,
                letterSpacing: 0.8),
            child: Text('${widget.link.label}  ↗'),
          ),
        ),
      );
}

/// Pictures full size over the page, one at a time: ←/→ or the arrows
/// move between them, Esc or a click outside closes.
class PictureViewer extends StatefulWidget {
  const PictureViewer({super.key, required this.pictures, required this.start});
  final List<String> pictures;
  final int start;

  static Future<void> open(
          BuildContext context, List<String> pictures, int start) =>
      Navigator.of(context).push(PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierLabel: '关闭',
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, _, __) =>
            PictureViewer(pictures: pictures, start: start),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child),
      ));

  @override
  State<PictureViewer> createState() => _PictureViewerState();
}

class _PictureViewerState extends State<PictureViewer> {
  late int _index = widget.start;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _move(int by) {
    final next = (_index + by).clamp(0, widget.pictures.length - 1);
    if (next != _index) setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.pictures.length > 1;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        switch (event.logicalKey) {
          case LogicalKeyboardKey.escape:
            Navigator.of(context).maybePop();
          case LogicalKeyboardKey.arrowLeft:
            _move(-1);
          case LogicalKeyboardKey.arrowRight:
            _move(1);
          default:
            return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Stack(fit: StackFit.expand, children: [
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: const ColoredBox(color: Color(0xE6000000)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(96, 72, 96, 72),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: ClipRRect(
                key: ValueKey(_index),
                borderRadius: BorderRadius.circular(10),
                child: Image(
                  image: artProvider(widget.pictures[_index]),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        if (many) ...[
          Positioned(
            left: 24,
            top: 0,
            bottom: 0,
            child: Center(
              child: NextIconButton(
                  glyph: NextGlyph.chevronLeft,
                  label: '上一张',
                  onTap: _index > 0 ? () => _move(-1) : null),
            ),
          ),
          Positioned(
            right: 24,
            top: 0,
            bottom: 0,
            child: Center(
              child: NextIconButton(
                  glyph: NextGlyph.chevronRight,
                  label: '下一张',
                  onTap: _index < widget.pictures.length - 1
                      ? () => _move(1)
                      : null),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Center(
              child: Text('${_index + 1} / ${widget.pictures.length}',
                  style: NextText.num(12, color: NextColors.p3)),
            ),
          ),
        ],
        Positioned(
          right: 20,
          top: 20 + MediaQuery.paddingOf(context).top,
          child: NextIconButton(
              glyph: NextGlyph.close,
              label: '关闭',
              onTap: () => Navigator.of(context).maybePop()),
        ),
      ]),
    );
  }
}
