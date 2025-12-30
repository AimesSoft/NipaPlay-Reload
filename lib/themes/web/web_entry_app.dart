import 'package:flutter/material.dart';

import 'package:nipaplay/themes/web/pages/web_home_page.dart';

class NipaPlayWebEntryApp extends StatelessWidget {
  const NipaPlayWebEntryApp({super.key});

  static const Color _seedColor = Color(0xFF00A1D6);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NipaPlay Web',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F8),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const WebHomePage(),
    );
  }
}

