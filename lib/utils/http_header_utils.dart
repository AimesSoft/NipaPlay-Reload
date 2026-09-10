/// 改写 HTTP 头的小工具。
///
/// `package:http` 的 `BaseRequest.headers` 是带自定义 `equals`/`hashCode` 的
/// 大小写不敏感 `LinkedHashMap`，改写它时不能用 `removeWhere`：
/// Dart 3.13 的 VM 回归（dart-lang/sdk#64217）里，`LinkedHashMap.removeWhere`
/// 只把 `_data` 槽位标记成已删除，没有同步 `_index`，残留的索引槽里存的是
/// 删除哨兵（data 数组本身）。之后任何落到这个槽位的插入或查找，都会把哨兵
/// 当成 key 交给 `equals`；对带自定义相等性的 map 来说那是一次带参数类型检查
/// 的动态调用，于是抛
/// `type 'List<dynamic>' is not a subtype of type 'String' of 'a'`。
///
/// `remove` 与下标赋值都会正常维护 `_index`，所以下面几个函数用它们实现，
/// 语义和原来的 `addAll` / `removeWhere` 一致，但不会留下墓碑。
library;

/// 逐项写入 [values]，同名的键会被覆盖（等价于 `addAll`，但不留墓碑）。
void addOrReplaceHeaders(
  Map<String, String> headers,
  Map<String, String> values,
) {
  for (final entry in values.entries) {
    headers[entry.key] = entry.value;
  }
}

/// 大小写不敏感地删除所有名为 [name] 的头。
void removeHeader(Map<String, String> headers, String name) {
  final target = name.toLowerCase();
  for (final key in headers.keys.toList()) {
    if (key.toLowerCase() == target) {
      headers.remove(key);
    }
  }
}

/// 大小写不敏感地删除名为 [name]、且值等于 [value] 的头。
void removeHeaderIfValueMatches(
  Map<String, String> headers,
  String name,
  String value,
) {
  final target = name.toLowerCase();
  for (final key in headers.keys.toList()) {
    if (key.toLowerCase() == target && headers[key] == value) {
      headers.remove(key);
    }
  }
}

/// 删除所有满足 [test] 的头，用来替代 `headers.removeWhere(test)`。
void removeHeadersWhere(
  Map<String, String> headers,
  bool Function(String key, String value) test,
) {
  for (final key in headers.keys.toList()) {
    final value = headers[key];
    if (value != null && test(key, value)) {
      headers.remove(key);
    }
  }
}
