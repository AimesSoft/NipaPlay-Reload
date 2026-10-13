import 'package:nipa_harness/nipa_harness.dart';

import 'gui_calls.dart';

/// Downloads as the person sees them: `task.list` (type download) for which
/// there are, `download.read` for each one's files, rates and peers, and
/// `download.*` for what they change.
final class NextDownloads {
  NextDownloads(this.calls);
  final GuiCalls calls;

  /// Every download NipaPlay keeps, newest first; removed ones are gone.
  Future<List<UiDownload>> list() async {
    final jobs = [
      for (final job in ((await calls.call('task.list', {'type': 'download'}))[
              'jobs'] as List)
          .cast<Map>())
        if (job['state'] != 'cancelled' && job['state'] != 'cancelling') job
    ]..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    if (jobs.isEmpty) return const [];
    final read = await calls.call('download.read', {
      'jobIds': [for (final job in jobs) job['jobId']]
    });
    final results = (read['results'] as List).cast<Map>();
    return [
      for (final (i, job) in jobs.indexed)
        UiDownload.from(
            job,
            results[i]['status'] == 'completed'
                ? results[i]['task'] as Map?
                : null),
    ];
  }

  /// One download, as it is now.
  Future<UiDownload> read(String jobId) async {
    final r = await calls.call('download.read', {'jobId': jobId});
    return UiDownload.from(r['job'] as Map, r['task'] as Map?);
  }

  /// The task IDs that are downloads, of [taskIds].
  Future<Set<String>> which(Iterable<String> taskIds) async {
    final wanted = taskIds.toSet();
    if (wanted.isEmpty) return const {};
    final jobs = (await calls.call('task.list', {'type': 'download'}))['jobs']
        as List;
    return {
      for (final job in jobs.cast<Map>())
        if (wanted.contains(job['jobId'])) job['jobId'] as String
    };
  }

  /// A magnet's name and files, without adding it.
  Future<UiTorrentPreview> preview(String magnet) async =>
      UiTorrentPreview.from(
          await calls.call('download.preview', {'source': magnet}));

  /// Where downloads go, and the folders chosen lately.
  Future<UiDownloadPlaces> places() async {
    final r = await calls.call('download.directories', {});
    return UiDownloadPlaces(
      folder: r['defaultDirectory'] as String,
      recent: (r['recentDirectories'] as List).cast<String>(),
    );
  }

  /// Adds [source] (a magnet, a torrent's address or a .torrent file);
  /// the new download's task ID.
  Future<String> add(String source,
      {String? folder, List<int>? files}) async {
    final r = await calls.call('download.add', {
      'source': source,
      if (folder != null) 'downloadDirectory': folder,
      if (files != null) 'fileIndices': files,
    });
    return (r['job'] as Map)['jobId'] as String;
  }

  Future<void> setPaused(List<String> jobIds, bool paused) async {
    final r = await calls
        .call('download.set_paused', {'jobIds': jobIds, 'paused': paused});
    _throwFirst(r);
  }

  /// Which files to download; the rest are left alone.
  Future<void> select(String jobId, List<int> files) =>
      calls.call('download.select_files', {'jobId': jobId, 'fileIndices': files});

  /// Takes the download off the list; with [files], what it downloaded too.
  Future<void> remove(String jobId, {required bool files}) =>
      calls.call(files ? 'download.delete' : 'download.remove', {'jobId': jobId});

  /// Plays a file, finished or while it downloads.
  Future<void> play(String jobId, int file) =>
      calls.call('download.play', {'jobId': jobId, 'fileIndex': file});

  Future<UiDownloadLimits> limits() async =>
      UiDownloadLimits.from(await calls.call('download.limits.get', {}));

  /// 0 is unlimited; null leaves that direction as it is.
  Future<UiDownloadLimits> setLimits({int? down, int? up}) async =>
      UiDownloadLimits.from(await calls.call('download.limits.set', {
        if (down != null) 'downloadBytesPerSecond': down,
        if (up != null) 'uploadBytesPerSecond': up,
      }));

  static void _throwFirst(JsonMap r) {
    for (final row in ((r['results'] as List?) ?? const []).cast<Map>()) {
      if (row['status'] == 'failed') {
        throw failureOf(row['error'] as Map);
      }
    }
  }
}

enum UiDownloadState { downloading, queued, paused, finished, failed }

final class UiDownload {
  const UiDownload({
    required this.jobId,
    required this.title,
    required this.state,
    this.done = 0,
    this.size = 0,
    this.down = 0,
    this.up = 0,
    this.peers,
    this.seenPeers,
    this.stalledFor,
    this.free,
    this.folder,
    this.error,
    this.files = const [],
    this.live = true,
    this.createdAt,
  });

  final String jobId;
  final String title;
  final UiDownloadState state;

  /// Checked bytes of the chosen files, and their total.
  final int done;
  final int size;

  /// Bytes per second.
  final int down;
  final int up;

  /// Connected peers, and every peer heard of; null while unknown.
  final int? peers;
  final int? seenPeers;

  /// Since when nothing arrived, when it matters.
  final Duration? stalledFor;

  /// Free space where it downloads.
  final int? free;
  final String? folder;
  final String? error;
  final List<UiDownloadFile> files;

  /// The download session is there (files, rates, peers can be read).
  final bool live;
  final DateTime? createdAt;

  double? get progress => size > 0 ? (done / size).clamp(0.0, 1.0) : null;
  bool get running =>
      state == UiDownloadState.downloading || state == UiDownloadState.queued;

  /// How long the rest takes at the current rate.
  Duration? get remaining => down > 0 && size > done
      ? Duration(seconds: ((size - done) / down).ceil())
      : null;

  factory UiDownload.from(Map job, Map? task) {
    final jobState = job['state'] as String?;
    final error = task?['error'] as String? ??
        (jobState == 'failed' ? ((job['error'] as Map?)?['message'] as String?) : null);
    final finished = task?['finished'] == true || jobState == 'succeeded';
    final paused = task?['paused'] == true || jobState == 'paused';
    final state = error != null || jobState == 'failed'
        ? UiDownloadState.failed
        : finished
            ? UiDownloadState.finished
            : paused || jobState == 'interrupted'
                ? UiDownloadState.paused
                : jobState == 'queued' || jobState == 'waiting_retry'
                    ? UiDownloadState.queued
                    : UiDownloadState.downloading;
    final progress = job['progress'] as Map?;
    final health = task?['health'] as Map?;
    final folder = task?['outputDirectory'] as String?;
    final stalled = (health?['secondsWithoutProgress'] as num?)?.toInt();
    return UiDownload(
      jobId: job['jobId'] as String,
      title: _title(task?['title'] as String?, job['title'] as String?),
      state: state,
      done: (task?['completedBytes'] as num?)?.toInt() ??
          (progress?['completed'] as num?)?.toInt() ??
          0,
      size: (task?['totalBytes'] as num?)?.toInt() ??
          (progress?['total'] as num?)?.toInt() ??
          0,
      down: (task?['downloadSpeedBytesPerSecond'] as num?)?.toInt() ?? 0,
      up: (task?['uploadSpeedBytesPerSecond'] as num?)?.toInt() ?? 0,
      peers: (health?['connectedPeers'] as num?)?.toInt(),
      seenPeers: (health?['seenPeers'] as num?)?.toInt(),
      stalledFor: state == UiDownloadState.downloading &&
              stalled != null &&
              stalled >= 60
          ? Duration(seconds: stalled)
          : null,
      free: ((task?['disk'] as Map?)?['availableBytes'] as num?)?.toInt(),
      folder: folder,
      error: error,
      live: task != null,
      createdAt: DateTime.tryParse('${job['createdAt']}')?.toLocal(),
      files: UiDownloadFile.inside([
        for (final f in ((task?['files'] as List?) ?? const []).cast<Map>())
          UiDownloadFile.from(f, folder),
      ]),
    );
  }

  static String _title(String? task, String? job) {
    if (task != null && task.trim().isNotEmpty) return task.trim();
    return job?.trim().isNotEmpty == true ? job!.trim() : '下载';
  }
}

final class UiDownloadFile {
  const UiDownloadFile({
    required this.index,
    required this.name,
    required this.size,
    this.folder,
    this.done,
    this.included = true,
    this.video = false,
    this.complete = false,
    this.playable = false,
    this.streamable = false,
  });

  final int index;

  /// The file's own name, and the folders above it inside the download.
  final String name;
  final String? folder;
  final int size;
  final int? done;
  final bool included;
  final bool video;
  final bool complete;
  final bool playable;
  final bool streamable;

  double? get progress => complete
      ? 1
      : done != null && size > 0
          ? (done! / size).clamp(0.0, 1.0)
          : null;

  /// [files] without the folder they all share (the torrent's own).
  static List<UiDownloadFile> inside(List<UiDownloadFile> files) {
    final first = files.firstOrNull?.folder?.split(' / ').first;
    if (first == null ||
        !files.every((f) => f.folder?.split(' / ').first == first)) {
      return files;
    }
    return [
      for (final f in files)
        UiDownloadFile(
          index: f.index,
          name: f.name,
          folder: f.folder == first
              ? null
              : f.folder!.substring(first.length + 3),
          size: f.size,
          done: f.done,
          included: f.included,
          video: f.video,
          complete: f.complete,
          playable: f.playable,
          streamable: f.streamable,
        )
    ];
  }

  factory UiDownloadFile.from(Map f, String? root) {
    var path = f['path'] as String;
    if (root != null && path.startsWith(root)) {
      path = path.substring(root.length);
    }
    final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
    return UiDownloadFile(
      index: (f['index'] as num).toInt(),
      name: parts.isEmpty ? path : parts.last,
      folder: parts.length > 1
          ? parts.take(parts.length - 1).join(' / ')
          : null,
      size: (f['expectedSize'] as num?)?.toInt() ?? 0,
      done: (f['completedBytes'] as num?)?.toInt(),
      included: f['included'] != false,
      video: f['isVideo'] == true,
      complete: f['complete'] == true,
      playable: f['playable'] == true,
      streamable: f['streamable'] == true,
    );
  }
}

final class UiTorrentPreview {
  const UiTorrentPreview(
      {required this.name, required this.size, required this.files});
  final String name;
  final int size;
  final List<UiDownloadFile> files;

  factory UiTorrentPreview.from(JsonMap r) => UiTorrentPreview(
        name: r['name'] as String,
        size: (r['totalSize'] as num).toInt(),
        files: UiDownloadFile.inside([
          for (final f in (r['files'] as List).cast<Map>())
            UiDownloadFile.from({
              'index': f['index'],
              'path': f['path'],
              'expectedSize': f['length'],
              'isVideo': _videoName(f['path'] as String),
            }, null),
        ]),
      );

  static bool _videoName(String path) => RegExp(
          r'\.(mkv|mp4|avi|mov|m4v|webm|flv|wmv|ts|m2ts|rmvb)$',
          caseSensitive: false)
      .hasMatch(path);
}

final class UiDownloadPlaces {
  const UiDownloadPlaces({required this.folder, this.recent = const []});
  final String folder;
  final List<String> recent;
}

final class UiDownloadLimits {
  const UiDownloadLimits({
    this.supported = false,
    this.running = false,
    this.down = 0,
    this.up = 0,
  });

  /// This downloader can be limited at all.
  final bool supported;

  /// The downloader is running, so the numbers are what it does now.
  final bool running;

  /// Bytes per second; 0 is unlimited.
  final int down;
  final int up;

  /// The smallest limit the downloader takes.
  static const minimum = 16384;

  factory UiDownloadLimits.from(JsonMap r) {
    final actual = r['actual'] as Map?;
    return UiDownloadLimits(
      supported: r['supported'] == true,
      running: r['sessionInitialized'] == true,
      down: (actual?['downloadBytesPerSecond'] as num?)?.toInt() ?? 0,
      up: (actual?['uploadBytesPerSecond'] as num?)?.toInt() ?? 0,
    );
  }
}
