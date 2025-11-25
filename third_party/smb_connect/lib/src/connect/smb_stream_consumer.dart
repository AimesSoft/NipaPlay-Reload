import 'dart:async';

import 'package:smb_connect/src/connect/smb_file.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';

abstract class SmbStreamConsumer implements StreamConsumer<List<int>> {
  final SmbFile file;
  final SmbTree tree;
  int position;
  static const int blockSize = 64936;

  SmbStreamConsumer(this.file, this.tree, this.position);

  @override
  Future addStream(Stream<List<int>> stream) async {
    Completer completer = Completer();
    late StreamSubscription subscription;
    subscription = stream.listen(
      (event) async {
        subscription.pause();
        await writeToFile(event);
        subscription.resume();
      },
      onDone: completer.complete,
      onError: completer.completeError,
    );

    return await completer.future;
  }

  @override
  Future close();
  // async {
  //   await smbCloseFile(file, tree, fileId, fid);
  // }

  Future writeToFile(List<int> b);
}
