import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Action, Invocation;
import 'package:nipa_harness/nipa_harness.dart' as harness_api show Invocation;
import 'package:nipaplay/next/mesh/chat_attachment.dart';
import 'package:nipaplay/next/mesh/chat_guest_host.dart';
import 'package:nipaplay/next/mesh/nipa_peers.dart';
import 'package:nipaplay/next/ui/chat/attach_button.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart'
    show ChatUnavailable;
import 'package:nipaplay/next/ui/conversation/mesh_chat_port.dart';
import 'package:nipaplay/next/ui/conversation/nipa_chat.dart';
import 'package:nipaplay/next/ui/widgets/sheet.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

import 'mesh_delegation_support.dart';

final class _FakePicker implements AttachmentPicker {
  _FakePicker({this.pickedFiles = const [], this.pickedPictures = const []});
  final List<String> pickedFiles;
  final List<String> pickedPictures;
  bool fail = false;
  int fileCalls = 0;
  int pictureCalls = 0;

  @override
  Future<List<String>> files() async {
    fileCalls++;
    if (fail) throw StateError('picker unavailable');
    return pickedFiles;
  }

  @override
  Future<List<String>> pictures() async {
    pictureCalls++;
    if (fail) throw StateError('photos unavailable');
    return pickedPictures;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttachButton', () {
    Widget host(Widget child) => MaterialApp(
          home: Stack(
            children: [
              Scaffold(body: Center(child: child)),
              const NextSheetLayer(),
            ],
          ),
        );

    testWidgets('desktop opens file dialog directly and reports selected paths',
        (tester) async {
      final picker = _FakePicker(pickedFiles: ['/tmp/sub.ass']);
      final attached = <List<String>>[];
      await tester.pumpWidget(host(AttachButton(
        onFiles: attached.add,
        picker: picker,
        offerPictures: false,
      )));
      await tester.tap(find.byKey(const Key('chat.attach')));
      await tester.pumpAndSettle();
      expect(picker.fileCalls, 1);
      expect(picker.pictureCalls, 0);
      expect(attached, [
        ['/tmp/sub.ass']
      ]);
    });

    testWidgets('phone offers photos and files choices in a sheet',
        (tester) async {
      final picker = _FakePicker(
          pickedPictures: ['/tmp/shot.png'], pickedFiles: ['/tmp/log.txt']);
      final attached = <List<String>>[];
      await tester.pumpWidget(host(AttachButton(
        onFiles: attached.add,
        picker: picker,
        offerPictures: true,
      )));

      await tester.tap(find.byKey(const Key('chat.attach')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.attach.pictures')), findsOneWidget);
      expect(find.byKey(const Key('chat.attach.files')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat.attach.pictures')));
      await tester.pumpAndSettle();
      expect(picker.pictureCalls, 1);
      expect(attached.single, ['/tmp/shot.png']);

      await tester.tap(find.byKey(const Key('chat.attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.attach.files')));
      await tester.pumpAndSettle();
      expect(picker.fileCalls, 1);
      expect(attached.last, ['/tmp/log.txt']);
    });

    testWidgets(
        'disabled button does not open picker; picker errors are caught',
        (tester) async {
      final picker = _FakePicker()..fail = true;
      final attached = <List<String>>[];
      await tester.pumpWidget(host(AttachButton(
        onFiles: attached.add,
        enabled: false,
        picker: picker,
        offerPictures: false,
      )));
      await tester.tap(find.byKey(const Key('chat.attach')));
      await tester.pumpAndSettle();
      expect(picker.fileCalls, 0);

      await tester.pumpWidget(host(AttachButton(
        onFiles: attached.add,
        enabled: true,
        picker: picker,
        offerPictures: false,
      )));
      await tester.tap(find.byKey(const Key('chat.attach')));
      await tester.pumpAndSettle();
      expect(picker.fileCalls, 1);
      expect(attached, isEmpty);
    });
  });

  testWidgets('refused: says why instead of picking', (tester) async {
    final picker = _FakePicker(pickedFiles: ['/tmp/a.png']);
    final attached = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
      Scaffold(
          body: Center(
              child: AttachButton(
                  onFiles: attached.add,
                  picker: picker,
                  offerPictures: false,
                  refused: '「MacBook」上的 NipaPlay 需要更新后才能接收附件。'))),
      const NextSheetLayer(),
    ])));
    await tester.tap(find.byKey(const Key('chat.attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.attach.refused')), findsOneWidget);
    expect(picker.fileCalls, 0);
    expect(attached, isEmpty);
  });

  group('Mesh attachment staging (mesh/chat/attach + MeshChatPort + NipaChat)',
      () {
    late Directory dir;
    late FakeChat chat;
    late ChatGuests guests;
    late NipaPeers peers;
    late MeshChatPort port;
    final changed = StreamController<void>.broadcast();

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mesh-chat-attach-');
      chat = FakeChat();
      guests = ChatGuests(
        root: Directory('${dir.path}/host')..createSync(),
        chat: () => chat,
        unavailableReason: () => null,
        deviceName: (id) => const {'ipad': 'iPad', 'phone': 'Phone'}[id],
        record: (_, __, ___) async {},
      );
      await guests.attach(chat);
      peers = NipaPeers(
        root: Directory('${dir.path}/ipad')..createSync(),
        devices: () async => [
          {
            'deviceId': 'mac',
            'name': 'MacBook',
            'online': true,
            'agent': {'runs': true, 'busy': false}
          },
        ],
        hostChanges: changed.stream,
      );
      await peers.refresh();
      await peers.choose('mac');
      port = MeshChatPort(
        call: (peer, method, params) => guests.handle(method, params, 'ipad'),
        hostChanges: changed.stream,
        peers: peers,
        retry: const Duration(milliseconds: 100),
      );
    });

    tearDown(() async {
      port.dispose();
      await peers.close();
      await guests.close();
      await chat.close();
      await dir.delete(recursive: true);
    });

    test('stages multi-chunk files across mesh and sanitizes filenames',
        () async {
      // Larger than chatAttachmentChunk (384 KiB) to exercise multi-chunking.
      final payload =
          List<int>.generate(chatAttachmentChunk + 4096, (i) => i % 251);
      final local = File('${dir.path}/..evil:clip.bin');
      await local.writeAsBytes(payload, flush: true);

      final staged = await port.stage([local.path]);
      expect(staged, hasLength(1));
      final remote = File(staged.single);
      expect(await remote.exists(), isTrue);
      expect(await remote.readAsBytes(), payload);
      expect(remote.path, contains('/chat-attachments/guests/ipad/'));
      expect(remote.path, isNot(contains(':')));

      // Windows would write "notes" for "notes. ": the path told to Nipa
      // must be the file written.
      final dotted = await guests.handle(
          'mesh/chat/attach',
          {
            'name': 'notes. ',
            'size': 2,
            'offset': 0,
            'data': base64Encode([1, 2]),
          },
          'ipad');
      expect(dotted['path'], endsWith('-notes'));
    });

    test('an older host that does not take files is told apart, not tried',
        () async {
      var attaches = 0;
      final old = MeshChatPort(
        call: (peer, method, params) async {
          if (method == 'mesh/chat/attach') attaches++;
          final result = await guests.handle(method, params, 'ipad');
          return method == 'mesh/chat/state'
              ? ({...result}..remove('attachments'))
              : result;
        },
        hostChanges: changed.stream,
        peers: peers,
        retry: const Duration(milliseconds: 100),
      );
      addTearDown(old.dispose);
      for (var i = 0; i < 50 && old.filesRefused == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(old.filesRefused, contains('需要更新'));
      final file = File('${dir.path}/a.txt')..writeAsStringSync('x');
      await expectLater(
          old.stage([file.path]), throwsA(isA<ChatUnavailable>()));
      expect(attaches, 0);
    });

    test('copies older than 30 days and forgotten parts are swept', () async {
      final folder = Directory('${dir.path}/host/chat-attachments/guests/ipad')
        ..createSync(recursive: true);
      final now = DateTime.now();
      final aged = File('${folder.path}/old-shot.png')..writeAsStringSync('o');
      aged.setLastModifiedSync(now.subtract(const Duration(days: 31)));
      final recent = File('${folder.path}/new-shot.png')
        ..writeAsStringSync('n');
      recent.setLastModifiedSync(now.subtract(const Duration(days: 2)));
      final part = File('${folder.path}/.abcdefghijkl.part')
        ..writeAsStringSync('p');
      part.setLastModifiedSync(now.subtract(const Duration(hours: 2)));
      // A file that was sent with a name ending in .part is a finished copy.
      final sent = File('${folder.path}/k3j2h1g0f9e8-notes.part')
        ..writeAsStringSync('s');
      sent.setLastModifiedSync(now.subtract(const Duration(hours: 2)));
      await guests.handle(
          'mesh/chat/attach',
          {
            'name': 'today.txt',
            'size': 1,
            'offset': 0,
            'data': base64Encode([7])
          },
          'ipad');
      expect(aged.existsSync(), isFalse);
      expect(part.existsSync(), isFalse);
      expect(recent.existsSync(), isTrue);
      expect(sent.existsSync(), isTrue);
    });

    test('two chunks for the same place at once: one is taken', () async {
      final first = await guests.handle(
          'mesh/chat/attach',
          {
            'name': 'clip.bin',
            'size': 6,
            'offset': 0,
            'data': base64Encode([1, 2])
          },
          'ipad');
      final uploadId = first['uploadId'] as String;
      Future<Object> chunk() => guests
          .handle(
              'mesh/chat/attach',
              {
                'uploadId': uploadId,
                'size': 6,
                'offset': 2,
                'data': base64Encode([3, 4])
              },
              'ipad')
          .then<Object>((r) => r, onError: (Object e) => e);
      final both = await Future.wait([chunk(), chunk()]);
      expect(both.whereType<Map>().single['received'], 4);
      expect(both.whereType<Failure>().single.code, FailureCode.invalidInput);
      final done = await guests.handle(
          'mesh/chat/attach',
          {
            'uploadId': uploadId,
            'size': 6,
            'offset': 4,
            'data': base64Encode([5, 6])
          },
          'ipad');
      expect(
          await File(done['path'] as String).readAsBytes(), [1, 2, 3, 4, 5, 6]);
    });

    test(
        'rejects cross-peer hijack, invalid offsets, and cleans .part on close',
        () async {
      final first = await guests.handle(
        'mesh/chat/attach',
        {
          'name': 'partial.txt',
          'size': 10,
          'offset': 0,
          'data': base64Encode(utf8.encode('hello')),
        },
        'ipad',
      );
      final uploadId = first['uploadId'] as String;
      expect(first['received'], 5);
      expect(first['path'], isNull);

      // Another peer cannot continue ipad's upload.
      await expectLater(
        guests.handle(
          'mesh/chat/attach',
          {
            'uploadId': uploadId,
            'size': 10,
            'offset': 5,
            'data': base64Encode(utf8.encode('world')),
          },
          'phone',
        ),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', FailureCode.notFound)),
      );

      // Wrong offset is rejected with received hint.
      await expectLater(
        guests.handle(
          'mesh/chat/attach',
          {
            'uploadId': uploadId,
            'size': 10,
            'offset': 0,
            'data': base64Encode(utf8.encode('world')),
          },
          'ipad',
        ),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', FailureCode.invalidInput)),
      );

      // Closing removes abandoned .part files.
      final partFile =
          File('${dir.path}/host/chat-attachments/guests/ipad/.$uploadId.part');
      expect(await partFile.exists(), isTrue);
      await guests.close();
      expect(await partFile.exists(), isFalse);
    });

    test('NipaChat stages files on send and preserves attachments on failure',
        () async {
      final nipa = NipaChat(port: port, data: _ChatData());
      addTearDown(nipa.dispose);
      await nipa.refreshSessions();

      final valid = File('${dir.path}/notes.txt');
      await valid.writeAsString('subtitle notes');
      nipa.attach([valid.path]);
      await nipa.say('帮我看看这个文件');
      final (_, sentText) = chat.started.single;
      expect(sentText, contains('/chat-attachments/guests/ipad/'));
      expect(sentText, contains('notes.txt'));
      expect(nipa.attachments, isEmpty);

      // Empty file fails staging cleanly and keeps the attachment queued.
      final empty = File('${dir.path}/empty.txt');
      await empty.writeAsBytes(const []);
      nipa.attach([empty.path]);
      await nipa.say('发空文件');
      expect(nipa.attachments, [empty.path]);
      expect(nipa.rawError.value?.message, contains('空的'));
    });

    test('attachment action stages on a device without reading a conversation',
        () async {
      final file = File('${dir.path}/attachment.bin');
      final payload = List<int>.filled(chatAttachmentChunk + 13, 42);
      await file.writeAsBytes(payload);
      var loseReceipt = false;
      final methods = <String>[];
      final harness = Harness([
        ChatAttachmentCapability((peer, method, params) async {
          expect(peer, 'mac');
          methods.add(method);
          final result = await guests.handle(method, params, 'ipad');
          if (loseReceipt &&
              method == 'mesh/chat/attach' &&
              result['path'] != null) {
            throw const Failure(FailureCode.unavailable, 'lost receipt',
                details: {'reason': 'outcome_unknown'});
          }
          return result;
        })
      ]);
      Future<JsonMap> send({String? legacyThread}) async {
        final result = await harness.invokeJson(
            'chat.attachment.send',
            {
              'path': file.path,
              'deviceId': 'mac',
              if (legacyThread != null) 'threadId': legacyThread,
            },
            harness_api.Invocation(origin: 'test'));
        expect(result, isA<Completed<JsonEncodable>>());
        return (result as Completed<JsonEncodable>).value.toJson() as JsonMap;
      }

      final staged = await send(legacyThread: 'no-such-thread');
      expect(staged['status'], 'staged');
      expect(staged['deviceId'], 'mac');
      expect(staged.containsKey('threadId'), isFalse);
      expect(staged['received'], payload.length);
      expect(await File(staged['path'] as String).readAsBytes(), payload);
      expect(
          methods, ['mesh/chat/state', 'mesh/chat/attach', 'mesh/chat/attach']);
      expect(chat.started, isEmpty);
      loseReceipt = true;
      final unknown = await send();
      expect(unknown['status'], 'outcomeUnknown');
      expect(unknown['received'], chatAttachmentChunk);
      expect(unknown['path'], isNull);
      expect(unknown.containsKey('threadId'), isFalse);
    });
  });
}

final class _ChatData implements NextUiData {
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Stream<List<UiTask>> tasks() => const Stream.empty();
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
