import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

/// Demo page showcasing AdaptiveButton features
class ButtonDemoPage extends StatefulWidget {
  const ButtonDemoPage({super.key});

  @override
  State<ButtonDemoPage> createState() => _ButtonDemoPageState();
}

class _ButtonDemoPageState extends State<ButtonDemoPage> {
  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        useNativeToolbar: true,
        title: "Buttons",
        actions: [
          AdaptiveAppBarAction(
            icon: PlatformInfo.isIOS
                ? CupertinoIcons.info_circle
                : Icons.info_outline,
            iosSymbol: "info.circle",
            onPressed: () => _showMessage(context, 'Info button pressed'),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final topPadding = PlatformInfo.isIOS ? 130.0 : 16.0;

    return ListView(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: topPadding,
        bottom: 16.0,
      ),
      children: [
        if (PlatformInfo.isIOS26OrHigher())
          _buildSection(
            context,
            title: 'iOS 26 Button Examples',
            children: [
              Text(
                'Default Button',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: PlatformInfo.isIOS
                      ? (MediaQuery.platformBrightnessOf(context) ==
                                Brightness.dark
                            ? CupertinoColors.white
                            : CupertinoColors.black)
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: AdaptiveButton(
                  size: AdaptiveButtonSize.large,
                  style: AdaptiveButtonStyle.prominentGlass,
                  textColor: Colors.white,
                  onPressed: () =>
                      _showMessage(context, 'Default button pressed'),
                  label: 'Click Me',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Button with Icon',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: PlatformInfo.isIOS
                      ? (MediaQuery.platformBrightnessOf(context) ==
                                Brightness.dark
                            ? CupertinoColors.white
                            : CupertinoColors.black)
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: AdaptiveButton.sfSymbol(
                  size: AdaptiveButtonSize.large,
                  style: AdaptiveButtonStyle.prominentGlass,
                  onPressed: () => _showMessage(context, 'Icon button pressed'),
                  sfSymbol: SFSymbol('heart.fill', size: 20),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Disabled Button',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: PlatformInfo.isIOS
                      ? (MediaQuery.platformBrightnessOf(context) ==
                                Brightness.dark
                            ? CupertinoColors.white
                            : CupertinoColors.black)
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: const AdaptiveButton(
                  size: AdaptiveButtonSize.large,
                  onPressed: null,
                  label: 'Disabled',
                ),
              ),
            ],
          )
        else
          _buildSection(
            context,
            title: "iOS 26 Button Examples",
            children: [Text("The device does NOT support")],
          ),

        const SizedBox(height: 24),

        _buildSection(
          context,
          title: 'Basic Buttons',
          children: [
            Text(
              'Default Button',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: AdaptiveButton(
                onPressed: () =>
                    _showMessage(context, 'Default button pressed'),
                label: 'Click Me',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Button with Icon',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: AdaptiveButton.icon(
                onPressed: () => _showMessage(context, 'Icon button pressed'),
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.heart_fill
                    : Icons.favorite,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Disabled Buttson',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: const AdaptiveButton(onPressed: null, label: 'Disabled'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Button Styles',
          children: [
            Text(
              'Filled Button',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            AdaptiveButton(
              onPressed: () => _showMessage(context, 'Filled button'),
              style: AdaptiveButtonStyle.filled,
              label: 'Filled',
            ),
            const SizedBox(height: 16),
            Text(
              'Tinted Button',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            AdaptiveButton(
              onPressed: () => _showMessage(context, 'Tinted button'),
              style: AdaptiveButtonStyle.tinted,
              label: 'Tinted',
            ),
            const SizedBox(height: 16),
            Text(
              'Bordered Button',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            AdaptiveButton(
              onPressed: () => _showMessage(context, 'Bordered button'),
              style: AdaptiveButtonStyle.bordered,
              label: 'Bordered',
            ),
            const SizedBox(height: 16),
            Text(
              'Plain Button',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            AdaptiveButton(
              onPressed: () => _showMessage(context, 'Plain button'),
              style: AdaptiveButtonStyle.plain,
              label: 'Plain',
            ),
            const SizedBox(height: 16),
            Text(
              'Gray Button',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            AdaptiveButton(
              onPressed: () => _showMessage(context, 'Gray button'),
              style: AdaptiveButtonStyle.gray,
              label: 'Gray',
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Button Sizes',
          children: [
            Text(
              'Large Button',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: AdaptiveButton(
                useSmoothRectangleBorder: false,
                onPressed: () => _showMessage(context, 'Large button'),
                style: AdaptiveButtonStyle.filled,
                size: AdaptiveButtonSize.large,
                label: 'Full Width',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Compact Buttons',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AdaptiveButton(
                    onPressed: () => _showMessage(context, 'Yes'),
                    style: AdaptiveButtonStyle.filled,
                    label: 'Yes',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AdaptiveButton(
                    onPressed: () => _showMessage(context, 'No'),
                    style: AdaptiveButtonStyle.bordered,
                    label: 'No',
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Icon-Only Buttons',
          children: [
            Text(
              'Action Buttons',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildIconButton(
                  context,
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.heart
                      : Icons.favorite_border,
                  label: 'Like',
                ),
                _buildIconButton(
                  context,
                  icon: PlatformInfo.isIOS ? CupertinoIcons.share : Icons.share,
                  label: 'Share',
                ),
                _buildIconButton(
                  context,
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.bookmark
                      : Icons.bookmark_border,
                  label: 'Save',
                ),
                _buildIconButton(
                  context,
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.ellipsis
                      : Icons.more_horiz,
                  label: 'More',
                ),
              ],
            ),
            if (PlatformInfo.isIOS26OrHigher()) ...[
              const SizedBox(height: 14),
              Text(
                'For iOS 26 or Higher',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: PlatformInfo.isIOS
                      ? (MediaQuery.platformBrightnessOf(context) ==
                                Brightness.dark
                            ? CupertinoColors.white
                            : CupertinoColors.black)
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildIos26IconButton(context, icon: "heart", label: 'Like'),
                  _buildIos26IconButton(
                    context,
                    icon: "square.and.arrow.up",
                    label: 'Share',
                  ),
                  _buildIos26IconButton(
                    context,
                    icon: "bookmark",
                    label: 'Save',
                  ),
                  _buildIos26IconButton(
                    context,
                    icon: "ellipsis",
                    label: 'More',
                  ),
                ],
              ),
            ],
            if (PlatformInfo.isIOS26OrHigher()) ...[
              const SizedBox(height: 14),
              Text(
                'For iOS 26 or Higher (Circular)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: PlatformInfo.isIOS
                      ? (MediaQuery.platformBrightnessOf(context) ==
                                Brightness.dark
                            ? CupertinoColors.white
                            : CupertinoColors.black)
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildIos26CircularButton(
                    context,
                    icon: "heart",
                    label: 'Like',
                  ),
                  _buildIos26CircularButton(
                    context,
                    icon: "square.and.arrow.up",
                    label: 'Share',
                  ),
                  _buildIos26CircularButton(
                    context,
                    icon: "bookmark",
                    label: 'Save',
                  ),
                  _buildIos26CircularButton(
                    context,
                    icon: "ellipsis",
                    label: 'More',
                  ),
                ],
              ),
            ],
          ],
        ),
        SizedBox(height: 100),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PlatformInfo.isIOS
            ? (isDark
                  ? CupertinoColors.darkBackgroundGray
                  : CupertinoColors.white)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: PlatformInfo.isIOS
              ? (isDark
                    ? CupertinoColors.systemGrey4
                    : CupertinoColors.separator)
              : Theme.of(context).dividerColor,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: PlatformInfo.isIOS
                  ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildIconButton(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    return Column(
      children: [
        SizedBox(
          width: 38,
          height: 38,
          child: AdaptiveButton.icon(
            onPressed: () => _showMessage(context, '$label pressed'),
            style: AdaptiveButtonStyle.bordered,
            icon: icon,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: PlatformInfo.isIOS
                ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildIos26IconButton(
    BuildContext context, {
    required String icon,
    required String label,
  }) {
    return Column(
      children: [
        SizedBox(
          width: 38,
          height: 38,
          child: AdaptiveButton.sfSymbol(
            onPressed: () => _showMessage(context, '$label pressed'),
            style: AdaptiveButtonStyle.prominentGlass,
            sfSymbol: SFSymbol(icon, size: 17, color: Colors.white),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: PlatformInfo.isIOS
                ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildIos26CircularButton(
    BuildContext context, {
    required String icon,
    required String label,
  }) {
    return Column(
      children: [
        SizedBox(
          width: 38,
          height: 38,
          child: AdaptiveButton.sfSymbol(
            useSmoothRectangleBorder: false,
            borderRadius: BorderRadius.circular(1000),
            onPressed: () => _showMessage(context, 'pressed'),
            style: AdaptiveButtonStyle.prominentGlass,
            sfSymbol: SFSymbol("xmark", size: 17, color: Colors.white),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: PlatformInfo.isIOS
                ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _showMessage(BuildContext context, String message) {
    AdaptiveAlertDialog.show(
      context: context,
      title: message,
      actions: [
        AlertAction(
          title: 'OK',
          onPressed: () {},
          style: AlertActionStyle.defaultAction,
        ),
      ],
    );
  }
}
