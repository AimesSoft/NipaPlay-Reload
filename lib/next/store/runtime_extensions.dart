import 'package:nipa_harness/nipa_harness.dart';

import '../capabilities/classic_action.dart';
import '../chat/chat_host.dart';
import '../harness_redaction.dart';
import '../runtime/dsh_install.dart';
import '../runtime/runtime_install_exception.dart';

const _output = ObjectSchema({}, additionalProperties: true);
const _name = StringSchema(minLength: 1, maxLength: 512);

final class RuntimeExtensions {
  RuntimeExtensions(
      {required this.host, required this.installer, required this.openUrl});

  final ChatHost? Function() host;
  final DshInstall? Function() installer;

  /// Opens a page in the system browser; null on a host without one (the
  /// headless host must not link Flutter plugins).
  final Future<bool> Function(Uri)? Function() openUrl;

  Future<JsonMap> webState() async => {
        ...?await installer()?.webState(),
        'ready': host()?.dshWebUri != null,
      };

  Future<JsonMap> dshPlugins() async {
    final current = host();
    if (current?.dsh == null || current?.available != true) return {};
    return current!.extensionRequest('nipa/plugins/list', {});
  }

  Future<JsonMap> codexPlugins() async {
    final current = host();
    if (current == null || current.dsh != null || !current.available) return {};
    final account =
        await current.extensionRequest('account/read', {'refreshToken': false});
    final signedIn = (account['account'] as Map?)?['type'] == 'chatgpt';
    final result = await current.extensionRequest('plugin/list', {
      if (!signedIn || !current.canManageCodexPlugins)
        'marketplaceKinds': ['local'],
    });
    return {...result, 'writable': current.canManageCodexPlugins};
  }

  ChatHost requireHost({required bool dsh}) {
    final current = host();
    if (current == null || !current.available || (current.dsh != null) != dsh) {
      throw const Failure(FailureCode.unavailable, '所需运行器未运行。');
    }
    return current;
  }

  Future<String> thread(ChatHost current, JsonMap input) async {
    if (input['threadId'] case final String id) return id;
    if (current.threadId == null) await current.getMainSession();
    return current.threadId!;
  }
}

final class RuntimeExtensionCapability implements Capability {
  RuntimeExtensionCapability(this.extensions);
  final RuntimeExtensions extensions;

  @override
  late final List<Action> actions = [
    ClassicAction(
        const ActionSpec(
            id: 'store.web.open',
            title: '打开 DSH Web',
            effect: Effect.read,
            description:
                'Reports the local DSH Web entry. A click in the application opens the authenticated site without returning credentials.',
            input: ObjectSchema({}),
            output: _output), (_, invocation) async {
      final url = extensions.host()?.dshWebUri;
      if (url == null)
        throw const Failure(FailureCode.unavailable, 'DSH Web 尚未启动。');
      if (invocation.origin == 'gui') {
        bool opened;
        try {
          opened = await extensions.openUrl()?.call(url) ?? false;
        } catch (_) {
          opened = false;
        }
        if (!opened) throw const Failure(FailureCode.unavailable, '无法打开浏览器。');
      }
      return {'entry': '设置 › 梨花 › 扩展 › 打开 DSH Web'};
    }),
    ClassicAction(
        const ActionSpec(
            id: 'store.commands.list',
            title: '列出斜杠命令',
            effect: Effect.read,
            description:
                'Lists DSH commands available to the specified conversation, or the selected conversation.',
            input: ObjectSchema({'threadId': _name}),
            output: _output), (input, _) async {
      final current = extensions.requireHost(dsh: true);
      return current.dshCommands(await extensions.thread(current, input));
    }),
    ClassicAction(
        const ActionSpec(
            id: 'store.commands.execute',
            title: '执行斜杠命令',
            effect: Effect.write,
            description:
                'Executes a DSH command without sending the line to the model. Shows the result in the matching local conversation and returns only the command status and non-link text.',
            input: ObjectSchema({
              'threadId': _name,
              'line': StringSchema(minLength: 2, maxLength: 8192)
            }, required: [
              'line'
            ]),
            output: _output), (input, _) async {
      final current = extensions.requireHost(dsh: true);
      final result = await current.runDshCommand(
          await extensions.thread(current, input), input['line'] as String,
          showInChat: true);
      return {
        'kind': result['kind'],
        'text': redactHarnessText((result['text'] as String? ?? '').replaceAll(
            RegExp(r'https?://[^\s<>]+', caseSensitive: false), '［链接仅在对话界面显示］'))
      };
    }),
    ClassicAction(
        const ActionSpec(
            id: 'store.codex.list',
            title: '列出 Codex 插件',
            effect: Effect.read,
            description:
                'Lists Codex marketplaces and plugins as reported by the running Codex process.',
            input: ObjectSchema({}),
            output: _output),
        (_, __) => extensions.codexPlugins()),
    ClassicAction(
        const ActionSpec(
            id: 'store.codex.marketplace.add',
            title: '添加 Codex 插件市场',
            effect: Effect.write,
            description:
                'Registers a user-supplied, unreviewed Codex marketplace in NipaPlay’s managed configuration.',
            input: ObjectSchema({'source': _name}, required: ['source']),
            output: _output),
        (input, _) async => {
              ...await extensions
                  .requireHost(dsh: false)
                  .extensionRequest('marketplace/add', input),
              'reviewed': false,
            }),
    ClassicAction(
        const ActionSpec(
            id: 'store.codex.install',
            title: '安装 Codex 插件',
            effect: Effect.write,
            description:
                'Installs a plugin from a Codex marketplace by its reported name and marketplace. Does not write existing configuration.',
            input: ObjectSchema({'marketplace': _name, 'plugin': _name},
                required: ['marketplace', 'plugin']),
            output: _output), (input, _) async {
      final current = extensions.requireHost(dsh: false);
      final catalog = await extensions.codexPlugins();
      final market = (catalog['marketplaces'] as List? ?? const [])
          .whereType<Map>()
          .where((market) => market['name'] == input['marketplace'])
          .firstOrNull;
      if (market == null ||
          !(market['plugins'] as List)
              .whereType<Map>()
              .any((plugin) => plugin['name'] == input['plugin'])) {
        throw const Failure(FailureCode.notFound, '市场中没有这个插件。');
      }
      return current.extensionRequest('plugin/install', {
        'pluginName': input['plugin'],
        if (market['path'] case final String path)
          'marketplacePath': path
        else
          'remoteMarketplaceName': market['name'],
      });
    }),
    ClassicAction(
        const ActionSpec(
            id: 'store.codex.remove',
            title: '卸载 Codex 插件',
            effect: Effect.destructive,
            description:
                'Uninstalls a plugin from the managed Codex configuration by its reported identity.',
            input: ObjectSchema({'id': _name}, required: ['id']),
            output: _output),
        (input, _) => extensions
            .requireHost(dsh: false)
            .extensionRequest('plugin/uninstall', {'pluginId': input['id']})),
  ];
}

Future<void> installStoreWeb(
    RuntimeExtensions extensions, String version) async {
  try {
    final installer = extensions.installer();
    if (installer == null)
      throw const RuntimeInstallException('此宿主没有 DSH 安装器。');
    await installer.installWeb(version);
  } on RuntimeInstallException catch (error) {
    throw Failure(FailureCode.unavailable, error.message);
  }
}
