import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class FloatingActionButtonDemoPage extends StatefulWidget {
  const FloatingActionButtonDemoPage({super.key});

  @override
  State<FloatingActionButtonDemoPage> createState() =>
      _FloatingActionButtonDemoPageState();
}

class _FloatingActionButtonDemoPageState
    extends State<FloatingActionButtonDemoPage> {
  int _counter = 0;
  bool _showMiniFAB = false;

  void _increment() {
    setState(() {
      _counter++;
    });
  }

  void _decrement() {
    setState(() {
      if (_counter > 0) _counter--;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Floating Action Button Demo'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Counter Display
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      const Text(
                        'Counter',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '$_counter',
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // FAB Toggle
              AdaptiveCard(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Show Mini FAB'),
                          const Text('Toggle between normal and mini size'),
                        ],
                      ),
                    ),
                    SizedBox(width: 10),
                    AdaptiveSwitch(
                      value: _showMiniFAB,
                      onChanged: (value) {
                        setState(() {
                          _showMiniFAB = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // FAB Info
              const AdaptiveCard(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AdaptiveFloatingActionButton Features',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '• iOS 26+: Circular button with native shadow',
                        style: TextStyle(fontSize: 14),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• iOS <26: CupertinoButton with circular shape',
                        style: TextStyle(fontSize: 14),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Android: Material FloatingActionButton',
                        style: TextStyle(fontSize: 14),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Supports mini size for compact layouts',
                        style: TextStyle(fontSize: 14),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Custom colors and elevation',
                        style: TextStyle(fontSize: 14),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Hero transitions for page navigation',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Examples Section
              const Text(
                'Different FAB Styles',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Color Examples
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  _buildFABExample('Default', Colors.blue, Icons.add),
                  _buildFABExample('Green', Colors.green, Icons.check),
                  _buildFABExample('Red', Colors.red, Icons.delete),
                  _buildFABExample('Purple', Colors.purple, Icons.favorite),
                ],
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrement FAB
          AdaptiveFloatingActionButton(
            onPressed: _decrement,
            mini: _showMiniFAB,
            heroTag: 'decrement_fab',
            backgroundColor: Colors.red,
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 16),
          // Increment FAB
          AdaptiveFloatingActionButton(
            onPressed: _increment,
            mini: _showMiniFAB,
            heroTag: 'increment_fab',
            backgroundColor: Colors.blue,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildFABExample(String label, Color color, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AdaptiveFloatingActionButton(
          onPressed: () {},
          backgroundColor: color,
          heroTag: 'fab_$label',
          mini: true,
          child: Icon(icon),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
