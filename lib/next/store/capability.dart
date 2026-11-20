import 'package:nipa_harness/nipa_harness.dart';

import '../capabilities/classic_action.dart';
import 'npm_package.dart';
import 'rika_store.dart';
import 'store_fetch.dart';
import 'store_index.dart';

const _output = ObjectSchema({}, additionalProperties: true);
const _id = StringSchema(minLength: 1, maxLength: 64);
const _npmSpec = StringSchema(minLength: 1, maxLength: 280);
const storeAppliedEvent = 'store.applied';
const storeAppliedObject = 'local';

final class StoreApplyResult {
  const StoreApplyResult.restarted({this.eventError})
      : status = 'restarted',
        reason = null,
        error = null;
  const StoreApplyResult.notRun(this.reason)
      : status = 'notRun',
        error = null,
        eventError = null;
  const StoreApplyResult.failed(this.error)
      : status = 'failed',
        reason = null,
        eventError = null;

  final String status;
  final String? reason, error, eventError;

  JsonMap toJson() => {
        'status': status,
        'restarted': status == 'restarted',
        if (reason != null) 'reason': reason,
        if (error != null) 'error': error,
        if (eventError != null) 'eventError': eventError,
      };
}

JsonMap storeAppliedFacts() {
  final now = DateTime.now().toUtc();
  return {
    'eventId': '$storeAppliedEvent-${now.microsecondsSinceEpoch}',
    'event': storeAppliedEvent,
    'objectId': storeAppliedObject,
    'occurredAt': now.toIso8601String(),
    'revision': null,
    'changedFields': <String>[],
    'facts': {'restarted': true},
  };
}

Future<T> _failures<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on StoreChanged catch (error) {
    throw Failure(FailureCode.conflict, error.message);
  } on StoreFormatException catch (error) {
    throw Failure(FailureCode.invalidInput, error.message);
  } on StoreFetchException catch (error) {
    throw Failure(FailureCode.unavailable, error.message);
  }
}

/// 梨花's store as actions, with an optional conversation-host restart.
final class StoreCapability implements Capability {
  StoreCapability(this.store, {Future<StoreApplyResult> Function()? restart})
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'store.list',
                  title: '梨花的商店',
                  effect: Effect.read,
                  description:
                      'Official and installed skills and DSH plugins, with version sources, version differences, enablement and notices. Different versions do not imply an upgrade. loadedAtLastStart records skills added to the prompt and plugins passed to DSH, not a plugin health check; notLoadedAtLastStart gives reasons items were left out. refresh re-reads the official list now. Installed changes take effect when the conversation host next starts.',
                  input: ObjectSchema({'refresh': BooleanSchema()}),
                  output: _output),
              (input, _) =>
                  _failures(() => _list(store, input['refresh'] == true))),
          ClassicAction(
              const ActionSpec(
                  id: 'store.readme',
                  title: '读取商店条目的说明',
                  effect: Effect.read,
                  description:
                      'The README of an item on the official list (what it does, its sources, limits, changelog), checked against the list.',
                  input: ObjectSchema({'id': _id}, required: ['id']),
                  output: _output),
              (input, _) => _failures(() async {
                    final list = await store.officialList();
                    final item = list.items
                            .where((i) => i.id == input['id'])
                            .firstOrNull ??
                        (throw StoreFormatException('官方列表里没有 ${input['id']}'));
                    return {
                      'id': item.id,
                      'version': item.version,
                      'readme': await store.readme(item)
                    };
                  })),
          ClassicAction(
              const ActionSpec(
                id: 'store.resolve_npm',
                title: '查看 npm 包的安装事实',
                effect: Effect.read,
                description:
                    'Read the requested tag or version, resolved version, tarball integrity (npm dist.integrity), root SKILL.md, DSH plugin declarations, deprecation and installability per kind without installing or running package code. An unspecified tag means latest. Package metadata is unreviewed.',
                input: ObjectSchema({'npm': _npmSpec}, required: ['npm']),
                output: _output,
              ),
              (input, _) => _resolveNpm(store, input['npm'] as String)),
          ClassicAction(
              const ActionSpec(
                  id: 'store.install',
                  title: '从商店安装',
                  effect: Effect.write,
                  description:
                      'Install or replace an extension at the user’s request. The user is informed of official notices or the npm package’s unreviewed status and account-level file and network permissions before installation. Official items are identified by id and version; npm items by package name, exact version, chosen kind and integrity from store.resolve_npm. An integrity change returns a conflict; preview again before installing. Plugins load only with DSH. Changes take effect on conversation-host start.',
                  input: ObjectSchema({
                    'id': _id,
                    'version': StringSchema(minLength: 1, maxLength: 64),
                    'npm': _npmSpec,
                    'kind': StringSchema(values: ['skill', 'plugin']),
                    'integrity': StringSchema(minLength: 1),
                  }),
                  output: _output), (input, _) {
            final id = input['id'] as String?, npm = input['npm'] as String?;
            final version = input['version'] as String?;
            final kind = input['kind'] as String?;
            final integrity = input['integrity'] as String?;
            if ((id == null) == (npm == null)) {
              throw const Failure(
                  FailureCode.invalidInput, 'Give exactly one of id or npm.');
            }
            if (version == null ||
                (npm != null) != (kind != null) ||
                (npm != null) != (integrity != null)) {
              throw const Failure(FailureCode.invalidInput,
                  'An exact version is required; kind and preview integrity are required only for npm.');
            }
            return _failures(() async {
              final installed = npm != null
                  ? await store.installNpm(npm,
                      version: version,
                      kind: StoreKind.values.byName(kind!),
                      expectedIntegrity: integrity)
                  : await store.installOfficial(id!, version: version);
              return {
                'installed': _installed(installed),
                'takesEffect': 'next conversation host start',
              };
            });
          }),
          ClassicAction(
              const ActionSpec(
                  id: 'store.enable',
                  title: '启用或停用已安装的扩展',
                  effect: Effect.write,
                  description:
                      'Turn an installed item on or off without removing it. Takes effect when the conversation host next starts.',
                  input: ObjectSchema({'id': _id, 'enabled': BooleanSchema()},
                      required: ['id', 'enabled']),
                  output: _output),
              (input, _) => _failures(() async => {
                    'installed': _installed(await store.setEnabled(
                        input['id'] as String, input['enabled'] as bool)),
                  })),
          ClassicAction(
              const ActionSpec(
                  id: 'store.remove',
                  title: '卸载扩展',
                  effect: Effect.destructive,
                  description:
                      'Remove an installed item and its files. Settings and sign-ins a plugin kept in DSH\'s own data stay. Takes effect when the conversation host next starts.',
                  input: ObjectSchema({'id': _id}, required: ['id']),
                  output: _output),
              (input, _) => _failures(() async {
                    await store.remove(input['id'] as String);
                    return {'removed': input['id']};
                  })),
          if (restart != null)
            ClassicAction(
                const ActionSpec(
                    id: 'store.apply',
                    title: '重启梨花使扩展生效',
                    effect: Effect.write,
                    description:
                        'Immediately restart the running conversation host to apply extension changes. Ends active turns (including the caller, which may not receive the result) and running conversation helpers. Saved conversations, followup records and schedules survive; deliveries into interrupted turns may be interrupted. The result distinguishes restarted, notRun with reason and failed with error. Successful restarts publish the durable store.applied followup event (objectId local); eventError reports publication failure separately. store.list reports extension selection and omissions at startup.',
                    input: ObjectSchema({}),
                    output: _output),
                (input, _) async => (await restart()).toJson()),
        ];

  final RikaStore store;
  @override
  final List<Action> actions;
}

Future<JsonMap> _resolveNpm(RikaStore store, String spec) async {
  final (name, requested) =
      await _failures(() async => NpmPackages.parseSpec(spec));
  try {
    final result = await store.resolveNpm(spec);
    return {
      'npm': name,
      'requested': requested,
      'version': result.version,
      'integrity': result.integrity,
      'hasSkill': result.hasSkill,
      'declaresDshPlugin': result.isPlugin,
      'deprecated': result.deprecated,
      'notices': result.notices,
      'installable': result.options.values.any((option) => option.item != null),
      'kinds': {
        for (final entry in result.options.entries)
          entry.key.name: {
            'installable': entry.value.item != null,
            if (entry.value.reason != null) 'reason': entry.value.reason,
          }
      },
    };
  } on Exception catch (error) {
    if (error is! StoreFormatException &&
        error is! StoreFetchException &&
        error is! FormatException) rethrow;
    return {
      'npm': name,
      'requested': requested,
      'installable': false,
      'reason': '$error'
    };
  }
}

JsonMap _installed(InstalledItem installed) => {
      'id': installed.item.id,
      'kind': installed.item.kind.name,
      'name': installed.item.name,
      'version': installed.item.version,
      'reviewed': installed.item.reviewed,
      if (installed.item.npmPackage case final name?) 'npmPackage': name,
      'enabled': installed.enabled,
      'installedAt': installed.at.toIso8601String(),
    };

Future<JsonMap> _list(RikaStore store, bool refresh) async {
  final installed = {for (final i in await store.installed()) i.item.id: i};
  StoreIndex? list;
  String? listSource;
  try {
    list = await store.officialList(refresh: refresh);
    listSource = store.listVersionSource;
  } on Object {
    // Installed items are known without the list.
  }
  JsonMap item(StoreItem item) => {
        'id': item.id,
        'kind': item.kind.name,
        'name': item.name,
        'version': item.version,
        'description': item.description,
        'author': item.author,
        'category': item.category,
        'notices': item.notices,
        'reviewed': item.reviewed,
        if (item.npmPackage case final name?) 'npmPackage': name,
      };
  InstalledItem? installedOfficial(String id) =>
      installed[id]?.item.reviewed == true ? installed[id] : null;
  return {
    'official': [
      for (final official in list?.items ?? const <StoreItem>[])
        {
          ...item(official),
          'versionSource': listSource,
          'installedVersion': installedOfficial(official.id)?.item.version,
          if (installedOfficial(official.id) != null)
            'installedVersionSource': 'installedRecord',
          'enabled': installedOfficial(official.id)?.enabled,
          'versionDiffers': installedOfficial(official.id) != null &&
              installedOfficial(official.id)!.item.version != official.version,
        }
    ],
    'installed': [
      for (final i in installed.values)
        {
          ...item(i.item),
          'versionSource': 'installedRecord',
          'origin': i.item.origin.name,
          'enabled': i.enabled,
          'installedAt': i.at.toIso8601String()
        }
    ],
    if (store.listProblem != null) 'listProblem': store.listProblem,
    if (store.loadedAtLastStart case final loaded?) 'loadedAtLastStart': loaded,
    if (store.notLoaded.isNotEmpty) 'notLoadedAtLastStart': store.notLoaded,
    if (store.unreadable.isNotEmpty) 'unreadable': store.unreadable,
  };
}
