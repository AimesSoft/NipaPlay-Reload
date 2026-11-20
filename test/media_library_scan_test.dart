import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/media_library_scan.dart';
import 'package:path/path.dart' as p;

typedef Entry = ({String path, bool directory});

Entry dir(String path) => (path: path, directory: true);
Entry file(String path) => (path: path, directory: false);

void main() {
  test('排除确认的原盘结构，不进入菜单或证书目录', () async {
    final tree = <String, List<Entry>>{
      '/': [dir('/Disc'), dir('/Other'), dir('/NotADisc')],
      '/Disc': [
        dir('/Disc/Menu'),
        dir('/Disc/bDmV'),
        dir('/Disc/CERTIFICATE'),
        dir('/Disc/Extras'),
        file('/Disc/movie.mkv'),
      ],
      '/Disc/bDmV': [
        file('/Disc/bDmV/MovieObject.BDMV'),
        dir('/Disc/bDmV/STREAM')
      ],
      '/Disc/bDmV/STREAM': [file('/Disc/bDmV/STREAM/clip.mkv')],
      '/Disc/Menu': [file('/Disc/Menu/loop.mkv')],
      '/Disc/CERTIFICATE': [file('/Disc/CERTIFICATE/extra.mp4')],
      '/Disc/Extras': [dir('/Disc/Extras/menu')],
      '/Disc/Extras/menu': [file('/Disc/Extras/menu/other.mp4')],
      '/Other': [
        dir('/Other/menu'),
        dir('/Other/BDMV'),
        dir('/Other/CERTIFICATE')
      ],
      '/Other/menu': [file('/Other/menu/recipe.mp4')],
      '/Other/BDMV': [
        dir('/Other/BDMV/index.bdmv'),
        file('/Other/BDMV/extra.mkv')
      ],
      '/Other/BDMV/index.bdmv': [],
      '/Other/CERTIFICATE': [file('/Other/CERTIFICATE/award.mkv')],
      '/NotADisc': [file('/NotADisc/BDMV'), dir('/NotADisc/menu')],
      '/NotADisc/menu': [file('/NotADisc/menu/video.mp4')],
    };
    final visits = <String>[];

    Future<List<Entry>> collect(String root) =>
        collectMediaLibraryVideos<Entry>(
          root,
          listDirectory: (path) async {
            visits.add(path);
            return tree[path]!;
          },
          nameOf: (entry) => p.posix.basename(entry.path),
          pathOf: (entry) => entry.path,
          isDirectory: (entry) => entry.directory,
          isVideoFile: (name) => name.endsWith('.mkv') || name.endsWith('.mp4'),
          onListError: (error) => fail('$error'),
        );

    expect(
        (await collect('/')).map((entry) => entry.path),
        unorderedEquals([
          '/Disc/movie.mkv',
          '/Disc/Extras/menu/other.mp4',
          '/Other/menu/recipe.mp4',
          '/Other/BDMV/extra.mkv',
          '/Other/CERTIFICATE/award.mkv',
          '/NotADisc/menu/video.mp4',
        ]));
    expect(visits, isNot(contains('/Disc/Menu')));
    expect(visits, isNot(contains('/Disc/CERTIFICATE')));
    expect(visits, isNot(contains('/Disc/bDmV/STREAM')));
    expect(visits.where((path) => path == '/Other/BDMV'), hasLength(1));
    expect(await collect('/Disc/bDmV'), isEmpty);
  });
}
