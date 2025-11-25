import 'dart:async';
import 'package:smb_connect/smb_connect.dart';
import 'package:smb_connect/src/connect/smb_transport.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';
import 'package:smb_connect/src/smb/file_entry.dart';

abstract class SmbFilesEnumerator {
  final SmbTree tree;
  final SmbTransport transport;
  final SmbFile folder;
  final String wildcard;
  final int searchAttributes;

  SmbFilesEnumerator(
    this.tree,
    this.transport,
    this.folder,
    this.wildcard,
    this.searchAttributes,
  );

  Future<List<FileEntry>?> next();

  bool canNext();

  Future<void> close();
}
