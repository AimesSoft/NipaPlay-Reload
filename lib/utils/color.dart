
// lib/utils/color.dart
// 颜色相关工具, 用于在终端中输出带颜色的文本.


/// ANSI 颜色代码枚举, 用于在终端中输出带颜色的文本.
enum ColorCode {

  // Regular colors
  red         ('\x1B[0;31m'), // 红色
  green       ('\x1B[0;32m'), // 绿色
  yellow      ('\x1B[0;33m'), // 黄色
  blue        ('\x1B[0;34m'), // 蓝色
  purple      ('\x1B[0;35m'), // 紫色
  cyan        ('\x1B[0;36m'), // 青色
  white       ('\x1B[0;37m'), // 白色
  gray        ('\x1B[0;90m'), // 灰色
  magenta     ('\x1B[0;35m'), // 洋红

  // Bold colors
  boldRed     ('\x1B[1;31m'), // 粗体红色
  boldGreen   ('\x1B[1;32m'), // 粗体绿色
  boldYellow  ('\x1B[1;33m'), // 粗体黄色
  boldBlue    ('\x1B[1;34m'), // 粗体蓝色
  boldPurple  ('\x1B[1;35m'), // 粗体紫色
  boldCyan    ('\x1B[1;36m'), // 粗体青色
  boldWhite   ('\x1B[1;37m'), // 粗体白色
  boldMagenta ('\x1B[1;35m'); // 粗体洋红

  const ColorCode(this.code);

  final String code;
}

/// 返回一个带有 ANSI 颜色代码的字符串, 用于在终端中输出带颜色的文本.
/// 如果 [enable] 为 false, 则返回原始文本.
String color(String text, ColorCode colorCode, [bool enable = true]) {

  const String ansiReset = '\x1B[0m';

  if(!enable) return text;
  final coloredText = text.replaceAll(ansiReset, colorCode.code);
  return '${colorCode.code}$coloredText$ansiReset';
}
