import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/media_library_scan.dart';
import 'package:path/path.dart' as p;

typedef Entry = ({String path, bool directory});

Entry dir(String path) => (path: path, directory: true);
Entry file(String path) => (path: path, directory: false);

void main() {
  test('保留原盘视频，只跳过同级菜单和证书目录', () async {
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
      '/Disc/bDmV/STREAM': [file('/Disc/bDmV/STREAM/00001.m2ts')],
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
          isVideoFile: (name) =>
              ['.mkv', '.mp4', '.m2ts'].contains(p.posix.extension(name)),
          onListError: (error) => fail('$error'),
        );

    expect(
        (await collect('/')).map((entry) => entry.path),
        unorderedEquals([
          '/Disc/movie.mkv',
          '/Disc/bDmV/STREAM/00001.m2ts',
          '/Disc/Extras/menu/other.mp4',
          '/Other/menu/recipe.mp4',
          '/Other/BDMV/extra.mkv',
          '/Other/CERTIFICATE/award.mkv',
          '/NotADisc/menu/video.mp4',
        ]));
    expect(visits, isNot(contains('/Disc/Menu')));
    expect(visits, isNot(contains('/Disc/CERTIFICATE')));
    expect(visits.where((path) => path == '/Disc/bDmV'), hasLength(1));
    expect(visits.where((path) => path == '/Other/BDMV'), hasLength(1));
  });

  test('直接选择确认的 BDMV 时也扫描 STREAM', () async {
    const root = '/Disc/BDMV';
    const video = '$root/STREAM/00001.m2ts';
    final tree = {
      root: [file('$root/index.bdmv'), dir('$root/STREAM')],
      '$root/STREAM': [file(video)],
    };

    final videos = await collectMediaLibraryVideos<Entry>(
      root,
      listDirectory: (path) async => tree[path]!,
      nameOf: (entry) => p.posix.basename(entry.path),
      pathOf: (entry) => entry.path,
      isDirectory: (entry) => entry.directory,
      isVideoFile: (name) => name.endsWith('.m2ts'),
      onListError: (error) => fail('$error'),
    );

    expect(videos, [file(video)]);
  });
}
