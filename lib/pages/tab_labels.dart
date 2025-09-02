// tab_labels.dart
import 'package:flutter/material.dart';

List<Widget> createTabLabels() {
  return [
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Text("主页",
          locale:Locale("zh","CN"),
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Text("视频播放",
          locale:Locale("zh","CN"),
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Text("媒体库",
          locale:Locale("zh","CN"),
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Text("新番更新",
          locale:Locale("zh","CN"),
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Text("设置",
          locale:Locale("zh","CN"),
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ),
  ];
}