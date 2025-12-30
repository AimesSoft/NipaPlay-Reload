import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/themes/web/pages/web_home_page.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class NipaPlayWebEntryApp extends StatefulWidget {
  const NipaPlayWebEntryApp({super.key});

  @override
  State<NipaPlayWebEntryApp> createState() => _NipaPlayWebEntryAppState();
}

class _NipaPlayWebEntryAppState extends State<NipaPlayWebEntryApp> {
  late final Future<void> _initFuture = _initialize();

  Future<void> _initialize() async {
    await PlayerFactory.initialize();
    await DanmakuKernelFactory.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UIThemeProvider()),
        ChangeNotifierProvider(create: (_) => VideoPlayerState()),
      ],
      child: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          return Consumer<UIThemeProvider>(
            builder: (context, uiThemeProvider, _) {
              final bool ready =
                  snapshot.connectionState == ConnectionState.done &&
                      uiThemeProvider.isInitialized;

              return fluent.FluentApp(
                title: 'NipaPlay Web',
                debugShowCheckedModeBanner: false,
                themeMode: ThemeMode.system,
                theme: fluent.FluentThemeData.light(),
                darkTheme: fluent.FluentThemeData.dark(),
                home: ready
                    ? const WebHomePage()
                    : const fluent.NavigationView(
                        content: Center(child: fluent.ProgressRing()),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
