import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';

// 计算饱和度调整的公式
Color _adjustSaturation(Color color, double factor) {
  // 将 RGB 转换为 HSL
  HSLColor hslColor = HSLColor.fromColor(color);

  // 调整饱和度，确保饱和度在0.0到1.0之间
  double newSaturation = hslColor.saturation * factor;
  newSaturation = newSaturation.clamp(0.0, 1.0); // 保证饱和度不会超出范围

  HSLColor newHSLColor = hslColor.withSaturation(newSaturation);

  // 返回调整后的颜色
  return newHSLColor.toColor();
}

// 计算明暗的公式
Color _calculateBrightness(Color color, double factor) {
  // 将 RGB 值转换为 HSL
  HSLColor hslColor = HSLColor.fromColor(color);

  // 调整亮度，确保亮度在0.0到1.0之间
  double newLightness = hslColor.lightness * factor;
  newLightness = newLightness.clamp(0.0, 1.0); // 保证亮度不会超出范围

  HSLColor newHSLColor = hslColor.withLightness(newLightness);

  // 返回调整后的颜色
  return newHSLColor.toColor();
}

// 封装返回背景颜色的方法
Color getBackgroundColor() {
  Color baseColor = _hexToColor(baseLightColor); // 使用传入的基础亮色
  Color adjustedColor;
  if (isDarkModeValue) {
    adjustedColor = _calculateBrightness(baseColor, 0.15);
    return _adjustSaturation(adjustedColor, 0.1); // 计算暗色背景
  } else {
    return baseColor; // 返回亮色背景
  }
}
Color getBorderColor() {
  Color baseColor = _hexToColor(baseLightColor); 
  Color adjustedColor;
  if (isDarkModeValue) {
    adjustedColor = _calculateBrightness(baseColor, 0.3);
    return _adjustSaturation(adjustedColor, 0.1); 
  } else {
    return _adjustSaturation(baseColor, 0.1); 
  }
}
Color getWBColor() {
  if (isDarkModeValue) {
    return Colors.white; 
  } else {
    return Colors.black; 
  }
}
// 封装返回边栏颜色的方法
Color getBarColor() {
  Color baseColor = _hexToColor(baseLightColor); // 使用传入的基础亮色
  Color adjustedColor;
  if (isDarkModeValue) {
    adjustedColor = _calculateBrightness(baseColor, 0.2); // 计算暗色边栏
  } else {
    adjustedColor = _calculateBrightness(baseColor, 0.8); // 计算亮色边栏
  }
  // 增加饱和度使边栏更艳丽
  return _adjustSaturation(adjustedColor, 0.2); // 提高边栏的饱和度，改为1.5
}

Color getLineColor() {
  Color baseColor = _hexToColor(baseLightColor); // 使用传入的基础亮色
  Color adjustedColor;
  if (isDarkModeValue) {
    adjustedColor = _calculateBrightness(baseColor, 0.4); // 暗色模式时减少亮度
  } else {
    adjustedColor = _calculateBrightness(baseColor, 0.65); // 亮色模式时减少亮度
  }
  return _adjustSaturation(adjustedColor, 0.2); // 提高线条的饱和度
}

Color getBarLineColor() {
  Color baseColor = _hexToColor(baseLightColor); // 使用传入的基础亮色
  Color adjustedColor;
  adjustedColor = _calculateBrightness(baseColor, 0.6); // 调整亮度
  return _adjustSaturation(adjustedColor, 0.2); // 提高边栏和线条的饱和度
}

// 封装返回按钮颜色的方法
Color getButtonColor() {
  Color baseColor = _hexToColor(baseLightColor); // 使用传入的基础亮色
  Color adjustedColor;
  if (isDarkModeValue) {
    adjustedColor = _calculateBrightness(baseColor, 0.4); // 计算暗色按钮
  } else {
    adjustedColor = _calculateBrightness(baseColor, 0.85); // 计算亮色按钮
  }
  // 降低饱和度使按钮更灰暗
  return _adjustSaturation(adjustedColor, 0.3); // 降低按钮的饱和度，改为0.8
}
Color getInputColor() {
  Color baseColor = _hexToColor(baseLightColor); // 使用传入的基础亮色
  Color adjustedColor;
  if (isDarkModeValue) {
    adjustedColor = _calculateBrightness(baseColor, 0.7); 
  } else {
    adjustedColor = _calculateBrightness(baseColor, 0.5); 
  }
  // 降低饱和度使按钮更灰暗r
  return _adjustSaturation(adjustedColor, 0.4); // 降低按钮的饱和度，改为0.8
}
// 封装返回按钮描边颜色的方法
Color getButtonLineColor() {
  Color baseColor = _hexToColor(baseLightColor); // 使用传入的基础亮色
  Color adjustedColor;
  if (isDarkModeValue) {
    adjustedColor = _calculateBrightness(baseColor, 0.5); // 暗色模式时边栏计算亮度
  } else {
    adjustedColor = _calculateBrightness(baseColor, 0.75); // 亮色模式时边栏计算亮度
  }
  return _adjustSaturation(adjustedColor, 0.2); // 降低按钮边框的饱和度，改为0.8
}
Color getSwitchOpenColor() {
  Color baseColor = _hexToColor(baseLightColor); // 使用传入的基础亮色
  Color adjustedColor;
  if (isDarkModeValue) {
    adjustedColor = _calculateBrightness(baseColor, 0.5); //夜间
  } else {
    adjustedColor = _calculateBrightness(baseColor, 0.75); //日间
  }
  return _adjustSaturation(adjustedColor, 0.5); 
}
Color getSwitchCloseColor() {
  Color baseColor = _hexToColor(baseLightColor); // 使用传入的基础亮色
  Color adjustedColor;
  if (isDarkModeValue) {
    adjustedColor = _calculateBrightness(baseColor, 0.5); //夜间
  } else {
    adjustedColor = _calculateBrightness(baseColor, 0.75); //日间
  }
  return _adjustSaturation(adjustedColor, 0.1); 
}
// 将十六进制字符串转换为 Color 对象
Color _hexToColor(String hex) {
  hex = hex.replaceAll('#', ''); // 去掉前面的 #
  return Color(int.parse('0xFF$hex')); // 转换为 Color 对象
}