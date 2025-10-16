// tab_labels.dart
import 'package:flutter/material.dart';
import 'dart:io';

List<Widget> createTabLabels() {
  List<Widget> tabs = [
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Text("主页",
          locale:Locale("zh-Hans","zh"),
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Text("视频播放",
          locale:Locale("zh-Hans","zh"),
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Text("媒体库",
          locale:Locale("zh-Hans","zh"),
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ),
  ];

  // 仅在非iOS平台显示新番更新Tab
  if (!Platform.isIOS) {
    tabs.add(
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: Text("新番更新",
            locale:Locale("zh-Hans","zh"),
  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
    );
  }

  tabs.add(
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Text("设置",
          locale:Locale("zh-Hans","zh"),
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ),
  );

  return tabs;
}