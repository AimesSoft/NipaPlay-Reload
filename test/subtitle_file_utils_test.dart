import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';

void main() {
  test('normalizeExternalSubtitleTrackUri converts local file path to URI', () {
    final path = Platform.isWindows
        ? r'C:\Anime\Frieren 01 中文字幕.ass'
        : '/tmp/Frieren 01 中文字幕.ass';

    expect(
      normalizeExternalSubtitleTrackUri(path),
      equals(File(path).absolute.uri.toString()),
    );
  });

  test('normalizeExternalSubtitleTrackUri keeps remote URI unchanged', () {
    const path = 'https://example.com/subtitles/frieren-01.ass';

    expect(normalizeExternalSubtitleTrackUri(path), equals(path));
  });

  test('pickLikelyEpisodeNumber prefers two-digit episode numbers', () {
    expect(
      pickLikelyEpisodeNumber(<String>['2024', '01', '1080']),
      equals('01'),
    );
  });

  test(
    'computeLocalSubtitleMatchScore prefers matching subtitle candidate',
    () {
      final matchingScore = computeLocalSubtitleMatchScore(
        videoName: '[SubsPlease] Frieren - 01 [1080p]',
        subtitleName: 'Frieren - 01 简中.ass',
        extension: '.ass',
        videoNumbers: <String>['01', '1080'],
        episodeNumber: '01',
      );

      final wrongEpisodeScore = computeLocalSubtitleMatchScore(
        videoName: '[SubsPlease] Frieren - 01 [1080p]',
        subtitleName: 'Frieren - 02 简中.ass',
        extension: '.ass',
        videoNumbers: <String>['01', '1080'],
        episodeNumber: '01',
      );

      final unrelatedScore = computeLocalSubtitleMatchScore(
        videoName: '[SubsPlease] Frieren - 01 [1080p]',
        subtitleName: 'Apothecary Diaries - 01 简中.ass',
        extension: '.ass',
        videoNumbers: <String>['01', '1080'],
        episodeNumber: '01',
      );

      expect(matchingScore, greaterThan(wrongEpisodeScore));
      expect(matchingScore, greaterThan(unrelatedScore));
    },
  );
}
