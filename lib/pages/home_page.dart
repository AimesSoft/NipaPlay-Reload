import 'package:flutter/material.dart';
import 'package:nipaplay/pages/new_series_page.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
// ... other imports ...

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // 懒加载观看记录
    Future.microtask(() {
      final provider = context.read<WatchHistoryProvider>();
      provider.loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // ... sidebar ...
          Expanded(
            child: PageView(
              children: const [
                NewSeriesPage(),
                // ... other pages ...
              ],
            ),
          ),
        ],
      ),
    );
  }
} 