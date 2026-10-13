import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import '../harness_redaction.dart';

final class ClassicScanExecutor implements JobExecutor {
  ScanService? scan;
  WatchHistoryProvider? history;
  int Function() matchingConcurrency = () => 4;
  @override
  String get type => 'media.scan_classic';
  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) => _run(context);

  Future<void> _run(JobContext context) async {
    final scanner = scan;
    final current = await context.snapshot();
    if (current.cancelRequestedAt != null) {
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.acknowledged,
          details: {
            'outcomes': current.checkpoint['outcomes'] ?? [],
            'filesRetained': true
          }));
      return;
    }
    if (scanner == null || scanner.isScanning) {
      await context.retryAt(
          DateTime.now().toUtc().add(const Duration(seconds: 1)),
          const Failure(
              FailureCode.unavailable, 'Waiting for the Classic scanner.',
              retryable: true));
      return;
    }
    final outcomes = (context.job.checkpoint['outcomes'] as List? ?? [])
        .cast<JsonMap>()
        .toList();
    final paths = (context.job.input['paths'] as List).cast<String>();
    var stopped = false;
    context.stopRequested.then((_) => stopped = true);
    await context.running(phase: 'scan');
    Future<bool> proceed() async {
      if (stopped) return false;
      final job = await context.snapshot();
      return job.state != JobState.paused && job.cancelRequestedAt == null;
    }

    for (final path in paths.skip(outcomes.length)) {
      if (!await proceed()) break;
      if (!scanner.scannedFolders.contains(path)) {
        throw const Failure(
            FailureCode.conflict, 'Scan root was removed after submission.');
      }
      var enumerationFailed = false;
      final files = <JsonMap>[];
      await scanner.startDirectoryScan(path,
          skipPreviouslyMatchedUnwatched:
              context.job.input['skipPreviouslyMatchedUnwatched'] == true,
          matchingConcurrency: matchingConcurrency(),
          continueProcessing: proceed,
          onFailure: (_) => enumerationFailed = true,
          onResults: (results) {
            for (final result in results) {
              files.add({
                'path': result.filePath,
                'identified': result.success,
                'reason': result.errorMessage,
                'animeId': result.historyItem?.animeId,
                'episodeId': result.historyItem?.episodeId
              });
            }
          });
      if (!await proceed()) break;
      if (enumerationFailed) {
        throw const Failure(
            FailureCode.unavailable, 'Classic directory enumeration failed.',
            details: {
              'stage': 'enumerate',
              'recoveryAction':
                  'Check root availability and diagnostics.file_logs.'
            });
      }
      outcomes.add(redactHarnessJson({
        'path': path,
        'message': scanner.scanMessage,
        'files': files,
        'skippedUnchangedFiles':
            'Classic file-diff skips unchanged files; files lists attempted recognition only',
        'failedFiles': [
          for (final file in scanner.failedScanFiles)
            {'path': file.filePath, 'reason': file.errorMessage}
        ]
      }) as JsonMap);
      await context.markSideEffectCommitted(checkpoint: {'outcomes': outcomes});
      await context.report(
          progress: JobProgress(
              completed: outcomes.length,
              total: paths.length,
              unit: 'directories'));
    }
    await history?.refresh();
    final after = await context.snapshot();
    if (stopped && after.cancelRequestedAt == null) return;
    final receipt =
        JobReceipt(verification: VerificationLevel.verified, details: {
      'outcomes': outcomes,
      'scanned': outcomes.map((o) => o['path']).toList(),
      'filesRetained': true,
      'identificationFailuresArePerFile': true
    });
    if (after.cancelRequestedAt != null) {
      await context.cancelled(receipt);
    } else {
      await context.succeed(receipt);
    }
  }
}
