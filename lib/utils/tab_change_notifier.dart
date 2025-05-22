import 'package:flutter/material.dart';

class TabChangeNotifier extends ChangeNotifier {
  int? _targetTabIndex;

  int? get targetTabIndex => _targetTabIndex;

  void changeTab(int index) {
    debugPrint('[TabChangeNotifier] changeTab called with index: $index (current: $_targetTabIndex)');
    if (_targetTabIndex == index) {
      debugPrint('[TabChangeNotifier] 已经是目标标签，无需切换');
      return;
    }
    _targetTabIndex = index;
    debugPrint('[TabChangeNotifier] 正在通知监听器切换到标签: $index');
    notifyListeners();
    debugPrint('[TabChangeNotifier] 已通知所有监听器');
  }

  void clear() {
    _targetTabIndex = null;
  }
} 