// themed_text_field.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/theme_colors.dart';

class ThemedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final VoidCallback? onVisibilityChanged;

  const ThemedTextField({super.key, 
    required this.controller,
    required this.label,
    required this.obscureText,
    this.onVisibilityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      cursorColor: getInputColor(),
      obscureText: obscureText,
      style: TextStyle(color: getInputColor()),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: getInputColor()),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        prefixIcon: Icon(
          label == '用户名' ? Ionicons.person_outline : Ionicons.lock_closed_outline,
          color: getInputColor(),
        ),
        suffixIcon: label == '密码' && onVisibilityChanged != null
            ? IconButton(
                icon: Icon(
                  obscureText ? Ionicons.eye_outline : Ionicons.eye_off_outline,
                  color: getInputColor(),
                ),
                onPressed: onVisibilityChanged,
              )
            : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: getInputLineColor(), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: getInputColor(), width: 2.0),
        ),
      ),
    );
  }
}