import 'package:nipa_harness/nipa_harness.dart';

import '../downloads/qbittorrent_hub.dart';
import 'classic_action.dart';
import 'user_authorization.dart';

const _output = ObjectSchema({}, additionalProperties: true);

List<Action> downloadBackendActions(QbittorrentHub hub) => [
      ClassicAction(
          const ActionSpec(
              id: 'download.backends.list',
              title: '列出下载后端配置',
              description:
                  'List configured qBittorrent backends without secrets. '
                  'probe:true also checks each server now and returns its status. '
                  'Omitting probe only reads saved configuration. Use the returned '
                  'backend reference in download.add and download.limits.get/set.',
              effect: Effect.read,
              input: ObjectSchema({'probe': BooleanSchema()}),
              output: _output), (input, _) async {
        await hub.load();
        return {
          'backends': await Future.wait(hub.entries.map((entry) async => {
                ...entry.toJson(),
                'backend': {'kind': 'qbittorrent', 'id': entry.id},
                if (input['probe'] == true)
                  'status': await hub.backend(entry.id)?.status(),
              }))
        };
      }),
      ClassicAction(
          const ActionSpec(
              id: 'download.backends.save',
              title: '配置 qBittorrent 下载后端',
              description: 'After explicit user authorization, add or update a '
                  'qBittorrent backend. Omit id to add; supply an existing id to '
                  'update. local means its paths are on the target NipaPlay '
                  'device, not the agent device. Password and username go to the '
                  'credential vault and are never returned. Omit both to retain '
                  'the login; send both empty to clear it. Authorization must '
                  'cover the server/address and use of credentials, including '
                  'sending a retained login to a changed address. Credentials may '
                  'come from the user or an existing location they explicitly '
                  'authorize. No manual settings entry is required. Save registers '
                  'the backend immediately but does not prove connectivity; call '
                  'download.backends.list with probe:true to verify. A lost response '
                  'may follow a committed save: list before retrying an add.',
              effect: Effect.write,
              input: ObjectSchema({
                'id': StringSchema(minLength: 1),
                'name': StringSchema(minLength: 1),
                'address': StringSchema(minLength: 1),
                'local': BooleanSchema(),
                'username': StringSchema(secret: true),
                'password': StringSchema(secret: true),
                'userAuthorization': userAuthorizationSchema,
              }, required: [
                'name',
                'address',
                'local',
                'userAuthorization'
              ]),
              output: _output), (input, _) async {
        requireUserAuthorization(input);
        final entry = await hub.save(
            id: input['id'] as String?,
            name: input['name'] as String,
            address: input['address'] as String,
            local: input['local'] as bool,
            username: input['username'] as String?,
            password: input['password'] as String?);
        return {
          ...entry.toJson(),
          'backend': {'kind': 'qbittorrent', 'id': entry.id},
        };
      }),
      ClassicAction(
          const ActionSpec(
              id: 'download.backends.remove',
              title: '移除下载后端配置',
              description: 'After explicit user authorization, remove this '
                  'qBittorrent configuration and saved login. Does not delete '
                  'server torrents or files. Existing NipaPlay jobs keep their '
                  'receipts but cannot contact the removed backend.',
              effect: Effect.write,
              input: ObjectSchema({
                'id': StringSchema(minLength: 1),
                'userAuthorization': userAuthorizationSchema,
              }, required: [
                'id',
                'userAuthorization'
              ]),
              output: _output), (input, _) async {
        requireUserAuthorization(input);
        await hub.remove(input['id'] as String);
        return {'id': input['id'], 'removed': true};
      }),
    ];
