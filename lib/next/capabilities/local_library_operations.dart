import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/android_saf_service.dart';
import 'package:nipaplay/services/harmony_local_media_service.dart';
import 'package:nipaplay/utils/platform_identity.dart' as platform;
import 'package:path/path.dart' as p;

import 'classic_action.dart';
import '../media/identity_store.dart' show stableMediaId;

const _output = ObjectSchema({}, additionalProperties: true);
const _paths = ArraySchema(StringSchema(minLength: 1));

final class LocalLibraryOperations implements Capability {
  LocalLibraryOperations(this.scan, this.history, {this.engine});
  final ScanService scan;
  final WatchHistoryProvider history;
  final TaskEngine? engine;

  Future<void> attachClassicHistory() async {
    await WatchHistoryManager.initialize();
    await WatchHistoryDatabase.instance.database;
    await WatchHistoryDatabase.instance.migrateFromJson();
    WatchHistoryManager.setMigratedToDatabase(true);
  }

  void _idle() {
    if (scan.isScanning) {
      throw const Failure(FailureCode.conflict, 'A Classic scan is running.');
    }
  }

  JsonMap _state() => {
        'roots': scan.scannedFolders,
        'scanning': scan.isScanning,
        'progress': scan.scanProgress,
        'message': scan.scanMessage,
        'totalFilesFound': scan.totalFilesFound,
        'failedFiles': [
          for (final file in scan.failedScanFiles)
            {'path': file.filePath, 'reason': file.errorMessage}
        ],
      };

  Future<List<String>> _directories(JsonMap input) async {
    final paths = (input['paths'] as List?)?.cast<String>();
    if (paths != null) return paths.toSet().toList();
    final selected = await FilePickerService().pickDirectory();
    return selected == null ? [] : [selected];
  }

  Future<void> _validateDirectory(String path) async {
    if (platform.isHarmonyOS) {
      await HarmonyLocalMediaService.ensureDirectoryAccess(path);
      return;
    }
    if (Platform.isAndroid && path.startsWith('content://')) {
      if (!await AndroidSafService.canAccessTree(path)) {
        throw const Failure(FailureCode.unavailable,
            'Grant this directory through the Classic picker first.');
      }
      return;
    }
    if (!p.isAbsolute(path) || !await Directory(path).exists()) {
      throw Failure(FailureCode.invalidInput,
          'Use an existing absolute directory path: $path');
    }
  }

  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'media.library.roots.list',
                title: 'Read local scan folders',
                description:
                    'Read Classic scan directories and scan progress/failures. '
                    'These roots also define the Next local media scope.',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: _output),
            (_, __) async => _state()),
        ClassicAction(
            const ActionSpec(
                id: 'media.library.roots.add',
                title: 'Add local scan folders',
                description:
                    'Add paths in one call to Classic saved scan directories. '
                    'Omit paths to let the user choose a directory with the Classic permission picker. '
                    'Use absolute existing paths, or platform-granted SAF/Harmony directory URIs. '
                    'Existing roots are retained. This registers roots without scanning; '
                    'call media.library.scan_classic for Classic identification or media.library.scan for Next indexing.',
                effect: Effect.write,
                input: ObjectSchema({'paths': _paths}),
                output: _output), (input, _) async {
          _idle();
          final paths = await _directories(input);
          for (final path in paths) {
            await _validateDirectory(path);
          }
          for (final path in paths) {
            await scan.addScannedFolder(path);
          }
          return {'selected': paths, ..._state()};
        }),
        ClassicAction(
            const ActionSpec(
                id: 'media.library.roots.remove',
                title: 'Remove local scan folders',
                description:
                    'Remove saved Classic roots in a batch and clean their associated '
                    'watch history and folder hash cache exactly as Classic does. '
                    'Media files stay on disk. No confirmation is needed. Returns removed roots.',
                effect: Effect.write,
                input: ObjectSchema({'paths': _paths}, required: ['paths']),
                output: _output), (input, _) async {
          _idle();
          final removed = <String>[];
          for (final path in (input['paths'] as List).cast<String>().toSet()) {
            if (!scan.scannedFolders.contains(path)) continue;
            await scan.removeScannedFolder(path);
            if ((await WatchHistoryManager.getItemsByPathPrefix(path))
                .isNotEmpty) {
              throw const Failure(FailureCode.unavailable,
                  'Classic could not remove associated history.');
            }
            removed.add(path);
          }
          await history.refresh();
          return {'removed': removed, ..._state()};
        }),
        ClassicAction(
            const ActionSpec(
                id: 'media.library.roots.cleanup',
                title: 'Clean missing scan folders',
                description:
                    'Use Classic cleanup to remove missing scan directories and associated '
                    'history/hash cache. Inaccessible Harmony roots are retained. Media files stay on disk.',
                effect: Effect.write,
                input: ObjectSchema({}),
                output: _output), (_, __) async {
          _idle();
          final before = scan.scannedFolders.toSet();
          await scan.cleanupMissingScannedFolders();
          await history.refresh();
          return {
            'removed': before.difference(scan.scannedFolders.toSet()).toList(),
            ..._state()
          };
        }),
        ClassicAction(
            const ActionSpec(
                id: 'media.library.scan_classic',
                title: 'Scan with Classic identification',
                description:
                    'Scan saved Classic roots sequentially with the same smart file-diff, '
                    'hash identification and history persistence as the Classic library. '
                    'Omit paths to scan all roots. paths must already be registered; SAF/Harmony roots are supported by Classic. '
                    'skipPreviouslyMatchedUnwatched defaults to false. Returns a persistent jobId; '
                    'task.control pauses/resumes at file boundaries; task.get/wait reads receipts and failures. '
                    'Login, if required for identification, is completed by the user through accounts.login.',
                effect: Effect.write,
                input: ObjectSchema({
                  'paths': _paths,
                  'skipPreviouslyMatchedUnwatched': BooleanSchema()
                }),
                output: _output), (input, _) async {
          final paths =
              (input['paths'] as List?)?.cast<String>().toSet().toList() ??
                  scan.scannedFolders;
          if (paths.any((path) => !scan.scannedFolders.contains(path))) {
            throw const Failure(FailureCode.invalidInput,
                'Register paths with media.library.roots.add first.');
          }
          if (engine == null) {
            throw const Failure(FailureCode.unavailable, 'Task engine is not attached.');
          }
          final job = await engine!.submit(type: 'media.scan_classic',
              title: 'Classic 媒体扫描', input: {'paths': paths,
                'skipPreviouslyMatchedUnwatched': input['skipPreviouslyMatchedUnwatched'] == true});
          return {'jobId': job.jobId, 'job': job.toJson()};
        }),
        ClassicAction(
            const ActionSpec(
                id: 'history.remove',
                title: 'Remove watch history',
                description:
                    'Delete Classic watch records in a batch by entryIds, paths and/or animeIds (union). '
                    'entryIds come from history.entries and work even when locator is null. '
                    'animeIds are Classic anime IDs, including negative custom IDs. Series deletion uses Classic '
                    'deletion tombstones; path deletion uses Classic single-record removal. '
                    'Missing records are skipped. removedEntryIds covers all removals; removedPaths only echoes supplied paths. '
                    'Video files stay on disk; no confirmation is needed.',
                effect: Effect.write,
                input: ObjectSchema({
                  'paths': _paths,
                  'entryIds': _paths,
                  'animeIds': ArraySchema(IntegerSchema())
                }),
                output: _output), (input, _) async {
          if (!input.containsKey('paths') && !input.containsKey('animeIds') &&
              !input.containsKey('entryIds')) {
            throw const Failure(
                FailureCode.invalidInput, 'Supply entryIds, paths or animeIds.');
          }
          final before = await WatchHistoryManager.getAllHistory();
          final paths = (input['paths'] as List? ?? []).cast<String>().toSet();
          final entryIds = (input['entryIds'] as List? ?? []).cast<String>().toSet();
          final ids = (input['animeIds'] as List? ?? [])
              .map((id) => (id as num).toInt())
              .toSet();
          final selected = before
              .where((item) =>
                  paths.contains(item.filePath) || ids.contains(item.animeId) ||
                  entryIds.contains(stableMediaId('history', item.filePath)))
              .toList();
          for (final id in ids) {
            await WatchHistoryManager.removeHistoryByAnimeId(id);
          }
          for (final item
              in selected.where((item) => !ids.contains(item.animeId))) {
            await history.removeHistory(item.filePath);
          }
          await history.refresh();
          final remaining = (await WatchHistoryManager.getAllHistory())
              .map((item) => item.filePath)
              .toSet();
          if (selected.any((item) => remaining.contains(item.filePath))) {
            throw const Failure(FailureCode.unavailable,
                'Classic could not delete all selected history.');
          }
          return {
            'removedPaths': [for (final item in selected)
              if (paths.contains(item.filePath)) item.filePath],
            'removedEntryIds': [for (final item in selected)
              stableMediaId('history', item.filePath)],
            'removedCount': selected.length
          };
        }),
      ];
}
