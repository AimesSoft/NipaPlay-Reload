import 'package:flutter/material.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// 与主界面保持一致的 TabBar 样式。
class NipaplayMainTabBar extends StatelessWidget
    implements PreferredSizeWidget {
  const NipaplayMainTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.showDivider = false,
    this.dividerColor,
    this.showLeadingLogoOnMobile = true,
    this.labelPadding = const EdgeInsets.only(bottom: 15.0),
    this.preferredHeight = kTextTabBarHeight,
  });

  final TabController controller;
  final List<Widget> tabs;
  final bool showDivider;
  final Color? dividerColor;
  final bool showLeadingLogoOnMobile;
  final EdgeInsetsGeometry labelPadding;
  final double preferredHeight;

  @override
  Size get preferredSize => Size.fromHeight(preferredHeight);

  @override
  Widget build(BuildContext context) {
    final tabBar = _buildTabBar(context);
    if (!showLeadingLogoOnMobile || globals.isDesktopOrTablet) {
      return tabBar;
    }

    return Row(
      children: [
        const SizedBox(width: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 20.0),
          child: Image.asset(
            'assets/logo.png',
            height: 40,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: tabBar),
      ],
    );
  }

  TabBar _buildTabBar(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return TabBar(
      controller: controller,
      isScrollable: true,
      tabs: tabs,
      labelColor: AppAccentColors.current,
      unselectedLabelColor: isDarkMode ? Colors.white60 : Colors.black54,
      labelPadding: labelPadding,
      tabAlignment: TabAlignment.start,
      splashFactory: NoSplash.splashFactory,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      dividerColor: showDivider ? dividerColor : Colors.transparent,
      dividerHeight: 3.0,
      indicator: NipaplayMainTabIndicator(
        indicatorHeight: 3.0,
        indicatorColor: AppAccentColors.current,
        radius: 30.0,
      ),
      indicatorSize: TabBarIndicatorSize.label,
    );
  }
}

/// 与主界面一致的底部指示器。
class NipaplayMainTabIndicator extends Decoration {
  const NipaplayMainTabIndicator({
    required this.indicatorHeight,
    required this.indicatorColor,
    required this.radius,
  });

  final double indicatorHeight;
  final Color indicatorColor;
  final double radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _NipaplayMainTabPainter(this, onChanged);
  }
}

class _NipaplayMainTabPainter extends BoxPainter {
  _NipaplayMainTabPainter(this.decoration, VoidCallback? onChanged)
      : super(onChanged);

  final NipaplayMainTabIndicator decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    assert(configuration.size != null);
    final rect = Offset(
          offset.dx,
          configuration.size!.height - decoration.indicatorHeight,
        ) &
        Size(configuration.size!.width, decoration.indicatorHeight);

    final paint = Paint()
      ..color = decoration.indicatorColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(decoration.radius)),
      paint,
    );
  }
}

/// 给自定义 Tab 使用的标签等宽指示线，与主 [TabBar] 的
/// [TabBarIndicatorSize.label] 保持一致。
class NipaplayLabelTabIndicator extends StatelessWidget {
  const NipaplayLabelTabIndicator({
    super.key,
    required this.label,
    required this.labelStyle,
    required this.selected,
    this.duration = const Duration(milliseconds: 160),
  });

  final String label;
  final TextStyle labelStyle;
  final bool selected;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    return AnimatedContainer(
      duration: duration,
      width: selected ? painter.width : 0,
      height: 3,
      decoration: BoxDecoration(
        color: AppAccentColors.current,
        borderRadius: BorderRadius.circular(30),
      ),
    );
  }
}
