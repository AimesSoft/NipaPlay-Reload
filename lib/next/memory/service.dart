import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';

import '../harness_redaction.dart';
import '../repository_location.dart';
import '../settings/registry.dart';

abstract interface class MemoryData {
  Future<List<JsonMap>> list();
  Future<JsonMap> read(String path);
  Future<JsonMap> delete(String path, String revision, Invocation invocation);
  Future<JsonMap> edit(
      String path, String content, String revision, Invocation invocation);
}

/// Markdown remains the source of truth; no extracted memory or transcript store.
final class HarnessMemory implements MemoryData {
  HarnessMemory(this.location, this.settings, this.report);
  final RepositoryLocation location;
  final SettingsRegistry settings;
  final Future<JsonMap> Function(JsonMap, Invocation) report;
  Future<JsonMap> Function(String?)? recent;
  Future<void> _pending = Future.value();
  final _seen = <String, Map<String, String>>{};
  static const preferenceBytes = 8192;
  static const indexBytes = 8192;
  static const recentCharacters = 4200;

  Future<File> _file(String path) async {
    await location.ready;
    final parts = path.split('/');
    if (!path.endsWith('.md') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        RegExp(r'[\\\x00-\x1f:<>"|?*]').hasMatch(path)) {
      throw const Failure(FailureCode.invalidInput,
          'Memory path must be a relative Markdown path under memory/.');
    }
    var current = '${location.path}/memory';
    for (final part in ['', ...path.split('/')]) {
      if (part.isNotEmpty) current = '$current/$part';
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const Failure(FailureCode.invalidInput,
            'Memory paths cannot contain symbolic links.');
      }
    }
    return File(current);
  }

  String _revision(String content) =>
      sha256.convert(utf8.encode(content)).toString();

  @override
  Future<JsonMap> read(String path) async {
    final file = await _file(path);
    if (!await file.exists()) {
      throw const Failure(FailureCode.notFound, 'Memory file does not exist.');
    }
    final content = await file.readAsString();
    return {
      'path': path,
      'content': redactMemoryText(content),
      'revision': _revision(content),
      'bytes': utf8.encode(content).length
    };
  }

  @override
  Future<List<JsonMap>> list() async {
    final root = (await _file('MEMORY.md')).parent;
    if (!await root.exists()) return [];
    final paths = <String>[];
    Future<void> visit(Directory directory, String prefix) async {
      await for (final entry in directory.list(followLinks: false)) {
        final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
        final path = '$prefix$name';
        if (entry is Directory) {
          await visit(entry, '$path/');
        } else if (entry is File && name.endsWith('.md')) {
          paths.add(path);
        }
      }
    }

    await visit(root, '');
    paths.sort();
    return [
      for (final path in paths) {...await read(path)}..remove('content')
    ];
  }

  Future<Map<String, String>> snapshot() async => {
        for (final row in await list())
          row['path'] as String: row['revision'] as String
      };

  Future<void> rememberThread(String id) async {
    final key = '${location.path}:$id';
    if (!_seen.containsKey(key)) {
      _seen[key] = await snapshot();
    }
  }

  /// When the user last changed memory from the interface.
  DateTime? _userChangedAt;

  /// A turn of thread [id] that began at [since] ended. What it changed
  /// itself is no news to it next time; a change the user made meanwhile
  /// still is, so then nothing is settled.
  Future<void> settle(String id, DateTime? since) async {
    final key = '${location.path}:$id';
    if (since == null || !_seen.containsKey(key)) return;
    if (_userChangedAt != null && !_userChangedAt!.isBefore(since)) return;
    _seen[key] = await snapshot();
  }

  /// Append once to each thread; existing model context is never rewritten.
  /// It follows what the user said, marked so the conversation hides it.
  Future<String?> changesFor(String id) async {
    final key = '${location.path}:$id';
    final now = await snapshot();
    final before = _seen[key];
    _seen[key] = now;
    if (before == null) return null;
    final removed = before.keys.where((p) => !now.containsKey(p)).toList();
    final changed = now.keys.where((p) => before[p] != now[p]).toList();
    if (removed.isEmpty && changed.isEmpty) return null;
    return '[NipaPlay 记忆] 记忆有变化：${removed.isEmpty ? '' : '已删除 ${removed.join('、')}；'}'
        '${changed.isEmpty ? '' : '已更新 ${changed.join('、')}，使用前请重读；'}'
        '已删除的条目和修改前的偏好不再作为依据，勿从旧对话或摘要恢复。';
  }

  Future<ProcessResult> _git(List<String> args,
      {Set<int> accepted = const {0}}) async {
    final result =
        await Process.run('git', args, workingDirectory: location.path);
    if (!accepted.contains(result.exitCode)) {
      throw StateError(
          redactHarnessText('Memory git failed: ${result.stderr}'));
    }
    return result;
  }

  Future<JsonMap> _change(
      String path, String? content, String revision, Invocation invocation) {
    if (invocation.origin == 'gui') _userChangedAt = DateTime.now();
    final result = _pending.then((_) async {
      final file = await _file(path);
      final old = await file.readAsString();
      if (_revision(old) != revision) {
        throw const Failure(FailureCode.conflict,
            'Memory changed since it was read. Read it again before editing.');
      }
      if (content == old) return {'path': path, 'changed': false};
      if (content != null) {
        if (redactMemoryText(content) != content) {
          throw const Failure(
              FailureCode.invalidInput, 'Secrets cannot be stored in memory.');
        }
        if ((path == 'preferences.md' || path == 'MEMORY.md') &&
            utf8.encode(content).length > preferenceBytes) {
          throw const Failure(FailureCode.invalidInput,
              'Resident memory exceeds 8192 UTF-8 bytes. Keep detail in topic files.');
        }
      }
      final relative = 'memory/$path';
      final tracked = (await _git(['ls-files', '--', relative]))
          .stdout
          .toString()
          .trim()
          .isNotEmpty;
      // Commit only this file. An unrelated staged change must stay staged.
      final staged = await _git(['diff', '--cached', '--quiet', '--', relative],
          accepted: {0, 1});
      if (staged.exitCode == 1) {
        throw const Failure(FailureCode.conflict,
            'The target memory file has staged changes. Finish that Git change first.');
      }
      try {
        if (content == null) {
          await file.delete();
        } else {
          await file.writeAsString(content, flush: true);
        }
        if (tracked || content != null) {
          await _git(['add', '-A', '--', relative]);
          await _git([
            '-c',
            'user.name=${invocation.origin == 'gui' ? 'NipaPlay User' : 'Nipa'}',
            '-c',
            'user.email=${invocation.origin == 'gui' ? 'user' : 'agent'}@localhost',
            '-c',
            'commit.gpgSign=false',
            '-c',
            'core.hooksPath=.git/no-hooks',
            'commit',
            '--only',
            '-m',
            '${content == null ? 'Forget' : 'Edit'} memory $path',
            '--',
            relative,
          ]);
        } else {
          await _git([
            '-c',
            'user.name=${invocation.origin == 'gui' ? 'NipaPlay User' : 'Nipa'}',
            '-c',
            'user.email=${invocation.origin == 'gui' ? 'user' : 'agent'}@localhost',
            '-c',
            'commit.gpgSign=false',
            '-c',
            'core.hooksPath=.git/no-hooks',
            'commit',
            '--allow-empty',
            '--only',
            '-m',
            'Forget untracked memory $path'
          ]);
        }
      } catch (_) {
        await file.writeAsString(old, flush: true);
        await _git(['reset', '--quiet', 'HEAD', '--', relative]);
        rethrow;
      }
      final commit =
          (await _git(['rev-parse', 'HEAD'])).stdout.toString().trim();
      await report({
        'title': '${invocation.origin == 'gui' ? '用户' : 'Nipa'}'
            '${content == null ? '删除' : '修改'}了记忆',
        'source': 'harness:memory',
        'facts': {
          'path': path,
          'operation': content == null ? 'delete' : 'edit',
          'commit': commit
        }
      }, invocation);
      return {'path': path, 'changed': true, 'commit': commit};
    });
    _pending = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  @override
  Future<JsonMap> delete(String path, String revision, Invocation invocation) =>
      _change(path, null, revision, invocation);
  @override
  Future<JsonMap> edit(String path, String content, String revision,
          Invocation invocation) =>
      _change(path, content, revision, invocation);

  Future<String> _resident(String path, int bytes) async {
    final file = await _file(path);
    if (!await file.exists()) return '(memory/$path 不存在)';
    final value = redactMemoryText(await file.readAsString());
    final encoded = utf8.encode(value);
    if (encoded.length <= bytes) return value;
    final prefix = utf8
        .decode(encoded.take(bytes).toList(), allowMalformed: true)
        .replaceFirst(RegExp(r'\uFFFD$'), '');
    return '$prefix\n[截断：memory/$path 尾部 '
        '${encoded.length - utf8.encode(prefix).length} UTF-8 字节未注入；完整文件按需读。]';
  }

  Future<JsonMap> context(String? threadId) async => {
        'preferences': await _resident('preferences.md', preferenceBytes),
        'settings': redactHarnessJson(await settings.preferences()),
        'index': await _resident('MEMORY.md', indexBytes),
        'recent': await recent?.call(threadId) ??
            {'text': '(对话宿主不可用)', 'truncated': false},
      };
}

