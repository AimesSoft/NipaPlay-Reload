/// Liquid Glass Widgets — pub.dev example.
///
/// Minimal recommended usage with [GlassScaffold]:
/// [LiquidGlassWidgets.initialize], [LiquidGlassWidgets.wrap],
/// [GlassScaffold], [GlassAppBar], [GlassTabBar], [GlassCard], [GlassButton].
///
///   cd example && flutter run -t example.dart

library;

import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();
  runApp(LiquidGlassWidgets.wrap(child: const _App()));
}

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  Brightness _brightness = Brightness.dark;

  void _toggle() => setState(() {
        _brightness =
            _brightness == Brightness.dark ? Brightness.light : Brightness.dark;
      });

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Liquid Glass Widgets',
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(brightness: _brightness),
      home: _HomePage(brightness: _brightness, onToggle: _toggle),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage({required this.brightness, required this.onToggle});
  final Brightness brightness;
  final VoidCallback onToggle;

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  int _tab = 0;

  static const _tabs = [
    GlassTab(icon: Icon(CupertinoIcons.house_fill), label: 'Home'),
    GlassTab(icon: Icon(CupertinoIcons.compass_fill), label: 'Explore'),
    GlassTab(icon: Icon(CupertinoIcons.music_note_2), label: 'Library'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;

    return GlassScaffold(
      background: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [
                    Color(0xFF0A0A2E),
                    Color(0xFF1A0A3E),
                    Color(0xFF0D1B2A)
                  ]
                : const [
                    Color(0xFFE8F0FE),
                    Color(0xFFF3E8FF),
                    Color(0xFFE8F4FD)
                  ],
          ),
        ),
      ),
      appBar: GlassAppBar(
        title: const Text('Liquid Glass'),
        actions: [
          GlassIconButton(
            onPressed: widget.onToggle,
            icon: Icon(
              isDark ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill,
            ),
          ),
        ],
      ),
      bottomBar: GlassTabBar.searchable(
        tabs: _tabs,
        selectedIndex: _tab,
        onTabSelected: (i) => setState(() => _tab = i),
        searchConfig: GlassSearchBarConfig(
          hintText: 'Search widgets…',
          onSearchToggle: (_) {},
          onSearchFocusChanged: (_) {},
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'iOS 26 Liquid Glass',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Shader-based refraction · jelly physics · dynamic lighting. '
                    'Tap ☀/☾ to toggle the app brightness independently of the OS.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      GlassButton(
                        icon: const Icon(CupertinoIcons.play_fill),
                        onTap: () {},
                        label: 'Get Started',
                      ),
                      const SizedBox(width: 12),
                      GlassButton(
                        icon: const Icon(CupertinoIcons.star_fill),
                        onTap: () {},
                        label: 'Star on GitHub',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (final item in [
              (
                CupertinoIcons.square_grid_2x2_fill,
                'Containers',
                'GlassCard · GlassContainer · GlassListTile'
              ),
              (
                CupertinoIcons.hand_point_left,
                'Interactive',
                'GlassButton · GlassSwitch · GlassSlider · GlassChip'
              ),
              (
                CupertinoIcons.layers_fill,
                'Surfaces',
                'GlassTabBar · GlassAppBar · GlassToolbar'
              ),
              (
                CupertinoIcons.rectangle_stack_fill,
                'Overlays',
                'GlassSheet · GlassMenu · GlassDialog · GlassToast'
              ),
              (
                CupertinoIcons.textformat,
                'Input',
                'GlassTextField · GlassSearchBar · GlassPicker'
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(item.$1, size: 26),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(item.$3, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(CupertinoIcons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
