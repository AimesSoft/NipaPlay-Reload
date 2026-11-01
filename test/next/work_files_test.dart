import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/ui/detail/file_facts.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/next/ui_data/work_details.dart';
import 'package:nipaplay/next/ui_data/work_files.dart';
import 'package:nipaplay/next/ui_data/work_more.dart';

import 'media_test_support.dart';

/// A work's page tells what its files are from what their scan read, and
/// which other works its sources relate it to. Nothing is guessed: a file
/// whose streams were never read says only its size.
const _technical = {
  'container': 'matroska,webm',
  'video': [
    {
      'codec': 'hevc',
      'width': 1920,
      'height': 1080,
      'pixelFormat': 'yuv420p10le',
      'colorSpace': 'bt709',
    }
  ],
  'audio': [
    {'codec': 'flac', 'channels': 2, 'language': 'jpn'},
  ],
};

UiFileFacts _facts(Map<String, Object?> probe,
        [List<Map<String, Object?>> tracks = const [], String? device]) =>
    UiFileFacts.fromJson({
      ...fileFactsOf(probe, tracks),
      if (device != null) 'device': device,
    });

void main() {
  group('what a file is', () {
    test('its streams, its subtitles in it and beside it', () {
      final facts = fileFactsOf({
        'size': 1500000000,
        'technical': _technical,
      }, [
        {
          'origin': 'embedded',
          'language': 'zh-Hans',
          'title': '简日双语',
          'format': 'ass'
        },
        // A file beside the video is named by its file name.
        {
          'origin': 'sidecar',
          'language': 'zh-Hant',
          'title': '[Group] Show - 01.cht.ass',
          'format': 'ass'
        },
        {'origin': 'sidecar', 'language': 'en', 'available': false},
      ]);
      expect(facts['known'], isTrue);
      expect((facts['video'] as Map)['width'], 1920);
      expect(facts['subtitles'], [
        {
          'language': 'zh-Hans',
          'title': '简日双语',
          'format': 'ass',
          'external': false
        },
        {'language': 'zh-Hant', 'format': 'ass', 'external': true},
      ]);
    });

    test('a file scanned before streams were kept knows its size only', () {
      final probe = {'size': 900, 'durationMs': 1440000};
      expect(lacksStreams(probe), isTrue);
      expect(lacksStreams({...probe, 'technical': _technical}), isFalse);
      final facts = fileFactsOf(probe, const []);
      expect(facts.containsKey('known'), isFalse);
      expect(facts['size'], 900);
    });
  });

  group('what the page says of them', () {
    test('a film: its marks and rows', () {
      final summary = fileSummary([
        _facts({
          'size': 18900000000,
          'technical': {
            'container': 'matroska,webm',
            'video': [
              {
                'codec': 'hevc',
                'width': 3840,
                'height': 2160,
                'pixelFormat': 'yuv420p10le',
                'colorSpace': 'bt2100PQ',
              }
            ],
            'audio': [
              {'codec': 'truehd', 'channels': 6, 'language': 'jpn'},
              {
                'codec': 'aac',
                'channels': 2,
                'language': 'jpn',
                'title': '评论音轨'
              },
            ],
          },
        }, [
          {'origin': 'embedded', 'language': 'zh-Hans', 'format': 'ass'},
          {
            'origin': 'embedded',
            'language': 'zh-Hans',
            'title': '[字幕组] 简日双语',
            'format': 'ass'
          },
          {'origin': 'sidecar', 'language': 'zh-Hant', 'format': 'srt'},
        ]),
      ]);
      expect(summary.badges, ['4K', 'HDR', '5.1']);
      expect({
        for (final r in summary.rows) r.label: r.value
      }, {
        '画质': '4K · HEVC 10-bit · HDR',
        '音轨': '日语 · TrueHD 5.1\n日语 · AAC 2.0 · 评论音轨',
        '字幕': '简体中文 ASS、简日双语 ASS（内嵌）\n繁体中文 SRT（外挂）',
        '文件': 'MKV · 17.6 GB',
      });
    });

    test('a series: what most files are, and how many are otherwise', () {
      final summary = fileSummary([
        for (var i = 0; i < 11; i++)
          _facts({'size': 1073741824, 'technical': _technical}),
        _facts({
          'size': 536870912,
          'technical': {
            ..._technical,
            'video': [
              {'codec': 'h264', 'width': 1280, 'height': 720}
            ],
          },
        }),
        // On the other device, never read: its size only.
        _facts({'size': 1073741824}, const [], 'Windows'),
      ]);
      expect(summary.badges, ['1080p']);
      final rows = {for (final r in summary.rows) r.label: r.value};
      expect(rows['画质'], '1080p · HEVC 10-bit（11 个文件）\n720p · H.264（1 个文件）');
      expect(rows['音轨'], '日语 · FLAC 2.0');
      expect(rows['字幕'], '无');
      expect(rows['文件'], '13 个文件 · MKV · 共 12.5 GB · 本机 12、Windows 1');
    });

    test('files nobody read say only what is known of them', () {
      final summary = fileSummary([
        _facts({'size': 2147483648}),
      ]);
      expect(summary.badges, isEmpty);
      expect(summary.rows, [(label: '文件', value: '2.0 GB')]);
      expect(fileSummary(const []).rows, isEmpty);
    });
  });

  group('the series a work is in', () {
    test('where its relatives are known, from its sources', () {
      final built = buildWorkMore({
        'fields': const {},
        'sources': [
          {
            'provider': 'bangumi',
            'objectType': 'subject',
            'externalId': '9717',
            'fields': const {'providerData': {}},
          },
          {
            'provider': 'tmdb',
            'objectType': 'movie',
            'externalId': '212162',
            'fields': {
              'providerData': {
                'belongs_to_collection': {'id': 1, 'name': '合集'}
              }
            },
          },
          {
            'provider': 'dandanplay',
            'objectType': 'anime',
            'externalId': '7000',
            'fields': {
              'providerData': {
                'relateds': [
                  {'animeId': 7001, 'animeTitle': '魔法少女小圆 剧场版 前篇'},
                  {'animeId': 7002},
                ]
              }
            },
          },
        ],
      });
      final ref = UiWorkMore.fromJson(built).related!;
      expect(ref.bangumi, '9717');
      expect(ref.tmdbCollection, '1');
      expect(ref.tmdbMovie, '212162');
      expect(ref.dandanplay.map((d) => (d.id, d.title)),
          [('7001', '魔法少女小圆 剧场版 前篇')]);
      // A work with none of these has none.
      expect(UiWorkMore.fromJson(buildWorkMore(const {})).related, isNull);
    });

    test('Bangumi says how each relates; books and music are not shown', () {
      final related = bangumiRelated([
        {
          'id': 9718,
          'type': 2,
          'name': '劇場版 魔法少女まどか☆マギカ [新編] 叛逆の物語',
          'name_cn': '魔法少女小圆 剧场版 新篇 叛逆的物语',
          'relation': '续集',
          'images': {'common': 'https://lain.bgm.tv/c.jpg'},
        },
        {'id': 1, 'type': 1, 'name': '原作漫画', 'relation': '原作'},
        {'id': 2, 'type': 3, 'name': 'OST', 'relation': '原声集'},
      ]);
      expect(related.single.$1.toJson(),
          ExternalRef('bangumi', 'subject', '9718').toJson());
      expect(related.single.$2.title, '魔法少女小圆 剧场版 新篇 叛逆的物语');
      expect(related.single.$2.role, '续集');
      expect(related.single.$2.poster, 'https://lain.bgm.tv/c.jpg');
      expect(related.single.$2.workId, 'found:bangumi:9718');
    });

    test('a TMDB collection: the other films, in the order they came out', () {
      final parts = tmdbCollectionParts({
        'parts': [
          {'id': 3, 'title': '叛逆的物语', 'release_date': '2013-10-26'},
          {'id': 1, 'title': '始まりの物語', 'release_date': '2012-10-06'},
          {'id': 2, 'title': '永遠の物語', 'release_date': '2012-10-13'},
        ]
      }, self: '3');
      expect([for (final (_, w) in parts) (w.title, w.year)],
          [('始まりの物語', 2012), ('永遠の物語', 2012)]);
    });
  });

  group('reading the streams of an older file', () {
    late MediaFixture f;
    setUp(() async {
      f = MediaFixture();
      await f.open();
    });
    tearDown(() => f.close());

    test('kept when the file is still what was scanned; its identity stays',
        () async {
      final id = await f.file('older.mkv');
      final file = await f.identities.entity(id);
      final probe = (file['attributes'] as JsonMap)['probe'] as JsonMap;
      expect(lacksStreams(probe), isTrue);

      // Changed since: nothing is kept.
      expect(
          await f.identities
              .addStreams(id, {...probe, 'size': 1, 'technical': _technical}),
          isFalse);
      expect(
          await f.identities
              .addStreams(id, {...probe, 'technical': _technical}),
          isTrue);
      final after = await f.identities.entity(id);
      final kept = (after['attributes'] as JsonMap)['probe'] as JsonMap;
      expect(kept['technical'], _technical);
      expect(kept['headMd5'], probe['headMd5']);
      expect(after['revision'], file['revision']);
    });
  });
}
