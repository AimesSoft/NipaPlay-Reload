import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/media_filename_parser.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import 'package:nipaplay/utils/webdav_file_sorter.dart';

void main() {
  group('media metadata utilities', () {
    test('extracts searchable anime titles', () {
      expect(
        MediaFilenameParser.extractAnimeTitleKeyword(
          '[Group] My.Anime.S02E03.1080p.mkv',
        ),
        'My Anime 1080p',
      );
      expect(
        MediaFilenameParser.extractAnimeTitleKeyword('【字幕组】【压制】番名 - 01.mkv'),
        '番名',
      );
    });

    test('scores matching subtitles and filters noise tokens', () {
      expect(
        extractSubtitleMatchTokens('Anime.02.[1080p].CHS.ass'),
        {'anime', '02'},
      );
      expect(
        computeLocalSubtitleMatchScore(
          videoName: 'Anime 02',
          subtitleName: 'Anime 02.chs',
          extension: '.ass',
          videoNumbers: const ['02'],
          episodeNumber: '02',
        ),
        greaterThanOrEqualTo(minReliableLocalSubtitleMatchScore),
      );
    });

    test('compares numeric name chunks naturally', () {
      expect(WebDAVFileSorter.naturalCompare('Episode 2', 'Episode 10'), -1);
      expect(WebDAVFileSorter.naturalCompare('Episode 02', 'Episode 2'), 1);
    });
  });
}
