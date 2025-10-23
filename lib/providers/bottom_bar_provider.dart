import 'package:flutter/foundation.dart';

/// 控制底部导航栏显示状态的 Provider
class BottomBarProvider extends ChangeNotifier {
  bool _useNativeBottomBar = true;

  bool get useNativeBottomBar => _useNativeBottomBar;

  /// 显示底部导航栏
  void showBottomBar() {
    if (!_useNativeBottomBar) {
      _useNativeBottomBar = true;
      notifyListeners();
    }
  }

  /// 隐藏底部导航栏
  void hideBottomBar() {
    if (_useNativeBottomBar) {
      _useNativeBottomBar = false;
      notifyListeners();
    }
  }
}
