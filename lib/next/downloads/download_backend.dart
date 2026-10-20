import 'package:nipa_harness/nipa_harness.dart';

/// Public identity only. Connection settings and credential references belong
/// to the backend adapter, never to task snapshots.
final class DownloadBackendRef implements JsonEncodable {
  const DownloadBackendRef({required this.kind, this.id});
  const DownloadBackendRef.builtin()
      : kind = 'builtin',
        id = null;
  final String kind;
  final String? id;
  factory DownloadBackendRef.fromJson(JsonMap json) => DownloadBackendRef(
      kind: json['kind'] as String, id: json['id'] as String?);
  String get key => '$kind:${id ?? ''}';
  @override
  JsonMap toJson() => {'kind': kind, if (id != null) 'id': id};
}

final class DownloadLocation {
  const DownloadLocation({required this.path, required this.isLocal});
  final String path;
  final bool isLocal;
}

final class DownloadFile {
  const DownloadFile(
      {required this.location,
      required this.expectedSize,
      required this.isVideo,
      this.completedBytes,
      this.included = true});
  final DownloadLocation location;
  final int expectedSize;
  final bool isVideo, included;
  final int? completedBytes;
  bool get complete => completedBytes == expectedSize;
}

final class DownloadSnapshot {
  const DownloadSnapshot(
      {required this.handle,
      required this.infoHash,
      required this.title,
      required this.output,
      required this.completed,
      required this.total,
      required this.finished,
      required this.paused,
      this.libraryKey,
      this.state,
      this.downloadSpeedBytesPerSecond,
      this.uploadSpeedBytesPerSecond,
      this.error,
      this.health,
      this.disk,
      this.files = const []});
  final String handle, infoHash, title;
  final DownloadLocation output;
  final int completed, total;
  final bool finished, paused;
  final String? error;
  final String? libraryKey;
  final String? state;
  final int? downloadSpeedBytesPerSecond, uploadSpeedBytesPerSecond;
  String get importKey => libraryKey ?? '$infoHash|${output.path}';
  final List<DownloadFile> files;
  final JsonMap? health, disk;

  JsonMap toJson() => {
        'handle': handle,
        'infoHash': infoHash,
        'title': title,
        'outputDirectory': output.path,
        'local': output.isLocal,
        'completedBytes': completed,
        'totalBytes': total,
        'finished': finished,
        'paused': paused,
        'error': error,
        if (health != null) 'health': health,
        if (disk != null) 'disk': disk,
        if (state != null) 'state': state,
        if (downloadSpeedBytesPerSecond != null)
          'downloadSpeedBytesPerSecond': downloadSpeedBytesPerSecond,
        if (uploadSpeedBytesPerSecond != null)
          'uploadSpeedBytesPerSecond': uploadSpeedBytesPerSecond,
        'files': [
          for (var i = 0; i < files.length; i++)
            {
              'index': i,
              'path': files[i].location.path,
              'local': files[i].location.isLocal,
              'expectedSize': files[i].expectedSize,
              'included': files[i].included,
              'isVideo': files[i].isVideo,
              'completedBytes': files[i].completedBytes,
              'complete': files[i].complete,
              'playable': files[i].included &&
                  files[i].isVideo &&
                  files[i].complete &&
                  files[i].location.isLocal,
              'streamable': files[i].included &&
                  files[i].isVideo &&
                  state == 'live' &&
                  !paused &&
                  error == null,
            }
        ],
      };
}

final class DownloadRequest implements JsonEncodable {
  const DownloadRequest(
      {required this.source,
      required this.infoHash,
      required this.title,
      this.downloadDirectory,
      this.fileIndices,
      this.createFolderForTask,
      this.fileBindings,
      this.bindingOrigin});
  final String source, infoHash, title;

  /// Declared at order time: file index -> episode identity. Normalized by
  /// `parseFileBindings`; the executor applies each when its file completes.
  final List<JsonMap>? fileBindings;

  /// Origin of the invocation that declared [fileBindings]; the bindings
  /// are written on its behalf.
  final String? bindingOrigin;
  final String? downloadDirectory;
  final bool? createFolderForTask;
  final List<int>? fileIndices;
  factory DownloadRequest.fromJson(JsonMap json) => DownloadRequest(
      source: json['source'] as String,
      infoHash: json['infoHash'] as String,
      title: json['title'] as String,
      downloadDirectory: json['downloadDirectory'] as String?,
      fileIndices: (json['fileIndices'] as List?)?.cast<int>(),
      createFolderForTask: json['createFolderForTask'] as bool?,
      fileBindings: (json['fileBindings'] as List?)?.cast<JsonMap>(),
      bindingOrigin: json['bindingOrigin'] as String?);
  @override
  JsonMap toJson() => {
        'source': source,
        'infoHash': infoHash,
        'title': title,
        if (downloadDirectory != null) 'downloadDirectory': downloadDirectory,
        if (fileIndices != null) 'fileIndices': fileIndices,
        if (createFolderForTask != null)
          'createFolderForTask': createFolderForTask,
        if (fileBindings != null) 'fileBindings': fileBindings,
        if (bindingOrigin != null) 'bindingOrigin': bindingOrigin,
      };
}

/// Offline adapters throw Failure(unavailable, retryable: true). Credentials
/// are resolved by adapters using a private reference. Remote paths remain
/// remote until a separate transfer task publishes them locally.
abstract interface class DownloadBackend {
  DownloadBackendRef get reference;
  String? get credentialRef;
  Future<void> initialize();
  Future<List<DownloadSnapshot>> list();
  Future<DownloadSnapshot> read(String handle);
  Future<DownloadSnapshot> add(DownloadRequest request,
      {Future<void>? stopRequested});
  Future<void> pause(String handle);
  Future<void> resume(String handle);
  Future<void> remove(String handle);

  /// Adapters must validate their own deletion boundary before removing data.
  Future<void> delete(String handle);

  /// Returns null for a missing file; remote adapters perform remote readback.
  Future<int?> readSize(DownloadFile file);
}

abstract interface class SelectableDownloadBackend {
  Future<void> selectFiles(String handle, List<int> indices);
}

/// Removes the data of individual files of a session, keeping the session and
/// the other files. Adapters validate their own deletion boundary: only the
/// files at [indices], only inside the session's output directory.
abstract interface class FileDeletingDownloadBackend {
  Future<void> deleteFiles(String handle, List<int> indices);
}

abstract interface class BandwidthDownloadBackend {
  Future<JsonMap> bandwidth(JsonMap input);
}

final class DownloadBackends {
  DownloadBackends(Iterable<DownloadBackend> backends)
      : _backends = {
          for (final backend in backends) backend.reference.key: backend
        };
  final Map<String, DownloadBackend> _backends;
  Iterable<DownloadBackend> get values => _backends.values;
  DownloadBackend resolve(DownloadBackendRef ref) =>
      _backends[ref.key] ??
      (throw Failure(FailureCode.unavailable,
          'Download backend is not configured: ${ref.key}',
          retryable: true));
}

/// Metadata preparation stopped before committing a backend session entry.
final class DownloadAddStopped implements Exception {
  const DownloadAddStopped();
}

abstract interface class DownloadLibrary {
  Future<bool> get enabled;
  bool get isBusy;
  Future<bool> wasImported(String key);
  Future<JsonMap?> lookup(String path);
  Future<bool> importFiles(List<String> paths, String outputDirectory);
  Future<void> markImported(String key);

  /// Writes the declared episode identity of one downloaded file through the
  /// same logic as `media.identity.bind_batch`. [requestId] is stable per
  /// job and file, so repeating it returns the saved result.
  Future<JsonMap> bindFile(
      {required String fileId,
      required JsonMap declaration,
      required String requestId,
      required String origin});
}
