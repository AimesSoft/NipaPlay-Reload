import 'package:flutter/material.dart';
import 'package:nipaplay/app/app_page_ids.dart';

class TabChangeNotifier extends ChangeNotifier {
  int? _targetTabIndex;
  int? _targetMediaLibrarySubTabIndex;
  String? _targetPageId;
  String? _targetMediaLibrarySectionId;

  int? get targetTabIndex => _targetTabIndex;
  int? get targetMediaLibrarySubTabIndex => _targetMediaLibrarySubTabIndex;
  String? get targetPageId => _targetPageId;
  String? get targetMediaLibrarySectionId => _targetMediaLibrarySectionId;

  void changePage(String pageId) {
    if (_targetPageId == pageId && _targetMediaLibrarySectionId == null) {
      return;
    }
    _targetPageId = pageId;
    _targetTabIndex = null;
    _targetMediaLibrarySectionId = null;
    _targetMediaLibrarySubTabIndex = null;
    debugPrint('[TabChangeNotifier] 请求切换到页面: $pageId');
    notifyListeners();
  }

  @Deprecated('Use changePage with a stable AppPageIds value.')
  void changeTab(int index) {
    final pageId = AppPageIds.fromLegacyIndex(index);
    _targetTabIndex = index;
    _targetPageId = pageId;
    _targetMediaLibrarySectionId = null;
    _targetMediaLibrarySubTabIndex = null;
    debugPrint(
      '[TabChangeNotifier] 兼容索引 $index 映射到页面: $pageId',
    );
    notifyListeners();
  }

  void changeToMediaLibrarySection(String sectionId) {
    _targetPageId = AppPageIds.mediaLibrary;
    _targetTabIndex = null;
    _targetMediaLibrarySectionId = sectionId;
    _targetMediaLibrarySubTabIndex = null;
    debugPrint('[TabChangeNotifier] 请求切换到媒体库分区: $sectionId');
    notifyListeners();
  }

  @Deprecated('Use changeToMediaLibrarySection with a stable section id.')
  void changeToMediaLibrarySubTab(
    int subTabIndex, {
    int mainTabIndex = 2,
  }) {
    debugPrint(
        '[TabChangeNotifier] changeToMediaLibrarySubTab called with subTabIndex: $subTabIndex, mainTabIndex: $mainTabIndex');
    _targetPageId = AppPageIds.mediaLibrary;
    _targetTabIndex = mainTabIndex;
    _targetMediaLibrarySectionId = null;
    _targetMediaLibrarySubTabIndex = subTabIndex;
    debugPrint('[TabChangeNotifier] 正在通知监听器切换到媒体库页面子标签: $subTabIndex');
    notifyListeners();
    debugPrint('[TabChangeNotifier] 已通知所有监听器');
  }

  void clearMainTabIndex() {
    debugPrint('[TabChangeNotifier] 只清除主标签索引，保留子标签索引');
    _targetTabIndex = null;
    _targetPageId = null;
    notifyListeners();
  }

  void clearSubTabIndex() {
    debugPrint('[TabChangeNotifier] 只清除子标签索引');
    _targetMediaLibrarySubTabIndex = null;
    _targetMediaLibrarySectionId = null;
    notifyListeners();
  }

  void clear() {
    _targetTabIndex = null;
    _targetMediaLibrarySubTabIndex = null;
    _targetPageId = null;
    _targetMediaLibrarySectionId = null;
  }
}
