import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/data/work_manage.dart';
import 'package:nipaplay/next/ui/detail/metadata_panel.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

void main() {
  testWidgets(
      'details show separate scores, credits, characters and actual file facts',
      (tester) async {
    const work = UiWork(workId: 'work', title: '样本');
    const managed =
        UiManagedWork(work: work, kind: UiWorkKind.matched, metadata: {
      'sources': [
        {
          'provider': 'tmdb',
          'objectType': 'tv',
          'externalId': '1',
          'fields': {
            'rating': {'value': 8.2, 'max': 10, 'count': 100},
            'credits': {
              'cast': [
                {'name': '配音演员', 'role': '主角'}
              ]
            },
            'studios': ['制作公司'],
            'status': 'Returning Series',
          }
        },
        {
          'provider': 'bangumi',
          'objectType': 'subject',
          'externalId': '2',
          'fields': {
            'rating': {'value': 7.6, 'max': 10},
            'staff': [
              {'name': '监督名字', 'relation': '监督'}
            ],
            'characters': [
              {
                'name': '角色名字',
                'relation': '主角',
                'actors': [
                  {'name': '声优名字'}
                ]
              }
            ],
            'infobox': [
              {'key': '原作', 'value': '原作者'}
            ],
          }
        },
      ]
    }, episodes: const [
      UiManagedEpisode(number: '1', files: [
        UiFile(path: '/sample/video.mkv', size: 1000000, technical: {
          'container': 'matroska',
          'bitrate': 6000000,
          'video': [
            {
              'codec': 'hevc',
              'width': 1920,
              'height': 1080,
              'fps': 23.976,
              'pixelFormat': 'yuv420p10le'
            }
          ],
          'audio': [
            {
              'codec': 'aac',
              'channels': 2,
              'sampleRate': 48000,
              'language': 'ja'
            }
          ],
        })
      ])
    ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: WorkMetadataPanel(work: work, manage: _Manage(managed)),
    ))));
    await tester.pump();
    expect(find.textContaining('8.2 / 10'), findsOneWidget);
    expect(find.textContaining('7.6 / 10'), findsOneWidget);
    expect(find.textContaining('配音演员'), findsOneWidget);
    expect(find.textContaining('监督名字'), findsOneWidget);
    expect(find.textContaining('声优名字'), findsOneWidget);
    expect(find.textContaining('原作者'), findsOneWidget);
    expect(find.text('video.mkv'), findsOneWidget);
    expect(find.textContaining('1920 × 1080'), findsOneWidget);
    expect(find.textContaining('6.00 Mb/s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Manage implements NextWorkManage {
  _Manage(this.value);
  final UiManagedWork value;
  @override
  Future<UiManagedWork> work(UiWork work) async => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
