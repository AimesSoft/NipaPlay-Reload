import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/media/filename_parser.dart';

void main() {
  const parser = RuleFilenameParser();
  test('release filenames keep SxxEyy ahead of resolution and codecs', () {
    for (var episode = 1; episode <= 48; episode++) {
      final padded = episode.toString().padLeft(2, '0');
      final name =
          "长安十二时辰.The.Longest.Day.In.Chang'an.2019.S01E$padded.2160p.IQ.WEB-DL.HEVC.AAC-ZmWeb.mp4";
      final signals = parser.parse(
          '长安十二时辰/长安十二时辰.The.Longest.Day.In.Chang\'an.2019.S01.2160p.IQ.WEB-DL.HEVC.AAC-ZmWeb/$name');
      expect(signals.season, 1);
      expect(signals.number, padded);
      expect(signals.endNumber, isNull);
      expect(signals.year, 2019);
      expect(signals.technical, ['2160p', 'WEB-DL', 'HEVC', 'AAC']);
    }
    for (final suffix in [
      '1080p',
      '2160p',
      '1080i',
      '4K',
      'x265',
      'HEVC',
      '2160.HEVC'
    ]) {
      expect(parser.parse('Show.S02E03.$suffix.mkv').number, '03',
          reason: suffix);
    }
    final priority = parser.parse('[Group] Show - 99 S02E03.1080p.mkv');
    expect(priority.number, '03');
    expect(priority.episodeType, 'regular');
  });

  test(
      'animation groups and explicit fractional episodes stay distinct from technical tags',
      () {
    final anime = parser.parse('[Group] Title - 01 [1080p][HEVC][AAC].mkv');
    expect(anime.title, 'Title');
    expect(anime.number, '01');
    expect(anime.releaseGroup, 'Group');
    expect(parser.parse('[Group] Title - 01.1080p.mkv').number, '01');
    expect(parser.parse('Title E12.5.mkv').number, '12.5');
    expect(parser.parse('Title S01E12.5.2160p.mkv').number, '12.5');
    expect(parser.parse('Title S01E12.5p.mkv').number, '12');
    expect(parser.parse('Title S01E01-E02.2160p.mkv').endNumber, '02');
    expect(parser.parse('Title S01E1080p.mkv').number, isNull);
    expect(parser.parse('Title - 1080p.mkv').number, isNull);
    expect(parser.parse('Title 2160p HEVC x265.mkv').number, isNull);
  });
}
