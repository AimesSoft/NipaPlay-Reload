import 'package:nipa_harness/nipa_harness.dart';

import '../capabilities/classic_action.dart';
import 'rika_store.dart';
import 'store_fetch.dart';
import 'store_index.dart';

const _output = ObjectSchema({}, additionalProperties: true);
const _id = StringSchema(minLength: 1, maxLength: 64);
const storeAppliedEvent = 'store.applied';
const storeAppliedObject = 'local';

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
  StoreCapability(this.store, {Future<void> Function()? restart})
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'store.list',
                  title: '梨花的商店',
                  effect: Effect.read,
                  description:
                      'Official and installed skills and DSH plugins, with versions, enablement, updates and notices. loadedAtLastStart records skills added to the prompt and plugins passed to DSH, not a plugin health check; notLoadedAtLastStart gives reasons items were left out. refresh re-reads the official list now. Installed changes take effect when the conversation host next starts.',
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
                    return {'id': item.id, 'readme': await store.readme(item)};
                  })),
          ClassicAction(
              const ActionSpec(
                  id: 'store.install',
                  title: '从商店安装',
                  effect: Effect.write,
                  description:
                      'Install or update only what the user asked for. Before installing, tell the user the official item\'s notices or that the npm package is unreviewed and runs with their account permissions, including file reads/writes and network access. An official item requires the id and version whose notices were disclosed; a changed version is a conflict. The npm field accepts name or name@version. Plugins load only with DSH. Changes take effect on conversation-host start.',
                  input: ObjectSchema({
                    'id': _id,
                    'version': StringSchema(minLength: 1, maxLength: 64),
                    'npm': StringSchema(minLength: 1, maxLength: 260),
                  }),
                  output: _output), (input, _) {
            final id = input['id'] as String?, npm = input['npm'] as String?;
            final version = input['version'] as String?;
            if ((id == null) == (npm == null)) {
              throw const Failure(
                  FailureCode.invalidInput, 'Give exactly one of id or npm.');
            }
            if (id != null && version == null) {
              throw const Failure(FailureCode.invalidInput,
                  'Give the version from store.list whose notices the person was told.');
            }
            return _failures(() async {
              final installed = npm != null
                  ? await store.installNpm(npm)
                  : await store.installOfficial(id!, version: version!);
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
                        'Immediately restart the conversation host to apply extension changes. Ends active turns (including the caller, which may not receive the result) and running conversation helpers. Saved conversations, followup records and schedules survive; followups delivered into an interrupted turn may be interrupted too. A successful restart emits the durable followup event store.applied with objectId local. store.list reports extension selection and omissions at startup.',
                    input: ObjectSchema({}),
                    output: _output), (input, _) async {
              await restart();
              return {'restarted': true};
            }),
        ];

  final RikaStore store;
  @override
  final List<Action> actions;
}

JsonMap _installed(InstalledItem installed) => {
      'id': installed.item.id,
      'kind': installed.item.kind.name,
      'name': installed.item.name,
      'version': installed.item.version,
      'reviewed': installed.item.reviewed,
      'enabled': installed.enabled,
      'installedAt': installed.at.toIso8601String(),
    };

Future<JsonMap> _list(RikaStore store, bool refresh) async {
  final installed = {for (final i in await store.installed()) i.item.id: i};
  StoreIndex? list;
  try {
    list = await store.officialList(refresh: refresh);
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
      };
  return {
    'official': [
      for (final official in list?.items ?? const <StoreItem>[])
        {
          ...item(official),
          'installedVersion': installed[official.id]?.item.version,
          'enabled': installed[official.id]?.enabled,
          'updateAvailable': installed[official.id] != null &&
              installed[official.id]!.item.version != official.version,
        }
    ],
    'installed': [
      for (final i in installed.values)
        {
          ...item(i.item),
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
