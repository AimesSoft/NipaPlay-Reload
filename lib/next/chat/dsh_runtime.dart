import 'dart:convert';
import 'dart:io';

/// Which runtime Nipa thinks in: DeepSeek Harness or Codex.
enum AgentRuntimeKind { dsh, codex }

/// What the environment or a lab profile fixes about the runtime, if
/// anything. `NIPAPLAY_AGENT_RUNTIME` (`dsh` or `codex`) wins over a lab's
/// `<lab root>/agent-runtime.json` (`{"runtime": "dsh", "node": ..., "root": ...}`).
/// With DSH, `NIPAPLAY_DSH_NODE` (a Node.js 24 executable) and
/// `NIPAPLAY_DSH_ROOT` (an npm prefix holding `node_modules/@deepseek-ai/dsh`)
/// or `NIPAPLAY_DSH_BIN` (its `lib/bin.js`) name an installation of your own;
/// without them NipaPlay's own downloaded runtime is used. Nothing fixed
/// leaves the choice to the person at this device (settings).
final class AgentRuntimeFixed {
  const AgentRuntimeFixed(this.kind, [this.dsh]);

  final AgentRuntimeKind? kind;

  /// The installation named by the environment or the file, when it names one.
  final DshRuntime? dsh;

  static AgentRuntimeFixed read(Map<String, String> environment,
      {Directory? labRoot}) {
    Map<String, Object?> file = const {};
    if (labRoot != null) {
      final config = File('${labRoot.path}/agent-runtime.json');
      if (config.existsSync()) {
        file = Map<String, Object?>.from(
            jsonDecode(config.readAsStringSync()) as Map);
      }
    }
    String? value(String key, String fileKey) {
      final text = environment[key] ?? file[fileKey] as String?;
      return text == null || text.isEmpty ? null : text;
    }

    final runtime = value('NIPAPLAY_AGENT_RUNTIME', 'runtime');
    if (runtime == null) return const AgentRuntimeFixed(null);
    if (runtime == 'codex') return const AgentRuntimeFixed(AgentRuntimeKind.codex);
    if (runtime != 'dsh') {
      throw StateError('Unknown agent runtime "$runtime"; expected codex or dsh.');
    }
    final node = value('NIPAPLAY_DSH_NODE', 'node');
    final root = value('NIPAPLAY_DSH_ROOT', 'root');
    final bin = value('NIPAPLAY_DSH_BIN', 'bin') ??
        (root == null ? null : '$root/node_modules/@deepseek-ai/dsh/lib/bin.js');
    if (node == null && bin == null) {
      return const AgentRuntimeFixed(AgentRuntimeKind.dsh);
    }
    if (node == null || bin == null) {
      throw StateError('DSH needs NIPAPLAY_DSH_NODE and NIPAPLAY_DSH_ROOT '
          '(or NIPAPLAY_DSH_BIN).');
    }
    if (!File(node).existsSync()) throw StateError('No Node.js at $node.');
    if (!File(bin).existsSync()) throw StateError('No DSH launcher at $bin.');
    final package = File('${File(bin).parent.parent.path}/package.json');
    final version = package.existsSync()
        ? (jsonDecode(package.readAsStringSync()) as Map)['version'] as String?
        : null;
    return AgentRuntimeFixed(AgentRuntimeKind.dsh,
        DshRuntime(node: node, bin: bin, version: version ?? 'unknown'));
  }
}

/// DeepSeek Harness (DSH) as Nipa's runtime instead of Codex. See
/// [AgentRuntimeFixed] for the environment and lab-file overrides.
final class DshRuntime {
  const DshRuntime(
      {required this.node, required this.bin, required this.version});

  /// Node.js executable that runs DSH.
  final String node;

  /// `@deepseek-ai/dsh/lib/bin.js`.
  final String bin;

  /// The installed `@deepseek-ai/dsh` version.
  final String version;

  /// The installation the environment or a lab file names; null when neither
  /// selects DSH with its own paths.
  static DshRuntime? select(Map<String, String> environment,
          {Directory? labRoot}) =>
      AgentRuntimeFixed.read(environment, labRoot: labRoot).dsh;
}

/// The model route DSH uses: what the person set up in NipaPlay's settings,
/// or what a Codex configuration holds ([fromCodexConfig]). The key stays in
/// memory and reaches DSH only as the environment value named by [keyVariable].
final class DshRoute {
  const DshRoute(
      {required this.baseUrl,
      required this.model,
      required this.key,
      this.api = 'openai-responses',
      this.reasoningEffort,
      this.contextWindow,
      this.maxRetries,
      this.imageInput,
      this.compat});

  static const keyVariable = 'NIPAPLAY_MODEL_API_KEY';
  static const provider = 'nipaplay';

  final String baseUrl, model, key, api;
  final String? reasoningEffort;
  final int? contextWindow, maxRetries;

  /// pi-ai wire-compatibility switches for the model, as a template or the
  /// person set them (e.g. DeepSeek's `thinkingFormat`); never inferred from
  /// the address.
  final Map<String, Object?>? compat;

  /// Whether the model answered about an image it was shown
  /// ([probeDshImageInput]); null when that is not known. DSH's `read_image`
  /// hands images only to a model declared to take them.
  final bool? imageInput;

  DshRoute withImageInput(bool? value) => DshRoute(
      baseUrl: baseUrl,
      model: model,
      key: key,
      api: api,
      reasoningEffort: reasoningEffort,
      contextWindow: contextWindow,
      maxRetries: maxRetries,
      imageInput: value,
      compat: compat);

  /// [config] is a Codex `config.toml`. [model] and [provider] override its
  /// top-level choice, as a NipaPlay-managed launch does. The credential is
  /// [key], else the provider's `experimental_bearer_token`, else the
  /// variable its `env_key` names in [environment], else `OPENAI_API_KEY` from
  /// [auth] (the home's auth.json).
  static DshRoute fromCodexConfig(String config,
      {String? model,
      String? provider,
      String? key,
      Map<String, String> environment = const {},
      Map<String, Object?>? auth}) {
    final toml = readCodexToml(config);
    final chosen = provider ?? toml['model_provider'] as String?;
    final table = chosen == null
        ? null
        : (toml['model_providers'] as Map?)?[chosen] as Map?;
    if (table == null || table['base_url'] is! String) {
      throw StateError('DSH needs a Codex model_providers entry with base_url '
          '(provider ${chosen ?? 'unset'}).');
    }
    final wire = table['wire_api'] as String? ?? 'responses';
    final envKey = table['env_key'] as String?;
    final credential = key ??
        table['experimental_bearer_token'] as String? ??
        (envKey == null ? null : environment[envKey]) ??
        auth?['OPENAI_API_KEY'] as String?;
    if (credential == null || credential.isEmpty) {
      throw StateError('No credential for model provider $chosen.');
    }
    final name = model ?? toml['model'] as String?;
    if (name == null) throw StateError('No model in the Codex configuration.');
    return DshRoute(
        baseUrl: (table['base_url'] as String).replaceFirst(RegExp(r'/$'), ''),
        model: name,
        key: credential,
        api: wire == 'chat' ? 'openai-completions' : 'openai-responses',
        reasoningEffort: toml['model_reasoning_effort'] as String?,
        contextWindow: (toml['model_context_window'] as num?)?.toInt(),
        maxRetries: (table['request_max_retries'] as num?)?.toInt());
  }

  /// The `llm-pi-ai` route configuration: no secret, only the variable name.
  Map<String, Object?> get piAiConfig => {
        'providers': {
          provider: {
            'api': api,
            'baseURL': baseUrl,
            'apiKeyEnv': keyVariable,
            'retryPolicy': {'mode': 'normal', 'maxRetries': maxRetries ?? 3},
            'models': [
              {
                'id': model,
                if (imageInput != null)
                  'input': imageInput! ? ['text', 'image'] : ['text'],
                if (contextWindow != null) 'contextWindow': contextWindow,
                if (compat != null && compat!.isNotEmpty) 'compat': compat,
                if (reasoningEffort != null)
                  'reasoningEfforts': {
                    for (final level in {'low', 'medium', 'high', reasoningEffort!})
                      level: level,
                  },
              }
            ],
          }
        }
      };
}

/// Sends the model one small image, solid red, and asks its colour: whether
/// it answers about it is what [DshRoute.imageInput] records. Kept in
/// [cache] per endpoint, model and wire API; an unanswered probe (network,
/// timeout, server error) is not kept, so the next launch asks again.
/// [send] posts a JSON body and returns the status and body; tests replace it.
Future<bool?> probeDshImageInput(DshRoute route, File cache,
    {Future<(int, String)> Function(Uri uri, Map<String, Object?> body,
            Map<String, String> headers)?
        send,
    Duration timeout = const Duration(seconds: 8)}) async {
  final id = '${route.api}|${route.baseUrl}|${route.model}';
  try {
    final kept = jsonDecode(await cache.readAsString()) as Map;
    if (kept['route'] == id && kept['imageInput'] is bool) {
      return kept['imageInput'] as bool;
    }
  } catch (_) {}
  const question = 'What colour is this image? Answer with one word.';
  final image = 'data:image/png;base64,$_redPng';
  final responses = route.api == 'openai-responses';
  final uri =
      Uri.parse('${route.baseUrl}/${responses ? 'responses' : 'chat/completions'}');
  final body = responses
      ? <String, Object?>{
          'model': route.model,
          'input': [
            {
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': question},
                {'type': 'input_image', 'image_url': image},
              ],
            }
          ],
          'max_output_tokens': 64,
        }
      : <String, Object?>{
          'model': route.model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': question},
                {
                  'type': 'image_url',
                  'image_url': {'url': image}
                },
              ],
            }
          ],
          'max_tokens': 64,
        };
  final (int, String) reply;
  try {
    reply = await (send ?? _postJson)(uri, body, {
      'Authorization': 'Bearer ${route.key}',
      'Content-Type': 'application/json',
    }).timeout(timeout);
  } catch (_) {
    return null;
  }
  final (status, text) = reply;
  if (status >= 500 || status == 429) return null;
  bool sawRed = false;
  if (status == 200) {
    try {
      final decoded = jsonDecode(text) as Map;
      final words = <String>[];
      for (final item in (decoded['output'] as List? ?? const [])) {
        for (final part in ((item as Map)['content'] as List? ?? const [])) {
          if ((part as Map)['text'] case final String t) words.add(t);
        }
      }
      for (final choice in (decoded['choices'] as List? ?? const [])) {
        if (((choice as Map)['message'] as Map?)?['content'] case final String t) {
          words.add(t);
        }
      }
      final answer = words.join(' ').toLowerCase();
      sawRed = answer.contains('red') || answer.contains('红');
    } catch (_) {}
  }
  try {
    await cache.parent.create(recursive: true);
    await cache.writeAsString(jsonEncode({
      'route': id,
      'imageInput': sawRed,
      'status': status,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
    }));
  } catch (_) {}
  return sawRed;
}

Future<(int, String)> _postJson(
    Uri uri, Map<String, Object?> body, Map<String, String> headers) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    headers.forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  } finally {
    client.close(force: true);
  }
}

/// 8×8, solid red.
const _redPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC';

/// DSH rows that upload sessions or package lists, ask for DeepSeek accounts,
/// or offer tools Nipa does not use; see lib/next/chat/README.md.
const dshDisabledRows = [
  'session-log-deepseek',
  'plugin-package-inventory-deepseek',
  'session-telemetry-otel',
  'command-feedback',
  'deepseek-account',
  'llm-deepseek-account',
  'sdk-jsonrpc-server',
  'tool-fs-search',
  'tool-working-directory',
  'plan-mode',
  'skill',
  'skill-filesystem',
  'tool-skill',
  'ptc-runtime',
  'workflow-ptc',
  'tool-workflow',
  'goal',
  'goal-round-driver',
  'command-goal',
  'tool-goal',
  'workspace-dependencies',
  'skill-office',
];

/// The `--patch` overlay over DSH's `sdk` profile. Plugin paths are absolute;
/// the overlay carries no credential.
List<Map<String, Object?>> dshPatch(
        {required DshRoute route,
        required Directory plugins,
        required String personaPrefix,
        required String personaSuffix,
        required String harness,
        required String version,
        bool webSearch = false}) =>
    [
      for (final id in dshDisabledRows) {'id': id, 'disabled': true},
      {'id': 'llm-pi-ai', 'config': route.piAiConfig},
      // DSH's own prompt and tool guidance stay; Nipa is its persona.
      {
        'id': 'system-prompt',
        'config': {'personaPrefix': personaPrefix, 'personaSuffix': personaSuffix}
      },
      {
        'id': 'tool-fs',
        'config': {'read': true, 'readImage': true, 'write': true, 'edit': false}
      },
      {
        'id': 'agent-instructions',
        'config': {
          'maxBytes': 65536,
          'instructionFileCandidates': ['AGENTS.md'],
          'localInstructionFileCandidates': <String>[],
        }
      },
      {
        'id': 'tool-web',
        'config': {'search': webSearch, 'fetch': true}
      },
      {
        'insert': [
          {
            'id': 'nipa-memory',
            'name': '${plugins.absolute.path}/nipa-memory.mjs',
            'config': {'harness': harness},
          },
          {
            'id': 'nipa-app-server',
            'name': '${plugins.absolute.path}/nipa-app-server.mjs',
            'inject': ['sdkAppStartup', 'loader'],
            'config': {
              'provider': DshRoute.provider,
              'model': route.model,
              'cwd': harness,
              'dshVersion': version,
              if (route.reasoningEffort != null)
                'reasoningEffort': route.reasoningEffort,
            },
          },
        ]
      },
    ];

/// The subset of TOML that Codex configuration files use here: tables
/// (including quoted keys), strings, numbers and booleans. Arrays, inline
/// tables and multi-line strings are kept as their raw text.
Map<String, Object?> readCodexToml(String text) {
  final root = <String, Object?>{};
  var table = root;
  for (final raw in const LineSplitter().convert(text)) {
    final line = _stripComment(raw).trim();
    if (line.isEmpty) continue;
    if (line.startsWith('[')) {
      final end = line.lastIndexOf(']');
      final inner = line.startsWith('[[')
          ? line.substring(2, end - 1)
          : line.substring(1, end);
      table = root;
      for (final key in _keys(inner)) {
        table = (table[key] ??= <String, Object?>{}) as Map<String, Object?>;
      }
      continue;
    }
    final equals = _unquotedIndex(line, '=');
    if (equals < 0) continue;
    final keys = _keys(line.substring(0, equals));
    var target = table;
    for (final key in keys.take(keys.length - 1)) {
      target = (target[key] ??= <String, Object?>{}) as Map<String, Object?>;
    }
    target[keys.last] = _value(line.substring(equals + 1).trim());
  }
  return root;
}

String _stripComment(String line) {
  final index = _unquotedIndex(line, '#');
  return index < 0 ? line : line.substring(0, index);
}

int _unquotedIndex(String text, String char) {
  String? quote;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quote != null) {
      if (c == '\\' && quote == '"') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == char) {
      return i;
    }
  }
  return -1;
}

/// Index of the quote closing the string that [text] opens.
int _closingQuote(String text) {
  final quote = text[0];
  for (var i = 1; i < text.length; i++) {
    if (quote == '"' && text[i] == '\\') {
      i++;
    } else if (text[i] == quote) {
      return i;
    }
  }
  throw FormatException('Unterminated string', text);
}

List<String> _keys(String text) {
  final keys = <String>[];
  var rest = text.trim();
  while (rest.isNotEmpty) {
    String key;
    if (rest.startsWith('"') || rest.startsWith("'")) {
      final end = _closingQuote(rest);
      key = _value(rest.substring(0, end + 1)) as String;
      rest = rest.substring(end + 1).trim();
    } else {
      final dot = rest.indexOf('.');
      key = (dot < 0 ? rest : rest.substring(0, dot)).trim();
      rest = dot < 0 ? '' : rest.substring(dot);
    }
    keys.add(key);
    if (rest.startsWith('.')) rest = rest.substring(1).trim();
  }
  return keys;
}

Object? _value(String text) {
  if (text.startsWith('"""') || text.startsWith("'''")) return text;
  if (text.startsWith('"')) {
    return jsonDecode(text.substring(0, _closingQuote(text) + 1)) as String;
  }
  if (text.startsWith("'")) return text.substring(1, _closingQuote(text));
  if (text == 'true' || text == 'false') return text == 'true';
  return int.tryParse(text.replaceAll('_', '')) ??
      double.tryParse(text.replaceAll('_', '')) ??
      text;
}
