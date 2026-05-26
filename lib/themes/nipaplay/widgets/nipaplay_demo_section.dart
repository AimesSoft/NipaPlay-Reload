import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';

class NipaplayDemoSection extends StatelessWidget {
  const NipaplayDemoSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsCard(
      padding: EdgeInsets.zero,
      backgroundOpacity: 0.22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.65),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.onSurface.withValues(alpha: 0.12),
          ),
          Column(
            children: children
                .asMap()
                .entries
                .expand((entry) => [
                      entry.value,
                      if (entry.key != children.length - 1)
                        Divider(
                          height: 1,
                          color: colorScheme.onSurface.withValues(alpha: 0.12),
                        ),
                    ])
                .toList(),
          ),
        ],
      ),
    );
  }
}
