/// 恢复旧媒体库排序存档时，逐字段兜底，避免空值或异常字段影响其他库。
Map<String, String> resolveMediaLibrarySortSettings(
  Object? saved, {
  required String defaultSortBy,
  required String defaultSortOrder,
}) {
  final settings = saved is Map ? saved : const {};
  final rawSortBy = settings['sortBy'];
  final rawSortOrder = settings['sortOrder'];
  final sortBy = rawSortBy is String ? rawSortBy.trim() : '';
  final sortOrder = rawSortOrder is String ? rawSortOrder.trim() : '';
  return {
    'sortBy': sortBy.isEmpty ? defaultSortBy : sortBy,
    'sortOrder': sortOrder == 'Ascending' || sortOrder == 'Descending'
        ? sortOrder
        : defaultSortOrder,
  };
}
