import 'dart:convert';
import 'dart:io';

/// DeepSeek Harness (DSH) as Nipa's runtime instead of Codex.
///
/// Codex stays the default. `NIPAPLAY_AGENT_RUNTIME=dsh` selects DSH, with
/// `NIPAPLAY_DSH_NODE` (a Node.js 24 executable) and `NIPAPLAY_DSH_ROOT` (an
/// npm prefix holding `node_modules/@deepseek-ai/dsh`) or `NIPAPLAY_DSH_BIN`
/// (its `lib/bin.js`). A lab profile may instead keep the same choice in
/// `<lab root>/agent-runtime.json`: `{"runtime": "dsh", "node": ..., "root": ...}`.
/// Environment values win over the file.
final class DshRuntime {
  const DshRuntime(
      {required this.node, required this.bin, required this.version});

  /// Node.js executable that runs DSH.
  final String node;

  /// `@deepseek-ai/dsh/lib/bin.js`.
  final String bin;

  /// The installed `@deepseek-ai/dsh` version.
  final String version;

  static DshRuntime? select(Map<String, String> environment,
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

    final runtime = value('NIPAPLAY_AGENT_RUNTIME', 'runtime') ?? 'codex';
    if (runtime == 'codex') return null;
    if (runtime != 'dsh') {
      throw StateError('Unknown agent runtime "$runtime"; expected codex or dsh.');
    }
    final node = value('NIPAPLAY_DSH_NODE', 'node');
    final root = value('NIPAPLAY_DSH_ROOT', 'root');
    final bin = value('NIPAPLAY_DSH_BIN', 'bin') ??
        (root == null ? null : '$root/node_modules/@deepseek-ai/dsh/lib/bin.js');
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
    return DshRuntime(node: node, bin: bin, version: version ?? 'unknown');
  }
}

/// The model route DSH uses, read from the same Codex configuration a Codex
/// launch would use. The key stays in memory and reaches DSH only as the
/// environment value named by [keyVariable].
final class DshRoute {
  const DshRoute(
      {required this.baseUrl,
      required this.model,
      required this.key,
      this.api = 'openai-responses',
      this.reasoningEffort,
      this.contextWindow,
      this.maxRetries});

  static const keyVariable = 'NIPAPLAY_MODEL_API_KEY';
  static const provider = 'nipaplay';

  final String baseUrl, model, key, api;
  final String? reasoningEffort;
  final int? contextWindow, maxRetries;

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
                if (contextWindow != null) 'contextWindow': contextWindow,
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
