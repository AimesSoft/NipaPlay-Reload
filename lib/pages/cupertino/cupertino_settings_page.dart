import 'package:flutter/cupertino.dart';

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
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );

    final titleOpacity = (1.0 - (_scrollOffset / 100.0)).clamp(0.0, 1.0);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: statusBarHeight + 52 + 12),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Container(
                    width: 260,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.black.withOpacity(0.18),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.gear_alt_fill, size: 36, color: CupertinoColors.inactiveGray),
                        SizedBox(height: 14),
                        Text(
                          '设置页面暂未实现',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: statusBarHeight,
            left: 0,
            right: 0,
            child: Opacity(
              opacity: titleOpacity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  '设置',
                  style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
