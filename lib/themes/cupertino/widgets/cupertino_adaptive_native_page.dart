import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoAdaptivePageAction {
  const CupertinoAdaptivePageAction({
    required this.label,
    required this.icon,
    required this.iosSymbol,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final String iosSymbol;
  final VoidCallback onPressed;
}

class CupertinoAdaptiveNativePage extends StatelessWidget {
  const CupertinoAdaptiveNativePage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <CupertinoAdaptivePageAction>[],
  });

  final String title;
  final Widget body;
  final List<CupertinoAdaptivePageAction> actions;

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isIOS26OrHigher()) {
      return AdaptiveScaffold(
        appBar: AdaptiveAppBar(
          title: title,
          useNativeToolbar: true,
          actions: [
            for (final action in actions)
              AdaptiveAppBarAction(
                iosSymbol: action.iosSymbol,
                icon: action.icon,
                onPressed: action.onPressed,
              ),
          ],
        ),
        body: body,
      );
    }

    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final iconColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final navigator = Navigator.of(context);

    return GlassScaffold(
      backgroundColor: backgroundColor,
      appBar: GlassAppBar(
        title: Text(title),
        leading: navigator.canPop()
            ? GlassIconButton(
                icon: Icon(CupertinoIcons.chevron_back, color: iconColor),
                onPressed: navigator.maybePop,
                useOwnLayer: false,
              )
            : null,
        actions: [
          for (final action in actions)
            Semantics(
              label: action.label,
              button: true,
              child: GlassIconButton(
                icon: Icon(action.icon, color: iconColor),
                onPressed: action.onPressed,
                useOwnLayer: false,
              ),
            ),
        ],
      ),
      body: body,
    );
  }
}
