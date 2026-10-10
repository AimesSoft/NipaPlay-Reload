import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Invocation;
import 'package:nipaplay/next/downloads/builtin_download_backend.dart';
import 'package:nipaplay/services/torrent_download_service.dart';

void main() {
  test(
      'native String errors from controls become explicit unavailable failures',
      () async {
    final backend =
        BuiltinDownloadBackend(_FailingService('native session unavailable'));
    for (final operation in [
      backend.initialize,
      () => backend.pause('1'),
      () => backend.resume('1'),
      () => backend.remove('1'),
    ]) {
      await expectLater(
          operation(),
          throwsA(isA<Failure>()
              .having(
                  (failure) => failure.code, 'code', FailureCode.unavailable)
              .having((failure) => failure.message, 'message',
                  'native session unavailable')));
    }
  });

  test('implementation defects remain exceptions for the Harness catch-all',
      () async {
    final backend =
        BuiltinDownloadBackend(_FailingService(StateError('defect')));
    await expectLater(backend.resume('1'), throwsStateError);
  });
}

class _FailingService implements TorrentDownloadService {
  _FailingService(this.error);
  final Object error;
  @override
  Future<void> initialize() async => throw error;
  @override
  Future<void> pause(int id) async => throw error;
  @override
  Future<void> resume(int id) async => throw error;
  @override
  Future<void> forget(int id) async => throw error;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
