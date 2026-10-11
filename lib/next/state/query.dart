import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';

typedef StateReader = Future<List<JsonMap>> Function(int offset, int limit);

final class StateRows {
  const StateRows(this.rows, {this.warnings = const []});
  final List<JsonMap> rows;
  final List<String> warnings;
}

final class StateRelation {
  const StateRelation(this.view, this.localField, this.foreignField);
  final String view, localField, foreignField;
  JsonMap toJson() =>
      {'view': view, 'localField': localField, 'foreignField': foreignField};
}

final class StateView {
  const StateView(
      {required this.name,
      required this.description,
      required this.fields,
      required this.read,
      this.readAll,
      this.relations = const {}});
  final String name, description;
  final ObjectSchema fields;
  final StateReader read;
  final Future<StateRows> Function()? readAll;
  final Map<String, StateRelation> relations;
  JsonMap describe() => {
        'view': name,
        'schemaVersion': 1,
        'description': description,
        'fields': publicSchema(fields),
        'relations': {
          for (final e in relations.entries) e.key: e.value.toJson()
        },
        'filterOperators': [
          'eq',
          'ne',
          'in',
          'contains',
          'gt',
          'gte',
          'lt',
          'lte'
        ],
      };
}

const stateQueryInput = ObjectSchema({
  'view':
      StringSchema(minLength: 1, description: 'Registered public view name.'),
  'filter': ObjectSchema({},
      additionalProperties: true,
      description:
          'Field to operator/value objects. Predicates use AND. Scalar fields are filterable; arrays support contains with an exact member.'),
  'select': ArraySchema(StringSchema(),
      description:
          'Top-level field projection. Omitted means all public fields.'),
  'orderBy': ArraySchema(
      ObjectSchema({
        'field': StringSchema(),
        'direction': StringSchema(values: ['asc', 'desc'])
      }, required: [
        'field'
      ]),
      description:
          'Scalar sort keys; default is source order. Equal keys retain source order.'),
  'include': ObjectSchema({},
      additionalProperties: true,
      description:
          'Declared relation names mapped to query options (filter, select, orderBy, limit, include).'),
  'limit': IntegerSchema(
      minimum: 1,
      description:
          'Root page size. Defaults to 50. Relations have their own page sizes.'),
  'cursor': StringSchema(
      description:
          'Opaque continuation for the same query over live data; it is not a transaction snapshot.'),
  'timeoutMs': IntegerSchema(
      minimum: 1,
      description:
          'Optional caller-selected execution budget in milliseconds. No deadline by default.'),
}, required: [
  'view'
]);

const stateQueryOutput = ObjectSchema({
  'schemaVersion':
      IntegerSchema(description: 'Public query envelope version; currently 1.'),
  'snapshotId': StringSchema(
      nullable: true,
      description:
          'Null: observations do not form a global transaction snapshot.'),
  'observedAt':
      StringSchema(description: 'UTC ISO-8601 response observation time.'),
  'consistency':
      StringSchema(description: 'Consistency and live pagination scope.'),
  'sources': ObjectSchema({},
      additionalProperties: true,
      description:
          'View name to UTC ISO-8601 read time; cached data can be older.'),
  'rows': ArraySchema(ObjectSchema({}, additionalProperties: true),
      description:
          'Public projections described by each registered view. Relations contain rows, truncated and nextQuery.'),
  'nextCursor': StringSchema(
      nullable: true,
      description:
          'Continuation for the same live query; null when no root continuation is known.'),
  'truncated': BooleanSchema(
      description: 'True when pagination or a resource limit omitted data.'),
  'warnings': ArraySchema(StringSchema(),
      description:
          'Omissions: time_limit (only with explicit timeoutMs), relation_limit, sort_within_scan_window (only after an explicit timeout).'),
}, required: [
  'schemaVersion',
  'snapshotId',
  'observedAt',
  'consistency',
  'sources',
  'rows',
  'nextCursor',
  'truncated',
  'warnings'
]);

final class StateCapability implements Capability {
  StateCapability(Iterable<StateView> views)
      : views = {for (final view in views) view.name: view} {
    actions = [_StateAction(this, false), _StateAction(this, true)];
  }
  final Map<String, StateView> views;
  @override
  late final List<Action> actions;

  StateView _view(String name) {
    final view = views[name];
    if (view == null) _invalid('unknown_view', 'Unknown public view.');
    return view!;
  }

  void _validate(StateView view, JsonMap query) {
    final violations = stateQueryInput.validate({'view': view.name, ...query});
    if (violations.isNotEmpty) {
      throw Failure(FailureCode.invalidInput, 'invalid_query',
          violations: violations);
    }
    void field(String name, {bool scalar = false}) {
      final schema = view.fields.properties[name];
      if (schema == null || schema.secret) {
        _invalid('unknown_field', 'Unknown public field.');
      }
      if (scalar && (schema is ObjectSchema || schema is ArraySchema)) {
        _invalid(
            'invalid_filter', 'Filtering and sorting require scalar fields.');
      }
    }

    for (final name in (query['select'] as List?) ?? []) {
      field(name as String);
    }
    final filter = query['filter'] as Map? ?? {};
    for (final e in filter.entries) {
      field(e.key as String);
      if (e.value is! Map || (e.value as Map).isEmpty) {
        _invalid('invalid_filter', 'Expected operator/value predicates.');
      }
      for (final predicate in (e.value as Map).entries) {
        if (!['eq', 'ne', 'in', 'contains', 'gt', 'gte', 'lt', 'lte']
            .contains(predicate.key)) {
          _invalid('invalid_filter', 'Unknown filter operator.');
        }
        final fieldSchema = view.fields.properties[e.key]!;
        if (fieldSchema is ObjectSchema || fieldSchema is ArraySchema && predicate.key != 'contains') {
          _invalid('invalid_filter', 'Objects cannot be filtered; arrays support contains only.');
        }
        final schema = fieldSchema is ArraySchema ? fieldSchema.items : fieldSchema;
        if (predicate.key == 'in') {
          if (predicate.value is! List) {
            _invalid('invalid_filter', 'in expects an array.');
          }
          for (final value in predicate.value as List) {
            if (value != null && schema.validate(value).isNotEmpty) {
              _invalid('invalid_filter',
                  'Filter value type differs from the field.');
            }
          }
        } else if (predicate.value != null &&
            schema.validate(predicate.value).isNotEmpty) {
          _invalid(
              'invalid_filter', 'Filter value type differs from the field.');
        }
        if (fieldSchema is! ArraySchema && predicate.key == 'contains' &&
            (schema is! StringSchema || predicate.value == null)) {
          _invalid('invalid_filter', 'contains requires a text field.');
        }
      }
    }
    for (final order in (query['orderBy'] as List?) ?? []) {
      field((order as Map)['field'] as String, scalar: true);
    }
    for (final e in (query['include'] as Map? ?? {}).entries) {
      final relation = view.relations[e.key];
      if (relation == null) {
        _invalid('unknown_relation', 'Unknown declared relation.');
      }
      if (e.value is! Map) {
        _invalid('invalid_query', 'Relation options must be an object.');
      }
      final child = Map<String, Object?>.from(e.value as Map);
      if (child.keys
          .any((key) => ['view', 'cursor', 'timeoutMs'].contains(key))) {
        _invalid('invalid_query',
            'Relation options cannot override view, cursor or timeout.');
      }
      _validate(_view(relation!.view), child);
    }
  }

  Future<JsonMap> query(JsonMap input) async {
    final view = _view(input['view'] as String);
    _validate(view, input);
    if (utf8.encode(jsonEncode(input)).length > 64 * 1024) {
      _invalid('input_limit', 'Query input exceeds 64 KiB.');
    }
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode({...input}..remove('cursor'))))
        .toString();
    var offset = 0;
    var sourceOffset = 0;
    if (input['cursor'] case final String cursor) {
      try {
        final decoded =
            jsonDecode(utf8.decode(base64Url.decode(cursor))) as Map;
        if (decoded['query'] != fingerprint ||
            decoded['offset'] is! int ||
            (decoded['offset'] as int) < 0 ||
            decoded['sourceOffset'] is! int ||
            (decoded['sourceOffset'] as int) < 0) {
          _invalid('invalid_cursor', 'Cursor belongs to another query.');
        }
        offset = decoded['offset'] as int;
        sourceOffset = decoded['sourceOffset'] as int;
      } on FormatException {
        _invalid('invalid_cursor', 'Malformed continuation.');
      } on TypeError {
        _invalid('invalid_cursor', 'Malformed continuation.');
      }
    }
    final context = _ReadContext(this, input['timeoutMs'] as int?);
    final source = await context.rows(view, startOffset: sourceOffset);
    final matched = _match(source, input);
    final rows = <JsonMap>[];
    var index = offset;
    final limit = input['limit'] as int? ?? 50;
    while (index < matched.length && rows.length < limit) {
      if (context.expired) {
        context.warnings.add('time_limit');
        break;
      }
      final row = await context.expand(view, matched[index], input);
      rows.add(row);
      index++;
    }
    final more = index < matched.length;
    if (context.expired) context.warnings.add('time_limit');
    final hasScanContinuation = context.incomplete.contains(view.name);
    if (hasScanContinuation && input.containsKey('orderBy')) {
      context.warnings.add('sort_within_scan_window');
    }
    return {
      'schemaVersion': 1,
      'snapshotId': null,
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'consistency':
          'Per-source observations of live state; no global transaction snapshot. Cursors paginate live observations.',
      'sources': context.observed,
      'rows': rows,
      'nextCursor': more || hasScanContinuation
          ? base64Url.encode(utf8.encode(jsonEncode({
              'query': fingerprint,
              'offset': more ? index : 0,
              'sourceOffset': more ? sourceOffset : sourceOffset + source.length
            })))
          : null,
      'truncated': more || context.warnings.isNotEmpty,
      'warnings': context.warnings.toList(),
    };
  }
}

void _invalid(String code, String message) =>
    throw Failure(FailureCode.invalidInput, '$code: $message');

List<JsonMap> _match(List<JsonMap> rows, JsonMap query) {
  final filter = query['filter'] as Map? ?? {};
  final found = rows
      .where((row) => filter.entries.every((e) {
            final actual = row[e.key];
            return (e.value as Map).entries.every((p) => switch (p.key) {
                  'eq' => actual == p.value,
                  'ne' => actual != p.value,
                  'in' => (p.value as List).contains(actual),
                  'contains' => actual is String &&
                      actual
                          .toLowerCase()
                          .contains((p.value as String).toLowerCase()) || actual is List && actual.contains(p.value),
                  'gt' => actual != null &&
                      p.value != null &&
                      _compare(actual, p.value) > 0,
                  'gte' => actual != null &&
                      p.value != null &&
                      _compare(actual, p.value) >= 0,
                  'lt' => actual != null &&
                      p.value != null &&
                      _compare(actual, p.value) < 0,
                  'lte' => actual != null &&
                      p.value != null &&
                      _compare(actual, p.value) <= 0,
                  _ => false
                });
          }))
      .toList();
  final order = query['orderBy'] as List? ?? [];
  final indexed = found.asMap().entries.toList();
  indexed.sort((a, b) {
    for (final raw in order) {
      final key = (raw as Map)['field'];
      final comparison = _compare(a.value[key], b.value[key]);
      if (comparison != 0) {
        return raw['direction'] == 'desc' ? -comparison : comparison;
      }
    }
    return a.key.compareTo(b.key);
  });
  return [for (final e in indexed) e.value];
}

int _compare(Object? a, Object? b) => a == b
    ? 0
    : a == null
        ? -1
        : b == null
            ? 1
            : a is num && b is num
                ? a.compareTo(b)
                : a.toString().compareTo(b.toString());

// Only schemas explicitly declaring additionalProperties expose open JSON facts.
Object? publicValue(Object? value, Schema schema) {
  if (schema.secret || value == null) return null;
  // JSON cannot represent non-finite measurements; null denotes unknown.
  if (value is num && !value.isFinite) return null;
  if (schema is ObjectSchema && value is! Map ||
      schema is ArraySchema && value is! List ||
      schema is StringSchema && value is! String ||
      schema is BooleanSchema && value is! bool ||
      (schema is NumberSchema || schema is IntegerSchema) && value is! num) {
    return null;
  }
  if (schema is ObjectSchema && value is Map) {
    return {
      if (schema.additionalProperties)
        for (final key in value.keys.cast<String>())
          if (!schema.properties.containsKey(key)) key: _publicJson(value[key]),
      for (final e in schema.properties.entries)
        if (!e.value.secret) e.key: publicValue(value[e.key], e.value)
    };
  }
  if (schema is ArraySchema && value is List) {
    return [for (final v in value) publicValue(v, schema.items)];
  }
  if (value is String) {
    if (!value.contains('://')) return value;
    // Public locator URLs contain no userinfo, query parameters or fragments.
    return value.replaceAllMapped(
        RegExp(
            r'''(?<![a-zA-Z0-9+.-])[a-zA-Z][a-zA-Z0-9+.-]{0,31}://[^\s<>"'\\]+'''),
        (match) {
      final uri = Uri.tryParse(match[0]!);
      return uri == null
          ? '[redacted-url]'
          : Uri(
                  scheme: uri.scheme,
                  host: uri.host,
                  port: uri.hasPort ? uri.port : null,
                  path: uri.path)
              .toString();
    });
  }
  if (value is num || value is bool) return value;
  return null;
}

Object? _publicJson(Object? value) => switch (value) {
      Map() => {
          for (final entry in value.entries)
            entry.key as String: _publicJson(entry.value)
        },
      List() => [for (final item in value) _publicJson(item)],
      String() => publicValue(value, const StringSchema()),
      num() => publicValue(value, const NumberSchema()),
      bool() => value,
      _ => null,
    };

JsonMap publicSchema(Schema schema) => {
      ...schema.toJsonSchema(),
      if (schema is ObjectSchema)
        'properties': {
          for (final field in schema.properties.entries)
            if (!field.value.secret) field.key: publicSchema(field.value)
        },
      if (schema is ArraySchema) 'items': publicSchema(schema.items),
      if (schema is ObjectSchema)
        'required': [
          for (final key in schema.required)
            if (schema.properties[key]?.secret != true) key
        ],
    };

final class _ReadContext {
  _ReadContext(this.capability, this.timeoutMs) : clock = Stopwatch()..start();
  final StateCapability capability;
  final int? timeoutMs;
  final Stopwatch clock;
  bool get expired =>
      timeoutMs != null && clock.elapsedMilliseconds >= timeoutMs!;
  final cache = <String, List<JsonMap>>{};
  final observed = <String, Object?>{};
  final warnings = <String>{};
  final incomplete = <String>{};
  Future<List<JsonMap>> _read(StateView view, int offset, int size) async {
    try {
      return await view.read(offset, size);
    } on Failure catch (failure) {
      if (['history_unavailable', 'classic_library_unavailable']
          .contains(failure.message)) {
        rethrow;
      }
      throw Failure(failure.code, 'state_source_failed',
          retryable: failure.retryable);
    }
  }

  Future<List<JsonMap>> rows(StateView view, {int startOffset = 0}) async {
    if (view.readAll != null) {
      if (!cache.containsKey(view.name)) {
        final Future<StateRows> pending;
        try {
          pending = view.readAll!();
          final source = timeoutMs == null ? await pending : await pending.timeout(
              Duration(milliseconds: (timeoutMs! - clock.elapsedMilliseconds).clamp(1, timeoutMs!)),
              onTimeout: () => const StateRows([], warnings: ['time_limit']));
          warnings.addAll(source.warnings);
          cache[view.name] = [for (final row in source.rows) publicValue(row, view.fields) as JsonMap];
        } on Failure catch (failure) {
          throw Failure(failure.code, 'state_source_failed', retryable: failure.retryable);
        }
        observed[view.name] = DateTime.now().toUtc().toIso8601String();
      }
      return cache[view.name]!.skip(startOffset).toList();
    }
    if (cache.containsKey(view.name)) return cache[view.name]!;
    final result = <JsonMap>[];
    var offset = startOffset;
    var complete = false;
    while (!expired) {
      const size = 500;
      final pending = _read(view, offset, size);
      final page = timeoutMs == null
          ? await pending
          : await pending.timeout(
              Duration(
                  milliseconds: (timeoutMs! - clock.elapsedMilliseconds)
                      .clamp(1, timeoutMs!)), onTimeout: () {
              warnings.add('time_limit');
              return [];
            });
      observed[view.name] = DateTime.now().toUtc().toIso8601String();
      for (final row in page) {
        result.add(publicValue(row, view.fields) as JsonMap);
      }
      offset += page.length;
      if (page.length < size && !warnings.contains('time_limit')) {
        complete = true;
        break;
      }
    }
    if (expired) warnings.add('time_limit');
    if (!complete) incomplete.add(view.name);
    return cache[view.name] = result;
  }

  Future<JsonMap> expand(StateView view, JsonMap row, JsonMap query) async {
    final select = (query['select'] as List?)?.cast<String>() ??
        view.fields.properties.entries
            .where((e) => !e.value.secret)
            .map((e) => e.key)
            .toList();
    final result = <String, Object?>{for (final key in select) key: row[key]};
    for (final e in (query['include'] as Map? ?? {}).entries) {
      final relation = view.relations[e.key]!;
      final target = capability._view(relation.view);
      final options = Map<String, Object?>.from(e.value as Map);
      final children = _match(
          (await rows(target))
              .where((child) =>
                  row[relation.localField] != null &&
                  child[relation.foreignField] == row[relation.localField])
              .toList(),
          options);
      final nested = <JsonMap>[];
      for (final child in children.take(options['limit'] as int? ?? 50)) {
        if (expired) break;
        nested.add(await expand(target, child, options));
      }
      result[e.key as String] = {
        'rows': nested,
        'truncated':
            nested.length < children.length || incomplete.contains(target.name),
        'nextQuery':
            nested.length < children.length || incomplete.contains(target.name)
                ? {
                    'view': target.name,
                    ...options,
                    'filter': {
                      ...?(options['filter'] as Map?),
                      relation.foreignField: {'eq': row[relation.localField]}
                    }
                  }
                : null
      };
      if (nested.length < children.length) warnings.add('relation_limit');
    }
    return result;
  }
}

final class _StateJson implements JsonEncodable {
  const _StateJson(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _StateAction extends Action<_StateJson, _StateJson> {
  const _StateAction(this.capability, this.isQuery);
  final StateCapability capability;
  final bool isQuery;
  @override
  ActionSpec get spec => ActionSpec(
        id: isQuery ? 'state.query' : 'state.describe',
        title: isQuery ? 'Query public state' : 'Describe public state',
        description: isQuery
            ? 'Read registered public state with filters, projections, sorting, pagination and declared relations. No filesystem scan, source refresh, network requests or business writes. Secrets and authentication data are excluded. Default page size 50; use limit and select for output size. No default deadline or scan/concurrency ceiling. Results report pagination and per-source observations; unknown fields/views and invalid cursors return invalid_input.'
            : 'Describe registered public views, field schemas, units, namespaces, relations and query limits. Contracts are generated from the same registrations that project query results. No business writes or network requests.',
        effect: Effect.read,
        input: isQuery
            ? stateQueryInput
            : const ObjectSchema({'view': StringSchema()}),
        output: isQuery
            ? stateQueryOutput
            : const ObjectSchema({}, additionalProperties: true),
      );
  @override
  _StateJson decodeInput(JsonMap json) => _StateJson(json);
  @override
  Future<Outcome<_StateJson>> run(
      _StateJson input, Invocation invocation) async {
    if (isQuery) {
      try {
        return Completed(_StateJson(await capability.query(input.json)));
      } on Failure {
        rethrow;
      } catch (_) {
        throw const Failure(FailureCode.internal, 'state_read_failed');
      }
    }
    final views = input.json['view'] == null
        ? capability.views.values
        : [capability._view(input.json['view'] as String)];
    return Completed(_StateJson({
      'views': [for (final view in views) view.describe()],
      'limits': {
        'defaultLimit': 50,
        'defaultTimeoutMs': null,
        'maxInputBytes': 64 * 1024
      }
    }));
  }
}
