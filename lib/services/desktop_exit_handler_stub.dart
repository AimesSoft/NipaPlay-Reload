import 'package:flutter/material.dart' as material;

/// Web/非桌面平台的空实现（用于条件导入）。
class DesktopExitHandler {
  DesktopExitHandler._();

  static final DesktopExitHandler instance = DesktopExitHandler._();

  Future<void> initialize(material.GlobalKey<material.NavigatorState> navigatorKey) async {}
}

