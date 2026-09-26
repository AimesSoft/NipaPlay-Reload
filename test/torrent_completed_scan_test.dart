import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/services/concurrent_video_processor.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/torrent_download_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed and throwing scans return failure and can be retried', () async {
    var attempt = 0;
    final scanner =
        ScanService.forTesting(completedFilesProcessor: (paths) async {
      attempt++;
      if (attempt == 1) throw StateError('unreadable');
      return [VideoProcessResult(filePath: paths.single, success: attempt > 2)];
    });
    addTearDown(scanner.dispose);
    expect(
        await scanner
            .scanCompletedFiles(['/download/a.mp4'], folderPath: '/download'),
        isFalse);
    expect(scanner.isScanning, isFalse);
    expect(
        await scanner
            .scanCompletedFiles(['/download/a.mp4'], folderPath: '/download'),
        isFalse);
    expect(
        await scanner
            .scanCompletedFiles(['/download/a.mp4'], folderPath: '/download'),
        isTrue);
    expect(scanner.scannedFolders, isEmpty);
    expect(scanner.failedScanFiles, isEmpty);
  });

  test('an occupied scanner does not claim the next task was imported',
      () async {
    final pending = Completer<List<VideoProcessResult>>();
    var calls = 0;
    final scanner = ScanService.forTesting(completedFilesProcessor: (_) {
      calls++;
      return pending.future;
    });
    addTearDown(scanner.dispose);
    final first =
        scanner.scanCompletedFiles(['a.mp4'], folderPath: '/download');
    expect(await scanner.scanCompletedFiles(['b.mp4'], folderPath: '/download'),
        isFalse);
    expect(calls, 1);
    pending.complete([]);
    expect(await first, isTrue);
  });

  test('only exact completed task files are selected from a shared directory',
      () async {
    final root = await Directory.systemTemp.createTemp('torrent-files-test-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/complete.mp4').writeAsString('done');
    await File('${root.path}/unfinished.mp4').writeAsString('partial');
    final service = TorrentDownloadService.forTesting(
        isIos: () => false,
        getDownloadsDirectory: () async => root,
        directoryExists: (_) async => true);
    final task = TorrentTask.fromMap({
      'id': 1,
      'output_folder': root.path,
      'stats': {'finished': true, 'state': 'live'},
      'files': [
        {'name': 'complete.mp4', 'length': 4, 'included': true}
      ]
    });
    expect(await service.listCompletedVideoPaths(task),
        ['${root.path}/complete.mp4']);
    await File('${root.path}/complete.mp4').delete();
    await expectLater(service.listCompletedVideoPaths(task), throwsStateError);
  });
}
