import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:path/path.dart' as p;

import '../media/media_service.dart';

final class UiOpenValue implements JsonEncodable {
  const UiOpenValue(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class UiOpenAction extends Action<UiOpenValue, UiOpenValue> {
  const UiOpenAction({this.media, this.openPage, this.openDetail, this.play});
  final MediaService Function()? media;
  final Future<bool> Function(String page)? openPage;
  final Future<bool> Function(int animeId)? openDetail;
  final Future<Outcome<JsonEncodable>> Function(JsonMap, Invocation)? play;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'ui.open',
        title: 'Open a visible Classic target',
        effect: Effect.write,
        description:
            'Supply exactly one page, entityId or path. Opens Classic work details or file/episode playback. '
            'Returns opened=false with the reason when no current interface can display the target. '
            'Multiple playable locations return an executable choice; nothing opens until chosen.',
        input: ObjectSchema({
          'page': StringSchema(values: AppPageIds.primaryOrder),
          'entityId': StringSchema(minLength: 1),
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
        'message': '目前没有界面能显示它：$reason',
      }));
  Completed<UiOpenValue> _opened(JsonMap target, JsonMap actual) =>
      Completed(UiOpenValue({
        'opened': true,
        'interface': 'classic',
        'target': target,
        'actual': actual,
        'reason': null,
        'message': null,
      }));

  Future<Outcome<UiOpenValue>> _play(
      JsonMap target, String path, Invocation invocation) async {
    if (play == null) return _unavailable(target, 'Classic 播放界面尚未连接。');
    final outcome = await play!({'path': path}, invocation);
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
    if (target.length != 1) {
      throw const Failure(FailureCode.invalidInput,
          'Supply exactly one page, entityId or path.');
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
    final id = target['entityId'] as String;
    final entity = await service.store.entity(id);
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
          '该${entity['kind']}没有唯一已接受的弹弹play作品身份，Classic 作品详情仅支持弹弹play；Next 事实页尚未实现。');
    }
    final animeId = int.tryParse(bindings.single['external_id'] as String);
    if (animeId == null || animeId <= 0) {
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
