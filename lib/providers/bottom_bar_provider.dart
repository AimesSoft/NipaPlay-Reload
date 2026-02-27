import 'package:flutter/foundation.dart';

/// 控制底部导航栏显示状态的 Provider
class BottomBarProvider extends ChangeNotifier {
  bool _useNativeBottomBar = true;
  bool _isBottomBarVisible = true;

  bool get useNativeBottomBar => _useNativeBottomBar;
  bool get isBottomBarVisible => _isBottomBarVisible;

  /// 显示底部导航栏
  void showBottomBar() {
    if (!_isBottomBarVisible) {
      _isBottomBarVisible = true;
      notifyListeners();
    }
  }

  /// 隐藏底部导航栏
  void hideBottomBar() {
    if (_isBottomBarVisible) {
      _isBottomBarVisible = false;
      notifyListeners();
    }
  }
}
