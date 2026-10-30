import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui_data/ui_data.dart';
import '../shell/shell_controller.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/icons.dart';
import '../widgets/shelf.dart';
import 'detail_page.dart' show Overview;

/// A person's page, pushed over the work's page they were opened from.
Route<void> personRoute(UiPersonRef person, {String? name, String? image}) =>
    PageRouteBuilder<void>(
      transitionDuration: NextMotion.page,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, __) =>
          PersonPage(person: person, name: name, image: image),
      transitionsBuilder: (context, animation, _, child) =>
          nextPageTransition(context, animation, child),
    );

/// Who someone is (their portrait, names, dates, biography) and what they
/// took part in: first the works of the library, then everything their
/// provider lists, any of which opens as a work.
class PersonPage extends StatefulWidget {
  const PersonPage({super.key, required this.person, this.name, this.image});
  final UiPersonRef person;

  /// As the page they came from showed them, until the person is read.
  final String? name;
  final String? image;

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  UiPerson? _person;
  List<UiWork> _library = const [];
  bool _failed = false;
  bool _bioOpen = false;
  NextShellController? _shell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (!identical(shell, _shell)) {
      _shell = shell;
      _load();
    }
  }

  Future<void> _load() async {
    final data = _shell!.services.data;
    if (data is! NextWorkDetails) {
      setState(() => _failed = true);
      return;
    }
    final person = await (data as NextWorkDetails).person(widget.person);
    if (!mounted) return;
    if (person == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _person = person);
    final works = <UiWork>[];
    for (final id in person.libraryWorkIds) {
      if (await data.work(id) case final work?) works.add(work);
    }
    if (mounted) setState(() => _library = works);
  }

  void _openFound(UiPersonWork w) => _shell!.openWork(UiWork(
        workId: w.workId,
        title: w.title,
        year: w.year,
        artwork: UiArtwork(poster: w.poster),
      ));

  @override
  Widget build(BuildContext context) {
    final person = _person;
    final name = person?.name ?? widget.name ?? '';
    final image = person?.image ?? widget.image;
    final compact = NextLayout.compact(context);
    final gutter = NextLayout.gutter(context);
    return Listener(
      onPointerDown: (e) {
        if (e.buttons & kBackMouseButton != 0) Navigator.of(context).maybePop();
      },
      child: ColoredBox(
        color: NextColors.ink,
        child: Stack(fit: StackFit.expand, children: [
          // The portrait, far out of focus, colours the page.
          if (image != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.34,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                  child: NextImage(image, shape: ArtShape.poster),
                ),
              ),
            ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0xF2000000)],
                ),
              ),
            ),
          ),
          CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(
                    left: gutter,
                    right: NextLayout.end(context),
                    top: NextLayout.underBar(context) + (compact ? 48 : 64)),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _portrait(image, name, 150),
                          const SizedBox(height: 24),
                          _words(person, name),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _portrait(image, name, 220),
                          const SizedBox(width: 48),
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: _words(person, name),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (_library.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 56),
                  child: Shelf(
                    title: '在媒体库中',
                    height: 290,
                    itemCount: _library.length,
                    itemBuilder: (context, i) {
                      final w = _library[i];
                      return PosterCard(
                        workId: w.workId,
                        image: w.artwork.poster ?? w.artwork.backdrop,
                        tint: w.artwork.tint,
                        title: w.title,
                        width: 160,
                        height: 240,
                        onOpen: () => _shell!.openWork(w),
                      );
                    },
                  ),
                ),
              ),
            if (person != null && person.credits.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Shelf(
                    title: '参与作品',
                    height: 300,
                    itemCount: person.credits.length,
                    itemBuilder: (context, i) {
                      final w = person.credits[i];
                      return PosterCard(
                        workId: w.workId,
                        image: w.poster,
                        title: w.title,
                        reason: w.role,
                        width: 160,
                        height: 240,
                        onOpen: () => _openFound(w),
                      );
                    },
                  ),
                ),
              ),
            SliverToBoxAdapter(
                child: SizedBox(
                    height: 80 + MediaQuery.paddingOf(context).bottom)),
          ]),
          Positioned(
            left: gutter - 9,
            top: compact
                ? NextLayout.barTop(context) + 10
                : NextLayout.underBar(context) + 8,
            child: NextIconButton(
              glyph: NextGlyph.chevronLeft,
              label: '返回',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _portrait(String? image, String name, double width) {
    final radius = BorderRadius.circular(16);
    return Container(
      width: width,
      height: width * 1.5,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: NextColors.ink3,
        boxShadow: const [
          BoxShadow(
              color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24)),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: image == null
            ? Center(
                child: Text(name.characters.firstOrNull ?? '',
                    style: NextText.serif(width * 0.3,
                        weight: FontWeight.w700, color: NextColors.p4)),
              )
            : NextImage(image,
                shape: ArtShape.poster, alignment: Alignment.topCenter),
      ),
    );
  }

  Widget _words(UiPerson? person, String name) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: NextText.serif(40, letterSpacing: 1, height: 1.15)),
          if (person?.alias case final alias?) ...[
            const SizedBox(height: 8),
            Text(alias,
                style: NextText.sans(15,
                    color: NextColors.p3, letterSpacing: 2.4)),
          ],
          if (person != null && person.facts.isNotEmpty) ...[
            const SizedBox(height: 22),
            for (final f in person.facts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(f.label,
                          style: NextText.sans(13,
                              color: NextColors.p3, letterSpacing: 0.6)),
                    ),
                    Expanded(
                      child: Text(f.value,
                          style: NextText.sans(13, color: NextColors.p2)),
                    ),
                  ],
                ),
              ),
          ],
          if (person?.biography case final bio?) ...[
            const SizedBox(height: 16),
            Overview(
              text: bio,
              open: _bioOpen,
              onToggle: () => setState(() => _bioOpen = !_bioOpen),
            ),
          ],
          if (person != null && person.links.isNotEmpty) ...[
            const SizedBox(height: 22),
            Wrap(spacing: 26, runSpacing: 10, children: [
              for (final link in person.links)
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse(link.url),
                      mode: LaunchMode.externalApplication),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('${link.label}  ↗',
                        style: NextText.sans(13,
                            weight: FontWeight.w500,
                            color: NextColors.p3,
                            letterSpacing: 0.8)),
                  ),
                ),
            ]),
          ],
          if (_failed && person == null) ...[
            const SizedBox(height: 18),
            Text('资料暂时读不到。', style: NextText.sans(13, color: NextColors.p3)),
          ],
        ],
      );
}
