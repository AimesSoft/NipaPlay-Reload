import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// What NipaPlay fetches to run Nipa on DeepSeek Harness: a Node.js archive
/// from nodejs.org and the npm packages of the trimmed DSH, each pinned by
/// SHA-256 (`assets/next/agent/dsh-runtime.json`, built by
/// `scripts/next/dsh_runtime/build_lock.py`). Nothing is looked up at run time.
final class DshManifest {
  DshManifest._(this.dsh, this.nodeVersion, this.nodes, this.registry,
      this.platforms, this.packages);

  factory DshManifest.parse(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['schema'] != 1) {
      throw FormatException('Unknown DSH runtime manifest ${json['schema']}');
    }
    final node = json['node'] as Map<String, dynamic>;
    return DshManifest._(
        json['dsh'] as String,
        node['version'] as String,
        {
          for (final e in (node['assets'] as Map<String, dynamic>).entries)
            e.key: DshNodeAsset._(e.value as Map<String, dynamic>)
        },
        json['registry'] as String,
        List<String>.unmodifiable(json['platforms'] as List),
        List.unmodifiable([
          for (final p in json['packages'] as List)
            DshPackage._(p as Map<String, dynamic>)
        ]));
  }

  /// The `@deepseek-ai/dsh` version.
  final String dsh;
  final String nodeVersion;

  /// By platform key (`macos-arm64`, `linux-x64`, `windows-x64`...).
  final Map<String, DshNodeAsset> nodes;

  /// The npm registry the package paths are relative to.
  final String registry;

  /// The platforms whose package list has been traced and tested.
  final List<String> platforms;
  final List<DshPackage> packages;

  /// Where an installation of this manifest lives under the runtime root.
  String get id => 'dsh-$dsh-node-$nodeVersion';

  bool supports(String platform) =>
      platforms.contains(platform) && nodes.containsKey(platform);

  /// The packages installed on [platform] (`os`/`cpu` as npm names them).
  List<DshPackage> packagesFor(String platform) {
    final (os, cpu) = npmPlatform(platform);
    return [
      for (final p in packages)
        if ((p.os == null || p.os!.contains(os)) &&
            (p.cpu == null || p.cpu!.contains(cpu)))
          p
    ];
  }

  /// The platform key of this machine, or null for an architecture without
  /// a pinned Node.js.
  static String? hostPlatform() {
    final os = switch (Platform.operatingSystem) {
      'macos' => 'macos',
      'linux' => 'linux',
      'windows' => 'windows',
      _ => null,
    };
    final arch = switch (Abi.current()) {
      Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'arm64',
      Abi.macosX64 || Abi.linuxX64 || Abi.windowsX64 => 'x64',
      _ => null,
    };
    return os == null || arch == null ? null : '$os-$arch';
  }

  static (String, String) npmPlatform(String platform) {
    final parts = platform.split('-');
    return (
      switch (parts[0]) { 'macos' => 'darwin', 'windows' => 'win32', _ => parts[0] },
      parts[1]
    );
  }
}

final class DshNodeAsset {
  DshNodeAsset._(Map<String, dynamic> json)
      : url = json['url'] as String,
        sha256 = json['sha256'] as String,
        bytes = json['bytes'] as int,
        archive = json['archive'] as String,
        executable = json['executable'] as String;

  final String url, sha256, archive, executable;
  final int bytes;

  String get name => url.split('/').last;
}

final class DshPackage {
  DshPackage._(Map<String, dynamic> json)
      : path = json['path'] as String,
        name = json['name'] as String,
        version = json['version'] as String,
        url = json['url'] as String,
        sha256 = json['sha256'] as String,
        bytes = json['bytes'] as int,
        os = (json['os'] as List?)?.cast<String>(),
        cpu = (json['cpu'] as List?)?.cast<String>();

  /// Relative to the install prefix: `node_modules/<name>` or nested.
  final String path;
  final String name, version;

  /// Relative to the registry: `<name>/-/<file>.tgz`.
  final String url;
  final String sha256;
  final int bytes;
  final List<String>? os, cpu;
}
