import 'dart:io';
import '../media/media_service.dart';
import 'facts.dart';
import 'library_io.dart';
SubtitleFacts createSubtitleFacts(MediaService media, Directory root) => SubtitleLibrary(media, root);
