import 'package:flutter/material.dart';

class TabChangeNotifier extends ChangeNotifier {
  int? _targetTabIndex;

  int? get targetTabIndex => _targetTabIndex;

  void changeTab(int index) {
    debugPrint('[TabChangeNotifier] changeTab called with index: $index');
    _targetTabIndex = index;
    notifyListeners();
  }

  void clear() {
    _targetTabIndex = null;
  }
} 