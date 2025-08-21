import 'package:flutter/material.dart';

class TabChangeNotifier extends ChangeNotifier {
  int? _targetTabIndex;
  int? _targetMediaLibrarySubTabIndex;

  int? get targetTabIndex => _targetTabIndex;
  int? get targetMediaLibrarySubTabIndex => _targetMediaLibrarySubTabIndex;

  void changeTab(int index) {
    debugPrint('[TabChangeNotifier] changeTab called with index: $index (current: $_targetTabIndex)');
    if (_targetTabIndex == index) {
      debugPrint('[TabChangeNotifier] 已经是目标标签，无需切换');
      return;
    }
    _targetTabIndex = index;
    _targetMediaLibrarySubTabIndex = null; // 清除子标签索引
    debugPrint('[TabChangeNotifier] 正在通知监听器切换到标签: $index');
    notifyListeners();
    debugPrint('[TabChangeNotifier] 已通知所有监听器');
  }

  void changeToMediaLibrarySubTab(int subTabIndex) {
    debugPrint('[TabChangeNotifier] changeToMediaLibrarySubTab called with subTabIndex: $subTabIndex');
    _targetTabIndex = 2; // 媒体库页面索引
    _targetMediaLibrarySubTabIndex = subTabIndex;
    debugPrint('[TabChangeNotifier] 正在通知监听器切换到媒体库页面子标签: $subTabIndex');
    notifyListeners();
    debugPrint('[TabChangeNotifier] 已通知所有监听器');
  }

  void clearMainTabIndex() {
    debugPrint('[TabChangeNotifier] 只清除主标签索引，保留子标签索引');
    _targetTabIndex = null;
    notifyListeners();
  }

  void clearSubTabIndex() {
    debugPrint('[TabChangeNotifier] 只清除子标签索引');
    _targetMediaLibrarySubTabIndex = null;
    notifyListeners();
  }

  void clear() {
    _targetTabIndex = null;
    _targetMediaLibrarySubTabIndex = null;
  }
} 