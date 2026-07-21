import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nipaplay/l10n/app_locale_utils.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

/// The player surface rendered in the secondary FlutterView.
///
/// Providers live above DesktopMultiWindowHost, so this MaterialApp sees the
/// same VideoPlayerState and Player instance as the main window.
class DesktopPlayerWindow extends StatelessWidget {
  const DesktopPlayerWindow({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeNotifier>().themeMode;
    final locale = context.watch<AppLanguageProvider>().locale;

    return MaterialApp(
      title: 'NipaPlay 独立播放器',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        fontFamilyFallback: AppTheme.platformFontFamilyFallback,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamilyFallback: AppTheme.platformFontFamilyFallback,
      ),
      locale: locale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: ColoredBox(
        color: Colors.black,
        child: PlayVideoPage(
          key: DesktopPlayerWindowService.instance.playerPageKey,
        ),
      ),
    );
  }
}
