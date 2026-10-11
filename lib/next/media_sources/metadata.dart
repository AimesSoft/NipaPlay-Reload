import 'package:nipa_harness/nipa_harness.dart';

const catalogMetadataFields =
    'ParentId,SeriesName,SeriesId,SeasonId,SeasonName,Path,MediaSources,'
    'MediaStreams,ProviderIds,Overview,OriginalTitle,ProductionYear,'
    'PremiereDate,DateCreated,DateLastMediaAdded,Genres,Studios,People,'
    'CommunityRating,OfficialRating,Tags';

const _itemFields = {
  'Id',
  'Name',
  'Type',
  'IsFolder',
  'ParentId',
  'SeriesId',
  'SeriesName',
  'SeasonId',
  'SeasonName',
  'IndexNumber',
  'IndexNumberEnd',
  'ParentIndexNumber',
  'ProductionYear',
  'OriginalTitle',
  'Overview',
  'Path',
  'Container',
  'Size',
  'RunTimeTicks',
  'ProviderIds',
  'PremiereDate',
  'DateCreated',
  'DateLastMediaAdded',
  'Genres',
  'Studios',
  'People',
  'CommunityRating',
  'OfficialRating',
  'Tags',
  'ImageTags',
  'UserData',
};

// Playback URLs and required headers are transport credentials, not metadata.
const _mediaSourceFields = {
  'Id',
  'ItemId',
  'Name',
  'Type',
  'Protocol',
  'Path',
  'Container',
  'Size',
  'RunTimeTicks',
  'Bitrate',
  'VideoType',
  'Video3DFormat',
  'IsRemote',
  'DefaultAudioStreamIndex',
  'DefaultSubtitleStreamIndex',
  'MediaAttachments',
};

JsonMap serverMetadata(Map<String, dynamic> item) => {
      for (final field in _itemFields)
        if (item.containsKey(field)) field: item[field],
      if (item.containsKey('MediaStreams'))
        'MediaStreams': _streams(item['MediaStreams']),
      if (item.containsKey('MediaSources'))
        'MediaSources': item['MediaSources'] == null
            ? null
            : [
                for (final source in item['MediaSources'] as List)
                  {
                    for (final field in _mediaSourceFields)
                      if ((source as Map).containsKey(field))
                        field: source[field],
                    if ((source as Map).containsKey('MediaStreams'))
                      'MediaStreams': _streams(source['MediaStreams']),
                  }
              ],
    };

Object? _streams(Object? streams) => streams == null
    ? null
    : [
        for (final stream in streams as List)
          {
            for (final entry in (stream as Map).entries)
              if (!{'DeliveryUrl', 'ExternalUrl'}.contains(entry.key))
                entry.key as String: entry.value,
          }
      ];

JsonMap sourceProvenance(JsonMap source, String itemId, String observedAt) => {
      'sourceId': source['sourceId'],
      'type': source['type'],
      'name': source['name'],
      'url': source['url'],
      'itemId': itemId,
      'observedAt': observedAt,
    };
