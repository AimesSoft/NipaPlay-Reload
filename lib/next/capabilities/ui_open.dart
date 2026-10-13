import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:path/path.dart' as p;

import '../media/media_service.dart';
import 'ui_targets.dart';

final class UiOpenValue implements JsonEncodable {
  const UiOpenValue(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class UiOpenAction extends Action<UiOpenValue, UiOpenValue> {
  const UiOpenAction(
      {this.media, this.openPage, this.openDetail, this.openWork, this.openTarget, this.play, this.resolveEntity});
  final Future<JsonMap?> Function(String)? resolveEntity;
  final MediaService Function()? media;
  final Future<bool> Function(String page)? openPage;
  final Future<bool> Function(int animeId)? openDetail;
  final Future<bool?> Function(String workId)? openWork;
  final Future<JsonMap?> Function(JsonMap target)? openTarget;
  final Future<Outcome<JsonEncodable>> Function(JsonMap, Invocation)? play;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'ui.open',
        title: '打开页面',
        effect: Effect.write,
        description:
            'Supply exactly one page, dialog, animeId, serverItem, sourceItem, libraryItem, aboutLink, system, entityId, workId or path. '
            'entityId/workId for a work opens Next details when Next is visible, otherwise follows Classic details. '
            'page=settings accepts subpage (defaults about); page=media_library accepts subpage for library section. '
            'Settings and dialogs use existing Classic forms; user enters secrets. Dialog connection forms add a server; no credentials accepted. '
            'serverItem={provider:jellyfin|emby,itemId} uses the currently active Classic server. animeId supports direct positive or custom negative Classic IDs. '
            'sourceItem={provider:nipaplay|dandanplay_remote,animeId} opens Classic shared/remote details with its episode loader on the active Classic source. '
            'libraryItem={source:local|webdav|smb,animeId} follows the Classic library card: records recently opened, clears NEW baseline and passes its episode context. '
            'dialog=quarterly_comment requires reviewAnimeId from discover.home.review; opens the existing Bangumi editor when signed in. '
            'aboutLink=community|repository|qq_group|website|sponsor uses the Classic URL; qr=true displays its QR dialog (TV defaults to QR). '
            'system=harness|logs dispatches the existing system folder opener. External URLs/folders report OS acceptance, not visible window verification. '
            'dialog=video_picker|video_gallery initiates the existing Classic selection/play flow; user selects or cancels. video_gallery is mobile-only. Native picker visibility is outside Flutter observation. '
            'Returns opened=false with the reason when no current interface can display the target. '
            'Multiple playable locations return an executable choice; nothing opens until chosen.',
        input: ObjectSchema({
          'page': StringSchema(
              values: [...AppPageIds.primaryOrder, 'settings', 'new_series']),
          'subpage': StringSchema(
              minLength: 1,
              description:
                  'For settings: appearance/language/general/storage/network/backup_restore/player/danmaku/external_player/shortcuts/remote_access/remote_media_library/downloader/developer_options/labs/plugins/about/webdav_quick. Only currently available Classic pages can open. For media_library: local_library/local_management/webdav_library/webdav_management/smb_library/smb_management/shared_library/shared_management/dandanplay/jellyfin/emby.'),
          'dialog': StringSchema(values: uiDialogs),
          'pluginId': StringSchema(
              minLength: 1,
              description:
                  'Required only for dialog=plugin_readme. Use plugins.market IDs.'),
          'reviewAnimeId': IntegerSchema(minimum: 1),
          'aboutLink': StringSchema(values: uiAboutLinks),
          'qr': BooleanSchema(),
          'system': StringSchema(values: ['harness', 'logs']),
          'animeId': IntegerSchema(),
          'serverItem': ObjectSchema({
            'provider': StringSchema(values: ['jellyfin', 'emby']),
            'itemId': StringSchema(minLength: 1),
          }, required: [
            'provider',
            'itemId'
          ]),
          'sourceItem': ObjectSchema({
            'provider': StringSchema(values: ['nipaplay', 'dandanplay_remote']),
            'animeId': IntegerSchema(),
          }, required: [
            'provider',
            'animeId'
          ]),
          'libraryItem': ObjectSchema({
            'source': StringSchema(values: ['local', 'webdav', 'smb']),
            'animeId': IntegerSchema(),
          }, required: [
            'source',
            'animeId'
          ]),
          'entityId': StringSchema(minLength: 1),
          'workId': StringSchema(minLength: 1),
          'path': StringSchema(minLength: 1),
        }),
        output: ObjectSchema({
          'opened': BooleanSchema(),
          'interface': StringSchema(nullable: true),
          'target': ObjectSchema({}, additionalProperties: true),
          'actual':
              ObjectSchema({}, additionalProperties: true, nullable: true),
          'reason': StringSchema(nullable: true),
          'message': StringSchema(nullable: true),
        }, required: [
          'opened',
          'interface',
          'target',
          'actual',
          'reason',
          'message'
        ]),
      );
  @override
  UiOpenValue decodeInput(JsonMap input) => UiOpenValue(input);

  Completed<UiOpenValue> _unavailable(JsonMap target, String reason) =>
      Completed(UiOpenValue({
        'opened': false,
        'interface': null,
        'target': target,
        'actual': null,
        'reason': reason,
        'message': '暂时无法打开。',
      }));
  Completed<UiOpenValue> _opened(JsonMap target, JsonMap actual) =>
      Completed(UiOpenValue({
        'opened': actual['matched'] != false,
        'interface': actual['interface'] ?? (actual['presentation'] == 'system' ? 'system' : 'classic'),
        'target': target,
        'actual': actual,
        'reason': actual['matched'] == false ? '目标界面当前不可用。' : null,
        'message': actual['matched'] == false ? '暂时无法打开。' : null,
      }));

  Future<Outcome<UiOpenValue>> _play(
      JsonMap target, String path, Invocation invocation, {int? startPositionMs}) async {
    if (play == null) return _unavailable(target, 'Classic 播放界面尚未连接。');
    final outcome = await play!({'path': path, if (startPositionMs != null) 'startPositionMs': startPositionMs}, invocation);
    if (outcome is Failed) return Failed(outcome.failure);
    if (outcome is NeedsDecision) return NeedsDecision(outcome.decision);
    final result = (outcome as Completed).value.toJson();
    if (result['player'] == 'external') {
      return Completed(UiOpenValue({
        'opened': true,
        'interface': 'external_player',
        'target': target,
        'actual': {'kind': 'playback', ...result},
        'reason': null,
        'message': '已交给用户配置的外部播放器。'
      }));
    }
    return _opened(target, {'kind': 'playback', ...result});
  }

  @override
  Future<Outcome<UiOpenValue>> run(
      UiOpenValue input, Invocation invocation) async {
    final target = input.value;
    final keys = [
      'page',
      'dialog',
      'animeId',
      'serverItem',
      'sourceItem',
      'libraryItem',
      'aboutLink',
      'system',
      'entityId',
      'workId',
      'path'
    ];
    if (keys.where(target.containsKey).length != 1 ||
        (target.containsKey('subpage') &&
            !['settings', 'media_library'].contains(target['page']))) {
      throw const Failure(FailureCode.invalidInput,
          'Supply exactly one target. subpage is only valid with settings or media_library.');
    }
    if ((target['dialog'] == 'plugin_readme') !=
        target.containsKey('pluginId')) {
      throw const Failure(FailureCode.invalidInput,
          'pluginId is required only for dialog=plugin_readme.');
    }
    if ((target['dialog'] == 'quarterly_comment') !=
            target.containsKey('reviewAnimeId') ||
        (target.containsKey('qr') && !target.containsKey('aboutLink'))) {
      throw const Failure(FailureCode.invalidInput,
          'reviewAnimeId is required only for quarterly_comment; qr only applies to aboutLink.');
    }
    if (target['page'] == 'settings' &&
        target.containsKey('subpage') &&
        !uiSettingsSubpages.contains(target['subpage'])) {
      throw const Failure(
          FailureCode.invalidInput, 'Unknown settings subpage.');
    }
    if (target.containsKey('dialog') ||
        target.containsKey('serverItem') ||
        target.containsKey('sourceItem') ||
        target.containsKey('libraryItem') ||
        target.containsKey('aboutLink') ||
        target.containsKey('system') ||
        target['page'] == 'settings' ||
        target['page'] == 'new_series' ||
        target.containsKey('subpage')) {
      final actual = await openTarget?.call(target);
      return actual == null
          ? _unavailable(target, '目标界面当前不可用。')
          : _opened(target, actual);
    }
    if (target['animeId'] case final int id) {
      if (id == 0)
        throw const Failure(
            FailureCode.invalidInput, 'animeId must be nonzero.');
      if (openDetail == null || !await openDetail!(id))
        return _unavailable(target, '作品详情尚未就绪。');
      return _opened(target, {'kind': 'work_detail', 'animeId': id});
    }
    if (target['page'] case final String page) {
      if (openPage == null || !await openPage!(page)) {
        return _unavailable(target, 'Classic 当前没有可见的 $page 页面。');
      }
      return _opened(target, {'kind': 'page', 'page': page});
    }
    final service = media?.call();
    if (service == null) return _unavailable(target, '媒体事实尚未连接。');
    if (target['path'] case final String path) {
      final uri = Uri.tryParse(path);
      final local = uri?.scheme == 'file' ? uri!.toFilePath() : path;
      return _play(
          target,
          p.isAbsolute(local) ? await service.authorizedPath(local) : path,
          invocation);
    }
    final id = (target['entityId'] ?? target['workId']) as String;
    final merged = await resolveEntity?.call(id);
    if (merged != null) {
      if (merged['sourcePlayback'] case final Map result) {
        return _opened(target, {'kind': 'playback', ...Map<String, Object?>.from(result)});
      }
      if (merged['workId'] case final String workId) {
        final opened = await openWork?.call(workId);
        return opened == true ? _opened(target, {'kind': 'work_detail', 'workId': workId, 'interface': 'next'})
            : _unavailable(target, '作品详情尚未就绪。');
      }
      final path = (merged['url'] ?? merged['path']) as String;
      return _play(target, path, invocation, startPositionMs: merged['resumeMs'] as int?);
    }
    final entity = await service.store.entity(id);
    if (target.containsKey('workId') && entity['kind'] != 'work') {
      throw const Failure(FailureCode.invalidInput, '请选择一部作品。');
    }
    if (entity['kind'] == 'work') {
      final opened = await openWork?.call(id);
      if (opened != null) {
        return opened ? _opened(target, {'kind': 'work_detail', 'workId': id, 'interface': 'next'})
            : _unavailable(target, '作品详情还没准备好。');
      }
    }
    if (entity['kind'] == 'file' || entity['kind'] == 'episode') {
      final rows = await service.store.database.rawQuery(
          entity['kind'] == 'file'
              ? 'SELECT locator FROM media_locations WHERE file_id=? AND owner_device_id=? AND available=1 ORDER BY id'
              : 'SELECT DISTINCT l.locator FROM media_file_episodes e JOIN media_locations l ON l.file_id=e.file_id '
                  'WHERE e.episode_id=? AND l.owner_device_id=? AND l.available=1 ORDER BY l.locator',
          [id, service.store.ownerDeviceId]);
      if (rows.length == 1) {
        return _play(target, rows.single['locator'] as String, invocation);
      }
      if (rows.length > 1) {
        return NeedsDecision(Decision(
            prompt: 'Which recorded location should Classic play?',
            options: [
              for (final row in rows)
                DecisionOption(
                    label: row['locator'] as String,
                    call: ActionCall('ui.open', {'path': row['locator']})),
            ]));
      }
      if (entity['kind'] == 'file') {
        return _unavailable(target, '该文件没有本机可播放的位置，Classic 没有独立事实页。');
      }
    }
    var detailEntity = entity;
    while (
        detailEntity['kind'] != 'work' && detailEntity['parent_id'] != null) {
      detailEntity =
          await service.store.entity(detailEntity['parent_id'] as String);
    }
    final bindings = await service.store.database.rawQuery(
        "SELECT DISTINCT o.external_id FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id "
        "WHERE b.entity_id=? AND b.status='accepted' AND o.provider='dandanplay' AND o.object_type IN ('work','anime')",
        [detailEntity['id']]);
    if (bindings.length != 1) {
      return _unavailable(target,
          '还没有找到这部作品的详情。');
    }
    final animeId = int.tryParse(bindings.single['external_id'] as String);
    if (animeId == null || animeId == 0) {
      return _unavailable(target, '弹弹play作品 ID 无法用于 Classic 详情页。');
    }
    if (openDetail == null || !await openDetail!(animeId)) {
      return _unavailable(target, 'Classic 作品详情窗口尚未就绪。');
    }
    return _opened(target, {
      'kind': 'work_detail',
      'animeId': animeId,
      'entityId': detailEntity['id']
    });
  }
}
