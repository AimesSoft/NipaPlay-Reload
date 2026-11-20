import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:nipa_harness/nipa_harness.dart';

import '../capabilities/classic_action.dart';
import 'chat_guest_host.dart' show chatAttachmentChunk, chatAttachmentLimit;

typedef ChatAttachmentRpc = Future<JsonMap> Function(
    String peer, String method, JsonMap params);

final class ChatAttachmentCapability implements Capability {
  ChatAttachmentCapability(ChatAttachmentRpc rpc)
      : actions = [
          ClassicAction(
            const ActionSpec(
              id: 'chat.attachment.send',
              title: '向另一台设备的会话交付附件',
              description:
                  'Stage an explicit local file for an existing conversation on another device. Returns the remote path and byte count on delivery; no message or turn is started. An unknown result means the final chunk may have landed without an acknowledgement.',
              effect: Effect.write,
              input: ObjectSchema({
                'path': StringSchema(minLength: 1),
                'deviceId': StringSchema(minLength: 1),
                'threadId': StringSchema(minLength: 1),
              }, required: [
                'path',
                'deviceId',
                'threadId'
              ]),
              output: ObjectSchema({}, additionalProperties: true),
            ),
            (input, _) async {
              final peer = input['deviceId'] as String;
              final thread = input['threadId'] as String;
              final path = input['path'] as String;
              if (!File(path).isAbsolute) {
                throw const Failure(
                    FailureCode.invalidInput, 'Supply an absolute local path.');
              }
              final target = {'deviceId': peer, 'threadId': thread};
              try {
                final state = await rpc(peer, 'mesh/chat/state', {});
                if (state['attachments'] != true) {
                  throw const Failure(FailureCode.unavailable, '目标未报告支持附件');
                }
                final conversation = await rpc(
                    peer, 'mesh/chat/read', {'threadId': thread, 'turns': 1});
                if ((conversation['thread'] as Map?)?['id'] != thread) {
                  throw const Failure(FailureCode.notFound, '未确认目标会话');
                }
                return {
                  ...target,
                  ...await stageChatAttachment(
                      path, (params) => rpc(peer, 'mesh/chat/attach', params))
                };
              } on Failure catch (failure) {
                return {
                  ...target,
                  'status': 'notDelivered',
                  'reason': failure.message
                };
              }
            },
          )
        ];

  @override
  final List<Action> actions;
}

Future<JsonMap> stageChatAttachment(
    String path, Future<JsonMap> Function(JsonMap) send) async {
  final file = File(path);
  final name = path.split(RegExp(r'[\\/]')).last;
  var received = 0;
  String? uploadId;
  var finalChunkSent = false;
  try {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const Failure(FailureCode.notFound, '找不到指定文件');
    }
    final size = stat.size;
    if (size == 0 || size > chatAttachmentLimit) {
      throw Failure(FailureCode.invalidInput,
          size == 0 ? '文件是空的' : '文件超过 ${chatAttachmentLimit >> 20} MiB');
    }
    final input = await file.open();
    try {
      while (received < size) {
        final count = math.min(chatAttachmentChunk, size - received);
        final bytes = await input.read(count);
        if (bytes.length != count || await input.length() != size) {
          throw const Failure(FailureCode.conflict, '传输时文件大小变化');
        }
        final next = received + count;
        finalChunkSent = next == size;
        final result = await send({
          'name': name,
          'size': size,
          'offset': received,
          'data': base64Encode(bytes),
          if (uploadId != null) 'uploadId': uploadId,
        });
        final id = result['uploadId'];
        final reference = result['path'];
        if (id is! String ||
            id.isEmpty ||
            (uploadId != null && id != uploadId) ||
            result['received'] != next ||
            (finalChunkSent
                ? reference is! String || reference.isEmpty
                : reference != null)) {
          throw const FormatException('无效的附件传输回执');
        }
        uploadId = id;
        received = next;
        if (finalChunkSent) {
          return {
            'status': 'delivered',
            'received': received,
            'uploadId': id,
            'path': reference
          };
        }
      }
      throw StateError('附件缺少最终回执');
    } finally {
      await input.close();
    }
  } catch (error) {
    final unknown = finalChunkSent &&
        (error is! Failure || error.details['reason'] == 'outcome_unknown');
    return {
      'status': unknown ? 'outcomeUnknown' : 'notDelivered',
      'received': received,
      if (uploadId != null) 'uploadId': uploadId,
      'reason': switch (error) {
        Failure(:final message) => message,
        FileSystemException() => '未能读取指定文件',
        FormatException(:final message) => message,
        _ => '未收到有效的传输结果',
      },
    };
  }
}
