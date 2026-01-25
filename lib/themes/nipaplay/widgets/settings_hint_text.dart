import 'package:flutter/material.dart';

class SettingsHintText extends StatelessWidget {
  final String text;
  const SettingsHintText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        fontSize: 12,
      ),
      textAlign: TextAlign.left,
    );
  }
} 