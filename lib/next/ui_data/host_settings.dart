/// Settings only the person at this device may change: which model Nipa
/// thinks with, and how this device takes part in the mesh. They are not
/// Actions, so Nipa cannot change them for herself; the settings page
/// calls them in-process. Everything else in settings goes through the
/// settings registry and the same Actions Nipa uses.
library;

abstract interface class NextHostSettings {
  Future<UiModelSetup> model();

  /// Saves the choice; [UiModelChoice.apiKey] null keeps the stored key.
  /// Takes effect for the next conversation turn.
  Future<void> setModel(UiModelChoice choice);

  /// Sends one small request with the saved choice.
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
