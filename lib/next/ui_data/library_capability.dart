import 'package:nipa_harness/nipa_harness.dart';
import '../mesh/library_codec.dart';
import 'library.dart';
import 'library_service.dart';

const _id = StringSchema(minLength: 1);
const libraryFilterSchema = ObjectSchema({
  'sourceIds': ArraySchema(_id),
  'deviceIds': ArraySchema(_id),
  'types': ArraySchema(StringSchema(values: ['anime', 'series', 'movie'])),
  'watch': StringSchema(values: ['unwatched', 'watching', 'watched']),
  'genres': ArraySchema(_id),
  'yearMin': IntegerSchema(),
  'yearMax': IntegerSchema(),
  'ratingMin': NumberSchema(),
  'ratingMax': NumberSchema(),
  'addedAfter': _id,
  'addedBefore': _id,
});
const _content = ObjectSchema({
  'kind': StringSchema(values: ['condition', 'manual', 'original']),
  'filter': libraryFilterSchema,
  'workIds': ArraySchema(_id),
  'sourceId': _id,
  'serverId': _id,
  'parentId': _id,
}, required: [
  'kind'
]);

final class LibraryCapability implements Capability {
  LibraryCapability(LibraryDataService service)
      : actions = [
          for (final op in [
            'sources',
            'page',
            'items',
            'put',
            'configure',
            'move',
            'remove',
            'restore'
          ])
            _Action(service, op)
        ];
  @override
  final List<Action> actions;
}

JsonMap libraryItemJson(UiLibraryItem item) => switch (item) {
      UiWorkItem() => {'kind': 'work', 'work': workJson(item.work)},
      UiFolderItem() => {
          'kind': 'folder',
          'categoryId': item.categoryId,
          'title': item.title,
          'count': item.count,
          'posters': item.posters
        },
    };

final class _Json implements JsonEncodable {
  const _Json(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _Action extends Action<_Json, _Json> {
  const _Action(this.service, this.op);
  final LibraryDataService service;
  final String op;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'ui.library.$op',
      title: '片库 · $op',
      description: switch (op) {
        'put' =>
          'Atomically replace categories in entries. Globally unique categoryId; replacement retains order. content kind=condition uses local filter (OR within arrays, AND across dimensions); manual uses ordered workIds; original references sourceId/parentId. Server works require accepted identity for conditions. Optional coverWorkIds (up to 3) and sort. Shows arrangement, retains origin/activity. Classification is requested by the user.',
        'configure' =>
          'Batch source form shelves/cards and original true/false; switching preserves arrangements.',
        'move' =>
          'Batch categoryId/index (zero-based) moves among visible categories. Original order is persisted only in this device\'s NipaPlay; server/share order never changes.',
        'remove' =>
          'Batch categoryId: arranged categories are removed from the arrangement; original categories are only hidden in this device\'s NipaPlay. Never deletes or changes server/share content or media/identities. Hidden IDs appear in page.hiddenCategories and library.arrangements.hiddenOriginal; restore them with ui.library.restore.',
        'restore' =>
          'Batch categoryId from page.hiddenCategories or library.arrangements.hiddenOriginal. Unhides original categories in this device\'s NipaPlay, preserving their order and server/share content. Does not recreate removed arranged categories.',
        'sources' =>
          'Local merged catalogue first, then configured SMB, WebDAV, Jellyfin and Emby.',
        'page' =>
          'Read categories, hiddenCategories for ui.library.restore, cached local covers and bounded previews. Offline sources return last successful observations (empty if never read); their works are not playable.',
        _ =>
          'Category page with total, offset, limit 1..500 and optional advertised sort. Original servers use server pagination; conditions query local X47 cache.'
      },
      effect: const ['sources', 'page', 'items'].contains(op)
          ? Effect.read
          : Effect.write,
      input: switch (op) {
        'sources' => const ObjectSchema({}),
        'page' => const ObjectSchema({'sourceId': _id}, required: ['sourceId']),
        'items' => const ObjectSchema({
            'categoryId': _id,
            'offset': IntegerSchema(minimum: 0),
            'limit': IntegerSchema(minimum: 1, maximum: 500),
            'sort': _id
          }, required: [
            'categoryId'
          ]),
        _ => ObjectSchema({
            'entries': ArraySchema(switch (op) {
              'put' => const ObjectSchema({
                  'sourceId': _id,
                  'categoryId': _id,
                  'title': _id,
                  'content': _content,
                  'coverWorkIds': ArraySchema(_id),
                  'sort': _id
                }, required: [
                  'sourceId',
                  'categoryId',
                  'title',
                  'content'
                ]),
              'configure' => const ObjectSchema({
                  'sourceId': _id,
                  'form': StringSchema(values: ['shelves', 'cards']),
                  'original': BooleanSchema()
                }, required: [
                  'sourceId'
                ]),
              'move' => const ObjectSchema(
                  {'categoryId': _id, 'index': IntegerSchema(minimum: 0)},
                  required: ['categoryId', 'index']),
              _ => const ObjectSchema({'categoryId': _id},
                  required: ['categoryId'])
            })
          }, required: [
            'entries'
          ])
      },
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final i = input.json;
    if (op == 'sources')
      return Completed(_Json({
        'sources': [
          for (final s in await service.sources())
            {
              'sourceId': s.sourceId,
              'name': s.name,
              'kind': s.kind.name,
              'online': s.online
            }
        ]
      }));
    if (op == 'items') {
      final slice = await service.items(i['categoryId'] as String,
          offset: i['offset'] as int? ?? 0,
          limit: i['limit'] as int? ?? 60,
          sort: i['sort'] as String?);
      return Completed(_Json({
        'items': slice.items.map(libraryItemJson).toList(),
        'total': slice.total
      }));
    }
    if (op == 'page') {
      final page = await service.page(i['sourceId'] as String);
      return Completed(_Json({
        'form': page.form.name,
        'arranged': page.arranged,
        'hasArrangement': page.hasArrangement,
        'hiddenCategories': [
          for (final c in page.hiddenCategories)
            {'categoryId': c.categoryId, 'title': c.title}
        ],
        'categories': [
          for (final c in page.categories)
            {
              'categoryId': c.categoryId,
              'title': c.title,
              'count': c.count,
              'posters': c.posters,
              'backdrop': c.backdrop,
              'tint': c.tint,
              'preview': c.preview.map(libraryItemJson).toList(),
              'sorts': [
                for (final s in c.sorts) {'id': s.id, 'label': s.label}
              ]
            }
        ]
      }));
    }
    if ((i['entries'] as List).isEmpty)
      throw const Failure(FailureCode.invalidInput, 'Supply nonempty entries.');
    return Completed(_Json(await service.mutate(
        op,
        (i['entries'] as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList(),
        invocation)));
  }
}
