import 'dart:async';

import 'package:smb_connect/src/connect/smb_files_enumerator.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_blank_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_find_close2.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans2/trans2_find_first2.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans2/trans2_find_first2_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans2/trans2_find_next2.dart';
import 'package:smb_connect/src/smb/file_entry.dart';

class Smb1FilesEnumerator extends SmbFilesEnumerator {
  final Trans2FindFirst2Response _response;
  Trans2FindNext2? nextRequest;
  int _num = 0;

  Smb1FilesEnumerator(
    super.tree,
    super.transport,
    super.folder,
    super.wildcard,
    super.searchAttributes,
  ) : _response = Trans2FindFirst2Response(transport.config);

  Future<Trans2FindFirst2Response> _first() async {
    _response.reset();
    var request = Trans2FindFirst2(
        transport.config,
        folder.uncPath,
        wildcard,
        searchAttributes,
        transport.config.listCount,
        transport.config.listSize - ITEMS_OVERHEAD);
    tree.prepare(request);
    await transport.sendrecvComTransaction(request, _response);
    return _response;
  }

  Future<Trans2FindFirst2Response?> _more() async {
    var lastName = _response.getLastName();
    if (lastName == null) {
      return null;
    }
    var request = nextRequest ??
        Trans2FindNext2(
          transport.config,
          _response.getSid(),
          _response.getResumeKey(),
          lastName,
          transport.config.listCount,
          transport.config.listSize - ITEMS_OVERHEAD,
        );
    request.reset2(_response.getResumeKey(), _response.getLastName());
    nextRequest = request;
    _response.reset();
    _response.subCommand = SmbComTransaction.TRANS2_FIND_NEXT2;
    tree.prepare(request);
    await transport.sendrecvComTransaction(request, _response);
    return _response;
  }

  @override
  Future<List<FileEntry>?> next() async {
    var prevNum = _num;
    _num++;
    Trans2FindFirst2Response? resp;
    if (prevNum == 0) {
      resp = await _first();
    } else {
      resp = await _more();
    }
    if (resp == null) {
      return null;
    }

    var res = _response.results;
    if (res == null) {
      return null;
    }
    return res;
  }

  @override
  bool canNext() => _num == 0 || !_response.isEndOfSearch();

  @override
  Future<void> close() async {
    // print("Close enumerator");
    final req = SmbComFindClose2(transport.config, _response.getSid());
    final resp = SmbComBlankResponse(transport.config);
    tree.prepare(req);
    await transport.sendrecv(req, response: resp);
  }

  static const ITEMS_OVERHEAD = 80;
}
