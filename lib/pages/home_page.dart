import 'package:flutter/material.dart';
import 'package:nipaplay/pages/new_series_page.dart';
// ... other imports ...

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

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