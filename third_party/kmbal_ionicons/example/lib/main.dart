import 'package:flutter/material.dart';

import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:url_launcher/url_launcher_string.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Ionicons',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: MyHomePage(),
    );
  }
}

/// Example page
class MyHomePage extends StatelessWidget {
  final _outlineItems = ValueNotifier<List<MapEntry<String, String>>>([]);
  final _filledItems = ValueNotifier<List<MapEntry<String, String>>>([]);
  final _sharpItems = ValueNotifier<List<MapEntry<String, String>>>([]);
  final _logoItems = ValueNotifier<List<MapEntry<String, String>>>([]);

  MyHomePage({super.key}) {
    _onTextChanged(''); // trigger the search
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Ionicons'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Outline'),
              Tab(text: 'Filled'),
              Tab(text: 'Sharp'),
              Tab(text: 'Logo'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _onPressedGitHub,
              icon: const Icon(Ionicons.logo_github),
            ),
            TextButton(
              onPressed: _onPressedPub,
              child: const Text(
                'v0.2.1',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search icons',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(left: 32, right: 16),
                    child: Icon(Ionicons.search_outline),
                  ),
                ),
                onChanged: _onTextChanged,
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ValueListenableBuilder<dynamic>(
                    valueListenable: _outlineItems,
                    builder: (context, value, child) => _ItemList(items: value),
                  ),
                  ValueListenableBuilder<dynamic>(
                    valueListenable: _filledItems,
                    builder: (context, value, child) => _ItemList(items: value),
                  ),
                  ValueListenableBuilder<dynamic>(
                    valueListenable: _sharpItems,
                    builder: (context, value, child) => _ItemList(items: value),
                  ),
                  ValueListenableBuilder<dynamic>(
                    valueListenable: _logoItems,
                    builder: (context, value, child) => _ItemList(items: value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle on search icons
  void _onTextChanged(String value) {
    final items = value.isEmpty
        ? ioniconsMapping.entries.toList()
        : ioniconsMapping.entries
              .where((e) => e.key.contains(value.toLowerCase()))
              .toList();

    _outlineItems.value = items
        .where((e) => e.key.endsWith('-outline'))
        .toList();
    _filledItems.value = items
        .where((e) => !(e.key.endsWith('-outline') || e.key.endsWith('-sharp')))
        .toList();
    _sharpItems.value = items.where((e) => e.key.endsWith('-sharp')).toList();
    _logoItems.value = items.where((e) => e.key.startsWith('logo-')).toList();
  }

  /// Handle on pressed GitHub button
  void _onPressedGitHub() {
    launchUrlString('https://github.com/KMBAL/flutter-ionicons');
  }

  /// Handle on pressed Pub button
  void _onPressedPub() {
    launchUrlString('https://pub.dev/packages/kmbal_ionicons');
  }
}

/// Render the list of icons
class _ItemList extends StatelessWidget {
  final List<MapEntry<String, String>> items;

  final _controller = ScrollController();

  _ItemList({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.extent(
      controller: _controller,
      maxCrossAxisExtent: 86,
      childAspectRatio: 0.7,
      children: List.generate(items.length, (index) {
        final item = items[index];
        return Column(
          children: [
            Icon(IconData(int.parse(item.value), fontFamily: 'Ionicons', fontPackage: 'kmbal_ionicons'), size: 64),
            const SizedBox(height: 8),
            Text(
              item.key,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      }),
    );
  }
}
