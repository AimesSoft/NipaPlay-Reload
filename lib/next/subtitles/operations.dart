import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'facts.dart';

abstract interface class SubtitleOperations implements SubtitleFacts {
  Database get db;
  Future<JsonMap> facts(String fileId);
  Future<JsonMap> importSubtitle(JsonMap input, Invocation invocation);
  Future<void> select(String fileId, String? trackId);
  Directory get root;
  Future<JsonMap> mutateFacts(String fileId, String operation, JsonMap input, Invocation invocation);
}
