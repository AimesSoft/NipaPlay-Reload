import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class BlurViewDemoPage extends StatefulWidget {
  const BlurViewDemoPage({super.key});

  @override
  State<BlurViewDemoPage> createState() => _BlurViewDemoPageState();
}

class _BlurViewDemoPageState extends State<BlurViewDemoPage> {
  BlurStyle _selectedBlurStyle = BlurStyle.systemUltraThinMaterial;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: 'Blur View Demo',
        actions: [AdaptiveAppBarAction(iosSymbol: "clear", onPressed: () {})],
      ),
      body: Stack(
        children: [
          // Background image for blur demonstration
          Positioned.fill(
            child: Image.network(
              'https://images.unsplash.com/photo-1747447597297-0716bbd5b049?ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&q=80&w=1364',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue.shade300,
                        Colors.purple.shade300,
                        Colors.pink.shade300,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Demo content - Scrollable
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 100),

                // Blur style selector
                AdaptiveBlurView(
                  blurStyle: BlurStyle.systemMaterial,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Blur Style',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildBlurStyleButton(
                          'Ultra Thin',
                          BlurStyle.systemUltraThinMaterial,
                        ),
                        _buildBlurStyleButton(
                          'Thin',
                          BlurStyle.systemThinMaterial,
                        ),
                        _buildBlurStyleButton(
                          'Regular',
                          BlurStyle.systemMaterial,
                        ),
                        _buildBlurStyleButton(
                          'Thick',
                          BlurStyle.systemThickMaterial,
                        ),
                        _buildBlurStyleButton(
                          'Chrome',
                          BlurStyle.systemChromeMaterial,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Example 1: Large blur card with icon
                AdaptiveBlurView(
                  blurStyle: _selectedBlurStyle,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'iOS 26 Liquid Glass',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getBlurStyleName(_selectedBlurStyle),
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Example 2: Horizontal card list
                SizedBox(
                  height: 140,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: BlurStyle.values.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final style = BlurStyle.values[index];
                      return AdaptiveBlurView(
                        blurStyle: style,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 120,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _getIconForStyle(style),
                                color: Colors.white,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _getShortStyleName(style),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Example 3: Grid of blur cards
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    _buildGridBlurCard(
                      'Photos',
                      Icons.photo_library,
                      Colors.blue,
                    ),
                    _buildGridBlurCard(
                      'Music',
                      Icons.music_note,
                      Colors.purple,
                    ),
                    _buildGridBlurCard('Videos', Icons.videocam, Colors.orange),
                    _buildGridBlurCard('Files', Icons.folder, Colors.green),
                  ],
                ),

                const SizedBox(height: 16),

                // Example 4: Platform info card
                AdaptiveBlurView(
                  blurStyle: BlurStyle.systemThinMaterial,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Platform Support',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow('iOS 26+', 'Native UIVisualEffectView'),
                        const SizedBox(height: 8),
                        _buildInfoRow('iOS <26', 'BackdropFilter with blur'),
                        const SizedBox(height: 8),
                        _buildInfoRow('Android', 'BackdropFilter with blur'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Example 5: Button group with blur background
                AdaptiveBlurView(
                  blurStyle: _selectedBlurStyle,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            'Cancel',
                            Icons.close,
                            Colors.red,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionButton(
                            'Confirm',
                            Icons.check,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Example 6: Bottom blur bar
                AdaptiveBlurView(
                  blurStyle: BlurStyle.systemUltraThinMaterial,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.apple, color: Colors.white70, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'iOS 26 Liquid Glass',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white70,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurStyleButton(String label, BlurStyle style) {
    final isSelected = _selectedBlurStyle == style;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedBlurStyle = style;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.white,
                  fontSize: 16,
                ),
              ),
              if (isSelected)
                const Icon(Icons.check, size: 20, color: Colors.blue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridBlurCard(String title, IconData icon, Color color) {
    return AdaptiveBlurView(
      blurStyle: _selectedBlurStyle,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String platform, String implementation) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Colors.white70,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: Colors.white70),
              children: [
                TextSpan(
                  text: '$platform: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                TextSpan(text: implementation),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getBlurStyleName(BlurStyle style) {
    switch (style) {
      case BlurStyle.systemUltraThinMaterial:
        return 'Ultra Thin Material';
      case BlurStyle.systemThinMaterial:
        return 'Thin Material';
      case BlurStyle.systemMaterial:
        return 'Regular Material';
      case BlurStyle.systemThickMaterial:
        return 'Thick Material';
      case BlurStyle.systemChromeMaterial:
        return 'Chrome Material';
    }
  }

  String _getShortStyleName(BlurStyle style) {
    switch (style) {
      case BlurStyle.systemUltraThinMaterial:
        return 'Ultra\nThin';
      case BlurStyle.systemThinMaterial:
        return 'Thin';
      case BlurStyle.systemMaterial:
        return 'Regular';
      case BlurStyle.systemThickMaterial:
        return 'Thick';
      case BlurStyle.systemChromeMaterial:
        return 'Chrome';
    }
  }

  IconData _getIconForStyle(BlurStyle style) {
    switch (style) {
      case BlurStyle.systemUltraThinMaterial:
        return Icons.opacity;
      case BlurStyle.systemThinMaterial:
        return Icons.blur_on;
      case BlurStyle.systemMaterial:
        return Icons.blur_circular;
      case BlurStyle.systemThickMaterial:
        return Icons.blur_linear;
      case BlurStyle.systemChromeMaterial:
        return Icons.gradient;
    }
  }
}
