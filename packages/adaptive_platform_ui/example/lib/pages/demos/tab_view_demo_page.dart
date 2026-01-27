import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class TabViewDemoPage extends StatelessWidget {
  const TabViewDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Tab Bar View Demo'),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(
            top: PlatformInfo.isIOS26OrHigher() ? 48.0 : 0,
          ),
          child: AdaptiveTabBarView(
            tabs: const ['Latest', 'Popular', 'Trending', 'Featured'],
            selectedColor: Colors.white,
            unselectedColor: Colors.white.withValues(alpha: 0.6),
            onTabChanged: (index) {
              // Tab changed callback
            },
            children: [
              _buildContent(
                context,
                title: 'Latest',
                color: Colors.blue,
                description: 'Most recent content',
              ),
              _buildContent(
                context,
                title: 'Popular',
                color: Colors.green,
                description: 'Most viewed content',
              ),
              _buildContent(
                context,
                title: 'Trending',
                color: Colors.orange,
                description: 'Trending now',
              ),
              _buildContent(
                context,
                title: 'Featured',
                color: Colors.purple,
                description: 'Featured content',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required String title,
    required Color color,
    required String description,
  }) {
    return Container(
      color: color.withValues(alpha: 0.1),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.article, size: 80, color: color),
              const SizedBox(height: 24),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text(
                'Swipe left or right to switch tabs',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
