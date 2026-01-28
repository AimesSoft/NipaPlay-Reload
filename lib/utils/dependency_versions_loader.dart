import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

class DependencyEntry {
  const DependencyEntry({
    required this.name,
    required this.version,
    required this.dependency,
    required this.source,
    this.repositoryUrl,
  });

  final String name;
  final String version;
  final String dependency;
  final String source;
  final String? repositoryUrl;

  String get githubUrl {
    final repoUrl = repositoryUrl;
    if (repoUrl != null && repoUrl.contains('github.com')) {
      return repoUrl;
    }
    return 'https://github.com/search?q=${Uri.encodeComponent(name)}';
  }
}

class DependencyVersionsLoader {
  static Future<List<DependencyEntry>> load() async {
    final lockContent = await rootBundle.loadString('pubspec.lock');
    final lockYaml = loadYaml(lockContent);
    if (lockYaml is! YamlMap) {
      return [];
    }
    final packages = lockYaml['packages'];
    if (packages is! YamlMap) {
      return [];
    }

    final Map<String, String?> pathRepoCache = {};
    final List<DependencyEntry> entries = [];

    for (final entry in packages.entries) {
      final name = entry.key.toString();
      final data = entry.value;
      if (data is! YamlMap) {
        continue;
      }
      final version = data['version']?.toString() ?? '未知';
      final dependency = data['dependency']?.toString() ?? '';
      final source = data['source']?.toString() ?? '';
      final description = data['description'];
      final repositoryUrl = await _resolveRepositoryUrl(
        source,
        description,
        pathRepoCache,
      );

      entries.add(
        DependencyEntry(
          name: name,
          version: version,
          dependency: dependency,
          source: source,
          repositoryUrl: repositoryUrl,
        ),
      );
    }

    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }
}

Future<String?> _resolveRepositoryUrl(
  String source,
  dynamic description,
  Map<String, String?> pathRepoCache,
) async {
  if (source == 'git' && description is YamlMap) {
    final url = description['url']?.toString();
    if (url != null && url.trim().isNotEmpty) {
      return _normalizeGitUrl(url);
    }
  }

  if (source == 'path' && description is YamlMap) {
    final path = description['path']?.toString();
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    if (pathRepoCache.containsKey(path)) {
      return pathRepoCache[path];
    }
    final pubspecPath = _ensureTrailingSlash(path) + 'pubspec.yaml';
    try {
      final content = await rootBundle.loadString(pubspecPath);
      final yaml = loadYaml(content);
      if (yaml is YamlMap) {
        final repoUrl = _extractRepositoryUrl(yaml);
        pathRepoCache[path] = repoUrl;
        return repoUrl;
      }
    } catch (_) {
      pathRepoCache[path] = null;
    }
  }

  return null;
}

String _ensureTrailingSlash(String path) {
  return path.endsWith('/') ? path : '$path/';
}

String? _extractRepositoryUrl(YamlMap yaml) {
  final candidates = [
    yaml['repository']?.toString(),
    yaml['homepage']?.toString(),
    yaml['issue_tracker']?.toString(),
  ];
  for (final candidate in candidates) {
    if (candidate == null) {
      continue;
    }
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    return _normalizeGitUrl(trimmed);
  }
  return null;
}

String _normalizeGitUrl(String url) {
  var normalized = url.trim();
  if (normalized.startsWith('git@github.com:')) {
    normalized = normalized.replaceFirst(
      'git@github.com:',
      'https://github.com/',
    );
  }
  if (normalized.startsWith('ssh://git@github.com/')) {
    normalized = normalized.replaceFirst(
      'ssh://git@github.com/',
      'https://github.com/',
    );
  }
  if (normalized.endsWith('.git')) {
    normalized = normalized.substring(0, normalized.length - 4);
  }
  return normalized;
}
