import 'dart:convert';
import 'dart:io';
import 'package:nipaplay/utils/subtitle_file_utils.dart';

void main(List<String> arguments) {
  final cases = (jsonDecode(File(arguments.single).readAsStringSync()) as List).cast<List>();
  print(jsonEncode([
    for (final item in cases) {
      'matches': subtitleMatchesVideo(item[0] as String, item[1] as String),
      'score': computeLocalSubtitleMatchScore(videoName: item[0] as String,
          subtitleName: item[1] as String, extension: '.ass',
          videoNumbers: ['01'], episodeNumber: '01'),
    }
  ]));
}
