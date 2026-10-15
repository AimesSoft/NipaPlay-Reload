/// Settings only the person at this device may change: which model Nipa
/// thinks with, and how this device takes part in the mesh. They are not
/// Actions, so Nipa cannot change them for herself; the settings page
/// calls them in-process. Everything else in settings goes through the
/// settings registry and the same Actions Nipa uses.
library;

/// Desktop runtime controls are host-only, never Actions or mesh settings.
/// A mirror is a directory containing the exact manifest asset filenames;
/// changing it never changes the pinned version or SHA-256 checks.
abstract interface class NextHostRuntimeSettings {
  Future<UiCodexRuntime> codexRuntime();
  /// Completes when installation ends. Subscribe to changes for byte progress.
  /// Repeating after cancellation resumes the retained partial download.
  Future<void> installCodex();
  Future<void> cancelCodexInstall();
  /// Refuses while a chat process is using the runtime.
  Future<void> removeCodex();
  Future<void> setCodexRuntime(UiCodexRuntimeChoice choice);
}

extension NextHostRuntimeAccess on NextHostSettings {
  NextHostRuntimeSettings get runtimeSettings {
    final host = this;
    if (host is NextHostRuntimeSettings) return host as NextHostRuntimeSettings;
    throw UnsupportedError('此宿主不支持运行包设置');
  }
}

enum UiCodexStatus { notInstalled, downloading, verifying, ready, failed }
enum UiCodexSource { managed, path, specified }

final class UiCodexRuntimeChoice {
  const UiCodexRuntimeChoice({this.source = UiCodexSource.managed,
    this.executable, this.mirror});
  final UiCodexSource source;
  /// Absolute native executable, required only for specified.
  final String? executable;
  /// Null/empty uses official GitHub Release assets. No credentials allowed.
  final String? mirror;
}

final class UiCodexRuntime {
  const UiCodexRuntime({required this.status, required this.version,
    required this.source, this.receivedBytes = 0, this.totalBytes,
    this.problem, this.executable, this.mirror, this.licensesDirectory});
  /// Managed package installation state, including when an advanced source is
  /// selected. [source] and [executable] describe the actual launch selection.
  final UiCodexStatus status;
  /// Manifest version for managed; null for an externally maintained Codex.
  final String? version;
  final UiCodexSource source;
  final int receivedBytes;
  final int? totalBytes;
  final String? problem, executable, mirror;
  /// Offline license files, including LICENSE/NOTICE and component notices.
  final String? licensesDirectory;
}

/// Optional host port, kept separate so existing UI/fake adapters remain valid.
/// These methods are in-process only and must never be registered as Actions.
abstract interface class NextHostDeviceSettings {
  Future<UiHostKeys> keys();

  /// Null retains a key; empty clears it. Secrets are write-only and never
  /// appear in changes, settings history, task receipts or returned models.
  Future<void> setKeys({String? spoilerAi, String? tmdb});
  Future<UiRemoteAccess> remoteAccess();
  Future<void> setRemoteAccess(UiRemoteAccessChoice choice);
  Future<void> forgetRemoteDevice(String clientKey);
}

extension NextHostDeviceAccess on NextHostSettings {
  NextHostDeviceSettings get deviceSettings {
    final host = this;
    if (host is NextHostDeviceSettings) return host as NextHostDeviceSettings;
    throw UnsupportedError('此宿主不支持设备设置');
  }
}

final class UiHostKeys {
  const UiHostKeys({required this.spoilerAi, required this.tmdb});
  final bool spoilerAi, tmdb;
}

final class UiRemoteAccess {
  const UiRemoteAccess({required this.running, required this.autoStart,
    required this.port, required this.ipv6, required this.receiverEnabled,
    this.devices = const [], this.problem});
  final bool running, autoStart, ipv6, receiverEnabled;
  final int port;
  final List<UiRemoteDevice> devices;
  final String? problem;
}

final class UiRemoteDevice {
  const UiRemoteDevice({required this.clientKey, required this.name});
  final String clientKey, name;
}

final class UiRemoteAccessChoice {
  const UiRemoteAccessChoice({required this.running, required this.autoStart,
    required this.port, required this.ipv6, required this.receiverEnabled});
  final bool running, autoStart, ipv6, receiverEnabled;
  final int port;
}

abstract interface class NextHostSettings {
  Future<UiModelSetup> model();

  /// Saves the choice; [UiModelChoice.apiKey] null keeps the stored key.
  /// Takes effect for the next conversation turn.
  Future<void> setModel(UiModelChoice choice);

  /// For an endpoint set up here, sends one small Responses request requiring
  /// a harmless function call. Existing Codex configurations use a probe thread.
  /// Success verifies that call only, not every Codex tool or streaming feature.
  Future<UiModelCheck> checkModel();

  Future<UiMeshSetup> mesh();
  Future<void> setMesh(UiMeshChoice choice);

  /// Whether Nipa may run programs on this device from another one.
  Future<bool> remotePrograms();
  Future<void> setRemotePrograms(bool allowed);

  /// Fires when anything above may have changed.
  Stream<void> get changes;
}

enum UiModelSource {
  /// The Codex configuration already on this computer (`~/.codex`).
  codex,

  /// A provider set up here; its key is kept in NipaPlay's vault.
  nipaplay,
}

final class UiModelSetup {
  const UiModelSetup({
    required this.source,
    this.codexAvailable = false,
    this.provider,
    this.baseUrl,
    this.model,
    this.hasKey = false,
    this.inUse,
    this.problem,
  });
  final UiModelSource source;

  /// Whether a Codex configuration exists to use.
  final bool codexAvailable;

  /// For [UiModelSource.nipaplay]: e.g. “OpenAI”, “DeepSeek”, or a name the
  /// user gave an OpenAI-compatible endpoint.
  final String? provider;
  /// Editable Responses base URL; a pasted /responses suffix is accepted.
  /// No provider allowlist or automatic official endpoint selection.
  final String? baseUrl;
  final String? model;

  /// A key is stored. The key itself is never read back.
  final bool hasKey;

  /// What the running conversation actually uses, e.g. “deepseek-v4.1-flash”.
  final String? inUse;

  /// Why Nipa cannot think right now, in a short sentence; null when fine.
  final String? problem;
}

final class UiModelChoice {
  const UiModelChoice({
    required this.source,
    this.provider,
    this.baseUrl,
    this.model,
    this.apiKey,
  });
  final UiModelSource source;
  final String? provider;
  final String? baseUrl;
  final String? model;
  final String? apiKey;
}

final class UiModelCheck {
  const UiModelCheck({required this.ok, this.message, this.latency});
  final bool ok;

  /// Short and plain, e.g. “密钥无效” or “连不上服务器”.
  final String? message;
  final Duration? latency;
}

final class UiMeshSetup {
  const UiMeshSetup({
    this.joined = false,
    this.available = true,
    this.problem,
    this.name,
    this.coordinator,
    this.port,
    this.loopbackOnly = false,
    this.broadcastDiscovery = true,
    this.addresses = const [],
    this.fileProxyPort,
    this.devices = const [],
  });

  /// This device is in the mesh now.
  final bool joined;

  /// The mesh can be used in this build (e.g. a release without an issuer
  /// cannot).
  final bool available;
  final String? problem;
  final String? name;
  final String? coordinator;
  final int? port;
  final bool loopbackOnly;
  final bool broadcastDiscovery;

  /// Extra addresses others may reach this device at, “host:port”.
  final List<String> addresses;

  /// Fixed port for the local player converter; null for a random one.
  final int? fileProxyPort;
  final List<UiMeshDevice> devices;
}

final class UiMeshDevice {
  const UiMeshDevice({
    required this.name,
    this.online = false,
    this.self = false,
    this.roles = const [],
    this.remotePrograms = false,
  });
  final String name;
  final bool online;
  final bool self;
  final List<String> roles;

  /// That device's host allows programs to be run on it.
  final bool remotePrograms;
}

final class UiMeshChoice {
  const UiMeshChoice({
    required this.joined,
    this.name,
    this.coordinator,
    this.port,
    this.loopbackOnly = false,
    this.broadcastDiscovery = true,
    this.addresses = const [],
    this.fileProxyPort,
  });
  final bool joined;
  final String? name;
  final String? coordinator;
  final int? port;
  final bool loopbackOnly;
  final bool broadcastDiscovery;
  final List<String> addresses;
  final int? fileProxyPort;
}
