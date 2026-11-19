import 'package:nipa_harness/nipa_harness.dart';

import '../capabilities/classic_action.dart';
import 'rika_store.dart';
import 'store_fetch.dart';
import 'store_index.dart';

const _output = ObjectSchema({}, additionalProperties: true);
const _id = StringSchema(minLength: 1, maxLength: 64);

/// The person, at this device's interface: not the agent, nor anything
/// arriving over Mesh (another device's agent included).
bool _person(Invocation invocation) => invocation.origin == 'gui';

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

/// 梨花's store as actions: the official list and what is installed, read
/// by anyone; installing from the list by anyone; installing an npm package
/// nobody reviewed only by the person; and [restart], when given, so what
/// changed takes effect.
final class StoreCapability implements Capability {
  StoreCapability(this.store, {Future<void> Function()? restart})
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'store.list',
                  title: '梨花的商店',
                  effect: Effect.read,
                  description:
                      'The official list of skills (instructions and scripts you run) and DSH plugins (model providers) in 梨花\'s store, and what this host has installed, with installed version, enabled state and whether the list has a newer version. Official items are reviewed and pinned; items from npm are not reviewed. refresh re-reads the list now (otherwise at most every 10 minutes). Installed changes take effect when the conversation host next starts.',
                  input: ObjectSchema({'refresh': BooleanSchema()}),
                  output: _output),
              (input, _) => _failures(() => _list(store, input['refresh'] == true))),
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
                      'Install or update an item of the official list (id), or an npm package (npm: "name" or "name@version"). An npm package is not reviewed: only the person may install one, from this device\'s store UI (or, headless, the host\'s --store-install-npm). An official item needs its version from store.list, the one whose notices the person was told; a newer listing is a conflict. Plugins load only with the DSH runtime. Install only what the person asked for, after telling them the item\'s notices (store.list). Takes effect when the conversation host next starts.',
                  input: ObjectSchema({
                    'id': _id,
                    'version': StringSchema(minLength: 1, maxLength: 64),
                    'npm': StringSchema(minLength: 1, maxLength: 260),
                  }),
                  output: _output), (input, invocation) {
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
            if (npm != null && !_person(invocation)) {
              throw const Failure(FailureCode.invalidInput,
                  'Only the person may install an npm package nobody reviewed; tell them where to do it (设置 › 梨花 › 扩展, or nipaplay-headless --store-install-npm).');
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
                        'Restart the conversation host so installed, removed or switched items take effect. Ends any turn in progress; only the person may ask for it.',
                    input: ObjectSchema({}),
                    output: _output), (input, invocation) async {
              if (!_person(invocation)) {
                throw const Failure(FailureCode.invalidInput,
                    'Restarting ends your own turn; ask the person to apply it from the store.');
              }
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
        {...item(i.item), 'enabled': i.enabled, 'installedAt': i.at.toIso8601String()}
    ],
    if (store.listProblem != null) 'listProblem': store.listProblem,
    if (store.notLoaded.isNotEmpty) 'notLoadedAtLastStart': store.notLoaded,
    if (store.unreadable.isNotEmpty) 'unreadable': store.unreadable,
  };
}
