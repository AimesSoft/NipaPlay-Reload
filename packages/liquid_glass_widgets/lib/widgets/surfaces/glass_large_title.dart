import 'package:flutter/cupertino.dart';

// =============================================================================
// GlassLargeTitleController
// =============================================================================

/// Coordinates the large-title + search-bar collapse animation between
/// [GlassLargeTitle] and [GlassAppBar].
///
/// Create one instance per screen, pass it to both widgets, and dispose it in
/// your `State.dispose()`. The controller owns the [ScrollController] — callers
/// attach it to their [CustomScrollView] via [scrollController].
///
/// ## Two-phase iOS 26 collapse
///
/// **Phase 1** — large title fades out over the first `~52pt` of scroll.
/// Driven by [collapseProgress].
///
/// **Phase 2** — search bar (when provided to [GlassLargeTitle]) collapses
/// immediately after the title, over the next `~44pt`. Driven by
/// [searchBarCollapseProgress].
///
/// ```dart
/// class _MyScreenState extends State<MyScreen> {
///   final _titleController = GlassLargeTitleController();
///
///   @override
///   void dispose() {
///     _titleController.dispose();
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) => GlassScaffold(
///     appBar: GlassAppBar(
///       title: Text('Chats'),
///       largeTitleController: _titleController,
///     ),
///     body: CustomScrollView(
///       controller: _titleController.scrollController,
///       slivers: [
///         GlassLargeTitle(
///           text: 'Chats',
///           controller: _titleController,
///           searchBar: GlassSearchBar(placeholder: 'Search'),
///         ),
///         // ... content slivers
///       ],
///     ),
///   );
/// }
/// ```
class GlassLargeTitleController extends ChangeNotifier {
  /// Creates a controller.
  ///
  /// [collapseTitleHeight] — scroll distance (logical pixels) over which the
  /// large title fully collapses. Defaults to `52.0` (iOS 26 spec). Overridden
  /// automatically by [GlassLargeTitle] after its first layout.
  ///
  /// [searchBarHeight] — scroll distance over which the search bar collapses
  /// after the title collapse completes. Defaults to `44.0` (standard iOS
  /// search bar height). Overridden automatically by [GlassLargeTitle] after
  /// first layout when a `searchBar` is provided.
  GlassLargeTitleController({
    double collapseTitleHeight = 52.0,
    double searchBarHeight = 44.0,
  })  : _collapseTitleHeight = collapseTitleHeight,
        _searchBarHeight = searchBarHeight {
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  late final ScrollController _scrollController;

  // Both mutable — overridden by self-measurement from GlassLargeTitle.
  double _collapseTitleHeight;
  double _searchBarHeight;

  double _collapseProgress = 0.0;
  double _searchBarCollapseProgress = 0.0;

  // Raw offset for overscroll rubber-band stretch. May be negative on iOS.
  double _rawScrollOffset = 0.0;

  /// The [ScrollController] to attach to your [CustomScrollView].
  ScrollController get scrollController => _scrollController;

  /// Title collapse progress in the range `[0.0, 1.0]`.
  ///
  /// - `0.0` — large title fully visible, bar title invisible.
  /// - `1.0` — large title fully hidden, bar title fully visible (Phase 1 done).
  double get collapseProgress => _collapseProgress;

  /// Search bar collapse progress in the range `[0.0, 1.0]`.
  ///
  /// Starts from `0.0` only **after** [collapseProgress] reaches `1.0`
  /// (Phase 2 begins after Phase 1 completes).
  ///
  /// - `0.0` — search bar fully visible.
  /// - `1.0` — search bar fully collapsed behind the navigation bar.
  ///
  /// Only meaningful when a `searchBar` is provided to [GlassLargeTitle].
  double get searchBarCollapseProgress => _searchBarCollapseProgress;

  /// Raw scroll offset including negative values during iOS rubber-band overscroll.
  ///
  /// Used internally by [GlassLargeTitle] to drive the stretch scale animation
  /// when the user pulls down past the top of the list.
  double get rawScrollOffset => _rawScrollOffset;

  /// Calibrates the title collapse distance to the actual rendered height.
  ///
  /// Called automatically by [GlassLargeTitle] after first layout. You do not
  /// normally need to call this yourself.
  void reportMeasuredHeight(double height) {
    if (height > 0 && height != _collapseTitleHeight) {
      _collapseTitleHeight = height;
      _updateState();
    }
  }

  /// Calibrates the search bar collapse distance to the actual rendered height.
  ///
  /// Called automatically by [GlassLargeTitle] after first layout when a
  /// `searchBar` widget is provided. You do not normally need to call this.
  void reportSearchBarHeight(double height) {
    if (height > 0 && height != _searchBarHeight) {
      _searchBarHeight = height;
      _updateState();
    }
  }

  void _onScroll() {
    // Fires in the gesture/animation phase — always before the build phase.
    // Safe to call notifyListeners() synchronously here.
    _updateState();
  }

  void _updateState() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;

    // Phase 1: large title collapses over first window.
    final newTitleProgress = (offset / _collapseTitleHeight).clamp(0.0, 1.0);

    // Phase 2: search bar collapses in the second window,
    // starting exactly where Phase 1 ends.
    final searchOffset = offset - _collapseTitleHeight;
    final newSearchProgress = _searchBarHeight > 0
        ? (searchOffset / _searchBarHeight).clamp(0.0, 1.0)
        : 0.0;

    // Notify on collapseProgress change, searchBar change, or overscroll
    // (negative offsets keep collapseProgress at 0 but change stretch scale).
    final overscrollChanged = offset < 0 && offset != _rawScrollOffset;
    final changed = newTitleProgress != _collapseProgress ||
        newSearchProgress != _searchBarCollapseProgress ||
        overscrollChanged;

    _rawScrollOffset = offset;
    _collapseProgress = newTitleProgress;
    _searchBarCollapseProgress = newSearchProgress;

    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }
}

// =============================================================================
// GlassLargeTitle
// =============================================================================

/// A sliver widget that renders a large 34pt iOS 26 navigation title (and
/// optionally an inline search bar) which collapse smoothly as the user scrolls.
///
/// Drop it as the **first sliver** in your [CustomScrollView]. Pair with
/// [GlassLargeTitleController] and pass the same controller to
/// [GlassAppBar.largeTitleController] to automatically cross-fade the
/// inline bar title.
///
/// ## iOS 26 fidelity
///
/// - **Typography:** 34pt, w700, -0.5 letter-spacing — exact iOS 26 spec.
/// - **Two-phase collapse:** Large title fades first (Phase 1), then the
///   search bar collapses under the nav bar (Phase 2) — matching iOS 26's
///   `UINavigationItem.searchController` behaviour.
/// - **Fade curve:** `Curves.easeIn` on title, `Curves.easeIn` on search bar.
/// - **Overscroll stretch:** Title scales up slightly on rubber-band pull,
///   matching iOS 26's `UINavigationBar` large-title elastic stretch.
/// - **Self-measuring:** Reports rendered heights to the controller after
///   first layout — correct collapse timing under all Dynamic Type settings.
///
/// ## Basic usage — title only
///
/// ```dart
/// GlassLargeTitle(
///   text: 'Chats',
///   controller: _titleController,
/// )
/// ```
///
/// ## With search bar — two-phase iOS 26 collapse
///
/// ```dart
/// GlassLargeTitle(
///   text: 'Messages',
///   controller: _titleController,
///   searchBar: GlassSearchBar(
///     placeholder: 'Search',
///     onChanged: (v) => _filter(v),
///   ),
/// )
/// ```
///
/// ## With trailing widget (avatar, action button)
///
/// ```dart
/// GlassLargeTitle(
///   text: 'Listen Now',
///   controller: _titleController,
///   trailing: CircleAvatar(child: Text('SD')),
/// )
/// ```
class GlassLargeTitle extends StatefulWidget {
  /// Creates a large-title sliver.
  ///
  /// [text] is the title displayed at 34pt (iOS 26 spec).
  /// [controller] coordinates the collapse animation with [GlassAppBar].
  /// [searchBar] is an optional search widget (e.g. [GlassSearchBar]) that
  /// collapses in Phase 2, after the large title is fully scrolled away.
  const GlassLargeTitle({
    required this.text,
    required this.controller,
    this.searchBar,
    this.fontSize = 34.0,
    this.fontWeight = FontWeight.w700,
    this.letterSpacing = -0.5,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 8),
    this.searchBarPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    this.color,
    this.trailing,
    super.key,
  });

  /// The navigation title text — should match the `title` passed to
  /// [GlassAppBar].
  final String text;

  /// The controller that drives the collapse animation and provides the
  /// [ScrollController] for your [CustomScrollView].
  final GlassLargeTitleController controller;

  /// Optional search widget displayed below the large title.
  ///
  /// Typically a [GlassSearchBar]. When provided, the widget collapses in
  /// **Phase 2** — after the large title has fully scrolled away — matching
  /// iOS 26's two-phase UINavigationBar search collapse behaviour.
  final Widget? searchBar;

  /// Font size of the large title. Defaults to `34.0` (iOS 26 spec).
  final double fontSize;

  /// Font weight. Defaults to [FontWeight.w700].
  final FontWeight fontWeight;

  /// Letter spacing. Defaults to `-0.5` (iOS 26 spec).
  final double letterSpacing;

  /// Padding around the title row.
  ///
  /// Defaults to `EdgeInsets.fromLTRB(24, 0, 24, 8)`.
  final EdgeInsetsGeometry padding;

  /// Padding around the search bar, when [searchBar] is provided.
  ///
  /// Defaults to `EdgeInsets.symmetric(horizontal: 16, vertical: 4)`,
  /// which matches iOS 26's search bar insets under a large title.
  final EdgeInsetsGeometry searchBarPadding;

  /// Title text colour. Defaults to [CupertinoColors.label] resolved from
  /// the current theme — correct dark-mode behaviour automatically.
  final Color? color;

  /// Optional widget at the trailing edge of the title row.
  ///
  /// Use for an avatar or action button (Apple Music / Podcasts pattern).
  /// Fades out with the same curve as the title text.
  final Widget? trailing;

  @override
  State<GlassLargeTitle> createState() => _GlassTitleSliverState();
}

class _GlassTitleSliverState extends State<GlassLargeTitle> {
  // GlobalKeys for self-measuring both the title row and the search bar.
  final _titleKey = GlobalKey();
  final _searchBarKey = GlobalKey();
  bool _pendingMeasure = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onProgressChanged);
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(GlassLargeTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onProgressChanged);
      widget.controller.addListener(_onProgressChanged);
      _scheduleMeasure();
    }
    if (oldWidget.fontSize != widget.fontSize ||
        oldWidget.padding != widget.padding ||
        oldWidget.searchBar != widget.searchBar) {
      _scheduleMeasure();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onProgressChanged() {
    if (mounted) setState(() {});
  }

  void _scheduleMeasure() {
    if (_pendingMeasure) return;
    _pendingMeasure = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingMeasure = false;
      _measureAndReport();
    });
  }

  void _measureAndReport() {
    // Measure title row height.
    final titleBox = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    if (titleBox != null && titleBox.hasSize) {
      final h = titleBox.size.height;
      if (h > 0) widget.controller.reportMeasuredHeight(h);
    }

    // Measure search bar height (only when a searchBar is provided).
    if (widget.searchBar != null) {
      final searchBox =
          _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
      if (searchBox != null && searchBox.hasSize) {
        final h = searchBox.size.height;
        if (h > 0) widget.controller.reportSearchBarHeight(h);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.controller.collapseProgress;
    final searchProgress = widget.controller.searchBarCollapseProgress;
    final rawOffset = widget.controller.rawScrollOffset;
    final effectiveColor =
        widget.color ?? CupertinoColors.label.resolveFrom(context);

    // ── iOS 26 ease-in fade (Phase 1) ─────────────────────────────────────
    // Large title stays opaque longer, drops off quickly — matching UIKit.
    final titleFadeOut =
        Curves.easeIn.transform((1.0 - progress).clamp(0.0, 1.0));

    // ── iOS 26 overscroll rubber-band stretch ──────────────────────────────
    // Title grows slightly on rubber-band pull, matching UINavigationBar.
    final stretchScale =
        rawOffset < 0 ? 1.0 + (-rawOffset / 300.0).clamp(0.0, 0.12) : 1.0;

    // ── iOS 26 search bar ease-in fade (Phase 2) ──────────────────────────
    // Collapses height to zero and fades out after the title is gone.
    final searchFadeOut =
        Curves.easeIn.transform((1.0 - searchProgress).clamp(0.0, 1.0));
    final searchHeightFactor = (1.0 - searchProgress).clamp(0.0, 1.0);

    return SliverToBoxAdapter(
      child: Transform.scale(
        scale: stretchScale,
        alignment: Alignment.bottomLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Large title row ────────────────────────────────────────────
            Padding(
              key: _titleKey,
              padding: widget.padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      widget.text,
                      style: TextStyle(
                        fontSize: widget.fontSize,
                        fontWeight: widget.fontWeight,
                        letterSpacing: widget.letterSpacing,
                        color: effectiveColor.withValues(alpha: titleFadeOut),
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    Opacity(
                      opacity: titleFadeOut,
                      child: widget.trailing,
                    ),
                  ],
                ],
              ),
            ),

            // ── Search bar (Phase 2 collapse) ──────────────────────────────
            // Collapses height to zero via ClipRect + Align(heightFactor),
            // then fades out — replicating UISearchController's collapse
            // under the navigation bar after the large title scrolls away.
            if (widget.searchBar != null)
              ClipRect(
                child: Align(
                  heightFactor: searchHeightFactor,
                  alignment: Alignment.topCenter,
                  child: Opacity(
                    opacity: searchFadeOut,
                    child: Padding(
                      key: _searchBarKey,
                      padding: widget.searchBarPadding,
                      child: widget.searchBar,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
