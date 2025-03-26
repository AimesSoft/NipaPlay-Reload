import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/theme_provider.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/color_option.dart';
import 'package:nipaplay/widgets/rounded_container.dart';
import 'package:provider/provider.dart';

/// 根据右侧颜色，计算出左侧颜色的 HEX 字符串
String computeLeftColorHex(Color rightColor) {
  if (rightColor == Colors.grey) {
    return "#FFFFFF";
  }
  final hsv = HSVColor.fromColor(rightColor);
  final newHsv = hsv.withSaturation(0.04).withValue(1.0);
  final newColor = newHsv.toColor();
  // 生成格式为 "#RRGGBB" 的字符串SS
  return '#${(newColor.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

class ColorSettings extends StatefulWidget {
  const ColorSettings({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _ColorSettingsState createState() => _ColorSettingsState();
}

class _ColorSettingsState extends State<ColorSettings> {
  // 定义右侧颜色列表
  final List<Color> rightColors = [
    Colors.grey, // 保持灰色不动
    const Color.fromARGB(255, 0, 123, 255), // 蓝色
    const Color.fromARGB(255, 0, 255, 255), // 青色
    const Color.fromARGB(255, 34, 193, 34), // 绿色
    const Color.fromARGB(255, 255, 255, 0), // 黄色
    const Color.fromARGB(255, 255, 0, 0), // 红色
    const Color.fromARGB(255, 255, 105, 180), // 粉色
    const Color.fromARGB(255, 75, 0, 130), // 紫色
    const Color.fromARGB(255, 0, 0, 139), // 深蓝
    const Color.fromARGB(255, 221, 160, 221), // 兰花紫
    const Color.fromARGB(255, 255, 20, 147), // 深粉色
  ];

  late final Map<String, Color> colorOptions;

  @override
  void initState() {
    super.initState();
    // 通过 rightColors 自动生成左侧 HEX 与右侧颜色的映射
    colorOptions = {
      for (var color in rightColors) computeLeftColorHex(color): color,
    };
  }

  // 保存颜色到存储
  Future<void> _saveColor(String color) async {
    await SettingsStorage.saveString("baseLightColor", color);
  }

  // 更新颜色的方法
  void _updateColor(String colorHex, ThemeProvider themeProvider) {
    setState(() {
      baseLightColor = colorHex;
      themeProvider.updateDraw();
      _saveColor(baseLightColor);
    });
  }
@override
Widget build(BuildContext context) {
  final themeProvider = context.watch<ThemeProvider>();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        "主色调",
        style: getTitleTextStyle(context),
      ),
      RoundedContainer(
        child: Row(
          children: colorOptions.entries.map((entry) {
            return ColorOption(
              color: entry.value,
              isPressed: baseLightColor == entry.key,
              onTap: () => _updateColor(entry.key, themeProvider),
            );
          }).toList(),
        ),
      ),
    ],
  );
}
}