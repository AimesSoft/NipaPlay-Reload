import 'package:flutter/material.dart';

class SettingsHintText extends StatelessWidget {
  final String text;
  const SettingsHintText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
      textAlign: TextAlign.left,
    );
  }
}
