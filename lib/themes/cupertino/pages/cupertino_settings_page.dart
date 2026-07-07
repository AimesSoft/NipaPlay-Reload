import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/unified_settings_entries.dart';

class CupertinoSettingsPage extends StatefulWidget {
  const CupertinoSettingsPage({super.key});

  @override
  State<CupertinoSettingsPage> createState() => _CupertinoSettingsPageState();
}

class _CupertinoSettingsPageState extends State<CupertinoSettingsPage> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = buildUnifiedSettingEntries(
      context,
      surface: UnifiedSettingsSurface.phone,
    );
    final Color backgroundColor =
        CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double bottomContentPadding =
        MediaQuery.viewPaddingOf(context).bottom + 96;
    final double titleOpacity = (1.0 - (_scrollOffset / 10.0)).clamp(0.0, 1.0);

    return AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.phone,
      child: ColoredBox(
        color: backgroundColor,
        child: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(top: statusBarHeight + 52),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final section in UnifiedSettingSection.values) ...[
                          UnifiedCupertinoSettingsSectionView(
                            section: section,
                            entries: entries
                                .where((entry) => entry.section == section)
                                .toList(),
                          ),
                          if (section != UnifiedSettingSection.values.last)
                            const SizedBox(height: 24),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.only(bottom: bottomContentPadding),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        backgroundColor,
                        backgroundColor.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: statusBarHeight,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: titleOpacity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      context.l10n.settingsLabel,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .navLargeTitleTextStyle,
                    ),
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
