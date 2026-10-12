import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay_ui_common/l10n/app_locale_utils.dart';
import 'package:nipaplay_ui_common/l10n/app_localizations.dart';

import 'ui/tv_app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const NipaPlayTvApp());
}

class NipaPlayTvApp extends StatelessWidget {
  const NipaPlayTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NipaPlay TV',
      theme: _buildTvTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocaleUtils.supportedLocales,
      home: const TvAppShell(),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
    );
  }

  ThemeData _buildTvTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF26C6DA),
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF101418),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 18),
        bodyMedium: TextStyle(fontSize: 16),
      ),
    );
  }
}
