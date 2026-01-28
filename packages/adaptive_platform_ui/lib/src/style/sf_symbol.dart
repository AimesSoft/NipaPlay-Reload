import 'package:flutter/cupertino.dart';

/// Describes an SF Symbol for native iOS 26 rendering
///
/// SF Symbols are Apple's system icons that can be used in iOS apps.
/// For a full list of available symbols, see: https://developer.apple.com/sf-symbols/
///
/// Example:
/// ```dart
/// SFSymbol('star.fill', size: 24, color: Colors.blue)
/// ```
class SFSymbol {
  /// The SF Symbol name (e.g., 'star.fill', 'heart', 'plus.circle')
  final String name;

  /// The size of the symbol in points
  final double size;

  /// The color of the symbol
  final Color? color;

  /// Creates an SF Symbol descriptor for native iOS rendering
  const SFSymbol(this.name, {this.size = 24.0, this.color});
}
