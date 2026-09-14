import 'dart:async';
import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

import 'fake_path_provider_windows.dart';

class CountingPathProvider extends FakePathProviderWindows {
  int calls = 0;
  @override
  Future<String?> getApplicationSupportPath() {
    calls++;
    return super.getApplicationSupportPath();
  }
}

// Implements only async disk operations: any sync call fails the test.
class AsyncOnlyFile implements File {
  AsyncOnlyFile(this.delegate);
  final File delegate;
  final firstWrite = Completer<void>();
  final releaseWrite = Completer<void>();
  final writes = <String>[];
  @override
  Future<bool> exists() => delegate.exists();
  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await delegate.create(recursive: recursive);
    return this;
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      delegate.readAsString(encoding: encoding);
  @override
  Future<File> writeAsString(String contents,
      {FileMode mode = FileMode.write,
      Encoding encoding = utf8,
      bool flush = false}) async {
    writes.add(contents);
    if (writes.length == 1) {
      firstWrite.complete();
      await releaseWrite.future;
    }
    await delegate.writeAsString(contents,
        mode: mode, encoding: encoding, flush: flush);
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected disk operation: ${invocation.memberName}');
}

class AsyncOnlyFileSystem implements FileSystem {
  AsyncOnlyFileSystem(this.target);
  final AsyncOnlyFile target;
  @override
  File file(dynamic path) => target;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('slow disk leaves event loop free and preserves write order', () async {
    final disk = MemoryFileSystem.test();
    final file = AsyncOnlyFile(disk.file('/preferences.json'));
    final provider = CountingPathProvider();
    final prefs = SharedPreferencesWindows()
      ..fs = AsyncOnlyFileSystem(file)
      ..pathProvider = provider;
    await prefs.getAll();
    final first = prefs.setValue('Int', 'flutter.position', 1000);
    await file.firstWrite.future;
    final second = prefs.setValue('Int', 'flutter.position', 2000);
    // A rendering/event-loop task can run while the disk write is blocked.
    await Future<void>.delayed(Duration.zero);
    expect(file.writes, hasLength(1));
    expect(jsonDecode(file.writes.single)['flutter.position'], 1000);
    file.releaseWrite.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(file.writes, hasLength(2));
    expect(jsonDecode(await file.readAsString())['flutter.position'], 2000);
    expect(provider.calls, 1,
        reason: 'Repeated saves must not query Win32 paths');
  });
}
