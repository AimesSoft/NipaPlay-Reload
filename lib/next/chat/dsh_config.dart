import 'dart:convert';

import 'package:crypto/crypto.dart';

/// User-owned configuration for the pinned DSH runtime. Host wiring and keys
/// stay in the generated overlay; plugin config otherwise uses DSH's names.
final class DshConfig {
  DshConfig._(this.json);
  final Map<String, Object?> json;

  static const defaults = <String, Object?>{
    'schema': 1,
    'model': <String, Object?>{},
    'provider': <String, Object?>{},
    'request': <String, Object?>{},
    'compaction': <String, Object?>{},
    'plugins': <String, Object?>{},
  };
  static String get starter =>
      const JsonEncoder.withIndent('  ').convert(defaults);

  factory DshConfig.parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('DSH 配置必须是 JSON 对象');
    }
    final value = Map<String, Object?>.from(decoded);
    _keys(value, defaults.keys.toSet(), '配置');
    if (value['schema'] != 1) {
      throw const FormatException('DSH 配置 schema 必须为 1');
    }
    for (final key in defaults.keys.where((k) => k != 'schema')) {
      if (value.containsKey(key) && value[key] is! Map<String, dynamic>) {
        throw FormatException('$key 必须是 JSON 对象');
      }
    }
    final result = DshConfig._(value);
    result._validate();
    return result;
  }

  Map<String, Object?> section(String name) =>
      Map<String, Object?>.from(json[name] as Map? ?? const {});
  Map<String, Object?> get model => section('model');
  Map<String, Object?> get provider => section('provider');
  Map<String, Object?> get request => section('request');
  Map<String, Object?> get compaction => section('compaction');
  int get contextWindow => model['contextWindow'] as int? ?? 262144;
  int get maxTokens =>
      request['maxTokens'] as int? ?? model['maxTokens'] as int? ?? 32768;
  String get fingerprint =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(json)))).toString();

  List<Map<String, Object?>> get pluginRows => [
        {'id': 'compaction-basic', 'config': compaction},
        for (final entry in section('plugins').entries)
          {'id': entry.key, ...Map<String, Object?>.from(entry.value as Map)},
      ];

  void _validate() {
    _keys(
        model,
        {
          'name',
          'contextWindow',
          'maxTokens',
          'input',
          'reasoningEfforts',
          'compat'
        },
        'model');
    _keys(request, {'reasoningEffort', 'maxTokens'}, 'request');
    for (final name in ['contextWindow', 'maxTokens']) {
      _integer(model, name, 1, 'model');
    }
    _integer(request, 'maxTokens', 1, 'request');
    if (request.containsKey('reasoningEffort') &&
        request['reasoningEffort'] is! String) {
      throw const FormatException('request.reasoningEffort 必须是字符串');
    }
    for (final name in [
      'apiKeyEnv',
      'apiKey',
      'baseURL',
      'models',
      'modelOverrides',
      'api',
      'defaultContextWindow',
      'defaultMaxTokens'
    ]) {
      if (provider.containsKey(name)) {
        throw FormatException('provider.$name 由模型设置管理；容量与输出上限填写在 model');
      }
    }
    if (model.containsKey('name') && model['name'] is! String) {
      throw const FormatException('model.name 必须是字符串');
    }
    if (model.containsKey('input') &&
        (model['input'] is! List ||
            (model['input'] as List).any((v) => v != 'text' && v != 'image'))) {
      throw const FormatException('model.input 必须是 text / image 数组');
    }
    if (model.containsKey('compat') && model['compat'] is! Map) {
      throw const FormatException('model.compat 必须是对象');
    }
    if (model.containsKey('reasoningEfforts') &&
        model['reasoningEfforts'] != false &&
        model['reasoningEfforts'] is! Map) {
      throw const FormatException('model.reasoningEfforts 必须是对象或 false');
    }
    if (provider.containsKey('retryPolicy') &&
        provider['retryPolicy'] is! Map) {
      throw const FormatException('provider.retryPolicy 必须是对象');
    }
    if (provider['retryPolicy'] case final Map retry) {
      _integer(Map<String, Object?>.from(retry), 'maxRetries', 0,
          'provider.retryPolicy');
    }
    _validateCompaction(compaction, 'compaction');
    _validateResolved(compaction, 'compaction');
    if (compaction['modelPolicies'] case final List policies) {
      final targets = <String>{};
      for (final (i, policy) in policies.indexed) {
        if (policy is! Map<String, dynamic> ||
            policy['provider'] is! String ||
            policy['model'] is! String ||
            (policy['provider'] as String).isEmpty ||
            (policy['model'] as String).isEmpty) {
          throw FormatException(
              'compaction.modelPolicies[$i] 需要 provider 和 model');
        }
        _validateCompaction(policy, 'compaction.modelPolicies[$i]',
            policy: true);
        if (!targets.add(jsonEncode([policy['provider'], policy['model']]))) {
          throw FormatException('compaction.modelPolicies[$i] 的目标重复');
        }
        _validateResolved(
            _resolvePolicy(policy), 'compaction.modelPolicies[$i]');
      }
    } else if (compaction.containsKey('modelPolicies')) {
      throw const FormatException('compaction.modelPolicies 必须是数组');
    }
    if (maxTokens >= contextWindow) {
      throw const FormatException('输出上限必须小于上下文容量');
    }
    _validateBudget(compaction);
    for (final entry in section('plugins').entries) {
      if (entry.key.isEmpty ||
          {
            'nipa-app-server',
            'nipa-memory',
            'llm-pi-ai',
            'compaction-basic',
            'sdk-jsonrpc-server'
          }.contains(entry.key)) {
        throw FormatException('插件 ${entry.key} 属于宿主桥接或有独立配置区');
      }
      if (entry.value is! Map<String, dynamic>) {
        throw FormatException('plugins.${entry.key} 必须是对象');
      }
      final row = Map<String, Object?>.from(entry.value as Map);
      _keys(row, {'config', 'disabled'}, 'plugins.${entry.key}');
      if (row.containsKey('config') && row['config'] is! Map<String, dynamic>) {
        throw FormatException('plugins.${entry.key}.config 必须是对象');
      }
      if (row.containsKey('disabled') && row['disabled'] is! bool) {
        throw FormatException('plugins.${entry.key}.disabled 必须是布尔值');
      }
    }
  }

  Map<String, Object?> _resolvePolicy(Map<String, Object?> policy) {
    final resolved = {...compaction, ...policy};
    if (policy.containsKey('retainTokens')) resolved.remove('retainRatio');
    if (policy.containsKey('retainRatio')) resolved.remove('retainTokens');
    return resolved;
  }

  /// Validate capacity against the selected model's exact override before
  /// replacing a live runtime. Other models may have different capacities.
  void validateTarget(String provider, String model) {
    for (final policy in compaction['modelPolicies'] as List? ?? const []) {
      if (policy['provider'] == provider && policy['model'] == model) {
        _validateBudget(
            _resolvePolicy(Map<String, Object?>.from(policy as Map)));
      }
    }
  }

  void _validateBudget(Map<String, Object?> policy) {
    if (compaction['auto'] == false) return;
    final budget = contextWindow - maxTokens;
    final headroom = policy['headroomTokens'] as int? ?? 65536;
    final threshold =
        (contextWindow * (policy['thresholdRatio'] as num? ?? .8)).floor();
    final ceiling = budget - headroom;
    final retained = policy['retainTokens'] as int? ??
        (budget * (policy['retainRatio'] as num? ?? .16)).floor();
    if (ceiling <= 0 ||
        retained >= (threshold < ceiling ? threshold : ceiling)) {
      throw const FormatException('压缩预算不足：请增加上下文容量，或降低输出上限、压缩预留和保留量');
    }
  }

  static void _validateResolved(Map<String, Object?> map, String path) {
    if ((map['maxTokens'] ?? map['headroomTokens'] ?? 65536) == 0) {
      throw FormatException('$path.maxTokens 必须大于 0，压缩预留为 0 时请显式指定摘要上限');
    }
    if (!map.containsKey('retainTokens') &&
        (map['retainRatio'] as num? ?? .16) >=
            (map['thresholdRatio'] as num? ?? .8)) {
      throw FormatException('$path 保留比例必须小于触发比例');
    }
  }

  static void _validateCompaction(Map<String, Object?> map, String path,
      {bool policy = false}) {
    _keys(
        map,
        {
          'thresholdRatio',
          'headroomTokens',
          'retainRatio',
          'retainTokens',
          'summarizationProvider',
          'summarizationModel',
          'maxTokens',
          'compactionRetries',
          'maxOverflowRetries',
          if (policy) ...[
            'provider',
            'model'
          ] else ...[
            'auto',
            'modelPolicies'
          ],
        },
        path);
    if (map.containsKey('auto') && map['auto'] is! bool) {
      throw FormatException('$path.auto 必须是布尔值');
    }
    for (final key in ['thresholdRatio', 'retainRatio']) {
      if (map.containsKey(key)) {
        final n = map[key];
        if (n is! num || !n.isFinite || n <= 0 || n > 1) {
          throw FormatException('$path.$key 必须大于 0 且不大于 1');
        }
      }
    }
    for (final key in [
      'headroomTokens',
      'retainTokens',
      'compactionRetries',
      'maxOverflowRetries'
    ]) {
      _integer(map, key, 0, path);
    }
    _integer(map, 'maxTokens', 1, path);
    for (final key in ['summarizationProvider', 'summarizationModel']) {
      if (map.containsKey(key) && map[key] is! String) {
        throw FormatException('$path.$key 必须是字符串');
      }
    }
    final summaryProvider = map['summarizationProvider'] as String?;
    final summaryModel = map['summarizationModel'] as String?;
    if ((summaryProvider == null) != (summaryModel == null) ||
        (summaryProvider != null &&
            summaryModel != null &&
            summaryProvider.isEmpty != summaryModel.isEmpty)) {
      throw FormatException('$path 摘要 provider 与 model 必须成对设置或成对清空');
    }
    if (map.containsKey('retainRatio') && map.containsKey('retainTokens')) {
      throw FormatException('$path 的 retainRatio 与 retainTokens 只能选择一个');
    }
  }

  static void _integer(
      Map<String, Object?> map, String key, int minimum, String path) {
    if (map.containsKey(key) &&
        (map[key] is! int || (map[key] as int) < minimum)) {
      throw FormatException('$path.$key 必须是至少为 $minimum 的整数');
    }
  }

  static void _keys(
      Map<String, Object?> value, Set<String> allowed, String path) {
    final unknown = value.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException('$path 存在未知字段：${unknown.join(', ')}');
    }
  }

  static Object? _canonical(Object? value) => switch (value) {
        final Map map => {
            for (final key in map.keys.cast<String>().toList()..sort())
              key: _canonical(map[key])
          },
        final List list => list.map(_canonical).toList(),
        _ => value,
      };
}
