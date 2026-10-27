import 'dart:convert';
import 'dart:io';
import 'package:nipaplay/next/harness_repository.dart';
Future<void> main(List<String> args) async {
  stdout.writeln(jsonEncode(await updateHarnessRepository(Directory(args[0]), Directory(args[1]))));
}
