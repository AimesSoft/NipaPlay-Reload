import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/search_model.dart';
import 'package:nipaplay/services/search_service.dart';

enum TagSearchMode { none, text, advanced }

abstract interface class TagSearchDataSource {
  Future<SearchConfig> loadConfig();

  Future<SearchResult> searchByTags(List<String> tags);

  Future<SearchResult> searchAdvanced({
    String? keyword,
    int? type,
    List<int>? tagIds,
    int? year,
    required int minRate,
    required int maxRate,
    required int sort,
  });
}

class SearchServiceTagSearchDataSource implements TagSearchDataSource {
  const SearchServiceTagSearchDataSource(this.service);

  final SearchService service;

  @override
  Future<SearchConfig> loadConfig() => service.getSearchConfig();

  @override
  Future<SearchResult> searchByTags(List<String> tags) =>
      service.searchAnimeByTags(tags);

  @override
  Future<SearchResult> searchAdvanced({
    String? keyword,
    int? type,
    List<int>? tagIds,
    int? year,
    required int minRate,
    required int maxRate,
    required int sort,
  }) {
    return service.searchAnimeAdvanced(
      keyword: keyword,
      type: type,
      tagIds: tagIds,
      year: year,
      minRate: minRate,
      maxRate: maxRate,
      sort: sort,
    );
  }
}

class TagSearchController extends ChangeNotifier {
  TagSearchController({
    TagSearchDataSource? dataSource,
    String? initialTag,
    List<String>? suggestedTags,
  })  : _dataSource = dataSource ??
            SearchServiceTagSearchDataSource(SearchService.instance),
        suggestedTags = List.unmodifiable(suggestedTags ?? const []) {
    if (initialTag?.trim().isNotEmpty == true) {
      _textTags.add(initialTag!.trim());
    }
  }

  static const int pageSize = 20;

  final TagSearchDataSource _dataSource;
  final List<String> suggestedTags;
  final List<String> _textTags = [];
  final List<int> _selectedTagIds = [];
  final List<ConfigItem> _selectedTags = [];

  TagSearchMode mode = TagSearchMode.none;
  SearchConfig? config;
  String keyword = '';
  int? selectedType;
  int? selectedYear;
  double minRating = 0;
  double maxRating = 10;
  bool isTextSearching = false;
  bool isAdvancedSearching = false;
  bool isLoadingConfig = false;
  bool isLoadingMoreText = false;
  bool isLoadingMoreAdvanced = false;
  String? errorMessage;

  List<SearchResultAnime> textSearchResults = [];
  List<SearchResultAnime> displayedTextResults = [];
  List<SearchResultAnime> advancedSearchResults = [];
  List<SearchResultAnime> displayedAdvancedResults = [];
  int _currentTextPage = 0;
  int _currentAdvancedPage = 0;

  UnmodifiableListView<String> get textTags => UnmodifiableListView(_textTags);
  UnmodifiableListView<int> get selectedTagIds =>
      UnmodifiableListView(_selectedTagIds);
  UnmodifiableListView<ConfigItem> get selectedTags =>
      UnmodifiableListView(_selectedTags);
  bool get isSearching => isTextSearching || isAdvancedSearching;
  bool get hasMoreText =>
      displayedTextResults.length < textSearchResults.length;
  bool get hasMoreAdvanced =>
      displayedAdvancedResults.length < advancedSearchResults.length;

  bool get hasAdvancedCriteria =>
      keyword.trim().isNotEmpty ||
      minRating > 0 ||
      maxRating < 10 ||
      selectedYear != null ||
      selectedType != null ||
      _selectedTagIds.isNotEmpty;

  List<SearchResultAnime> get visibleResults => mode == TagSearchMode.advanced
      ? displayedAdvancedResults
      : displayedTextResults;

  int get totalResults => mode == TagSearchMode.advanced
      ? advancedSearchResults.length
      : textSearchResults.length;

  Future<void> initialize() async {
    if (_textTags.isNotEmpty) {
      await performTextSearch();
      return;
    }
    await loadConfig();
  }

  Future<void> loadConfig() async {
    isLoadingConfig = true;
    errorMessage = null;
    notifyListeners();
    try {
      config = await _dataSource.loadConfig();
    } catch (error) {
      errorMessage = '加载搜索配置失败: $error';
    } finally {
      isLoadingConfig = false;
      notifyListeners();
    }
  }

  String? addTextTag(String value) {
    final tag = value.trim();
    if (tag.isEmpty || _textTags.contains(tag)) return null;
    if (_textTags.length >= 10) return '最多只能添加10个标签';
    if (tag.length > 50) return '单个标签长度不能超过50个字符';
    _textTags.add(tag);
    notifyListeners();
    return null;
  }

  void removeTextTag(String tag) {
    if (_textTags.remove(tag)) notifyListeners();
  }

  void toggleTag(ConfigItem tag) {
    if (_selectedTagIds.remove(tag.key)) {
      _selectedTags.removeWhere((item) => item.key == tag.key);
    } else {
      _selectedTagIds.add(tag.key);
      _selectedTags.add(tag);
    }
    notifyListeners();
  }

  void setKeyword(String value) {
    if (keyword == value) return;
    keyword = value;
    notifyListeners();
  }

  void setSelectedType(int? value) {
    if (selectedType == value) return;
    selectedType = value;
    notifyListeners();
  }

  void setSelectedYear(int? value) {
    if (selectedYear == value) return;
    selectedYear = value;
    notifyListeners();
  }

  void setMinRating(double value) {
    minRating = value;
    if (minRating > maxRating) maxRating = minRating;
    notifyListeners();
  }

  void setMaxRating(double value) {
    maxRating = value;
    if (maxRating < minRating) minRating = maxRating;
    notifyListeners();
  }

  Future<void> performSmartSearch() async {
    if (isSearching) return;
    if (hasAdvancedCriteria) {
      await performAdvancedSearch();
      return;
    }
    if (_textTags.isNotEmpty) {
      await performTextSearch();
      return;
    }
    _setError('请添加标签或设置筛选条件');
  }

  Future<void> performTextSearch() async {
    if (_textTags.isEmpty) {
      _setError('请至少添加一个标签');
      return;
    }

    mode = TagSearchMode.text;
    isTextSearching = true;
    errorMessage = null;
    textSearchResults = [];
    displayedTextResults = [];
    _currentTextPage = 0;
    notifyListeners();

    try {
      final result = await _dataSource.searchByTags(_textTags);
      textSearchResults = result.animes;
      _currentTextPage = 1;
      final end = pageSize.clamp(0, textSearchResults.length);
      displayedTextResults = textSearchResults.sublist(0, end);
    } catch (error) {
      errorMessage = '搜索失败: $error';
    } finally {
      isTextSearching = false;
      notifyListeners();
    }
  }

  Future<void> performAdvancedSearch() async {
    mode = TagSearchMode.advanced;
    isAdvancedSearching = true;
    errorMessage = null;
    advancedSearchResults = [];
    displayedAdvancedResults = [];
    _currentAdvancedPage = 0;
    notifyListeners();

    try {
      final result = await _dataSource.searchAdvanced(
        keyword: keyword.trim().isEmpty ? null : keyword.trim(),
        type: selectedType,
        tagIds: _selectedTagIds.isEmpty ? null : _selectedTagIds,
        year: selectedYear,
        minRate: minRating.round(),
        maxRate: maxRating.round(),
        sort: 0,
      );
      advancedSearchResults = result.animes;
      _currentAdvancedPage = 1;
      final end = pageSize.clamp(0, advancedSearchResults.length);
      displayedAdvancedResults = advancedSearchResults.sublist(0, end);
    } catch (error) {
      errorMessage = '高级搜索失败: $error';
    } finally {
      isAdvancedSearching = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreTextResults() async {
    if (isLoadingMoreText || !hasMoreText) return;
    isLoadingMoreText = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _currentTextPage++;
    final start = (_currentTextPage - 1) * pageSize;
    final end =
        (_currentTextPage * pageSize).clamp(0, textSearchResults.length);
    displayedTextResults.addAll(textSearchResults.sublist(start, end));
    isLoadingMoreText = false;
    notifyListeners();
  }

  Future<void> loadMoreAdvancedResults() async {
    if (isLoadingMoreAdvanced || !hasMoreAdvanced) return;
    isLoadingMoreAdvanced = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _currentAdvancedPage++;
    final start = (_currentAdvancedPage - 1) * pageSize;
    final end = (_currentAdvancedPage * pageSize)
        .clamp(0, advancedSearchResults.length);
    displayedAdvancedResults.addAll(advancedSearchResults.sublist(start, end));
    isLoadingMoreAdvanced = false;
    notifyListeners();
  }

  String? takeError() {
    final message = errorMessage;
    errorMessage = null;
    return message;
  }

  void _setError(String message) {
    errorMessage = message;
    notifyListeners();
  }
}
