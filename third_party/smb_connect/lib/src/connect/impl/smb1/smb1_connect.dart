import 'dart:io';
import 'dart:typed_data';

import 'package:smb_connect/smb_connect.dart';
import 'package:smb_connect/src/connect/dcerpc.dart';
import 'package:smb_connect/src/connect/fscc/file_information.dart';
import 'package:smb_connect/src/connect/fscc/file_standard_info.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_blank_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_close.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_create_directory.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_delete.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_delete_directory.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_negotiate_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_nt_create_and_x.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_nt_create_and_x_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_open_and_x.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_open_and_x_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_query_information.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_query_information_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_rename.dart';
import 'package:smb_connect/src/connect/impl/smb1/dcerpc.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb1_files_enumerator.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb1_random_access_file_controller.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb1_session.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb1_stream_consumer.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb1_tree.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans2/trans2_query_path_information.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans2/trans2_query_path_information_response.dart';
import 'package:smb_connect/src/connect/smb_file_stream.dart';
import 'package:smb_connect/src/connect/smb_random_access_file.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';
import 'package:smb_connect/src/dcerpc/msrpc/msrpc_share_enum.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/smb/request_param.dart';
import 'package:smb_connect/src/smb_constants.dart';

class Smb1Connect extends SmbConnect {
  Smb1Connect(super.configuration, super.transport);

  @override
  Smb1Session initSession() {
    var session = Smb1Session(transport.config, transport);
    return session;
  }

  @override
  SmbTree initTree(String share) {
    var session = initSession();
    var tree = Smb1Tree(transport, session, share, null);
    return tree;
  }

  bool isCapabilitiyNtSMBS() =>
      transport
          .getNegotiatedResponse()
          ?.haveCapabilitiy(SmbConstants.CAP_NT_SMBS) ==
      true;

  @override
  Future<SmbFile> file(String path) async {
    var infoLevel = FileInformation.FILE_STANDARD_INFO;
    String share = SmbConnect.getShare(path);
    var uncPath = SmbConnect.getUncPath(path);

    var tree = await shareTree(share);
    if (isCapabilitiyNtSMBS()) {
      //
      // Trans2 Query Path Information Request / Response
      //
      var response =
          Trans2QueryPathInformationResponse(configuration, infoLevel);
      var request =
          Trans2QueryPathInformation(configuration, uncPath, infoLevel);
      tree.prepare(request);

      await transport.sendrecvComTransaction(request, response);
      final info = response.getInfo() as FileStandardInfo?;

      if (info == null ||
          SmbConnect.responseStatusNotFound(response.errorCode)) {
        return SmbFile.notExists(path, uncPath, share);
      } else {
        return SmbFile.info(path, uncPath, share, info);
      }
    } else {
      //
      // Query Information Request / Response
      //
      var response = SmbComQueryInformationResponse(
          configuration, getServerTimeZoneOffset());

      var request = SmbComQueryInformation(configuration, path);
      tree.prepare(request);
      response = await transport.sendrecv(request, response: response);

      return SmbFile.info(path, uncPath, share, response);
    }
  }

  @override
  Future<SmbFile> createFile(String path) async {
    String share = SmbConnect.getShare(path);
    var uncPath = SmbConnect.getUncPath(path);

    int flags =
        SmbConstants.O_RDWR | SmbConstants.O_CREAT | SmbConstants.O_EXCL;
    int access = SmbConstants.O_RDWR;
    int sharing = SmbConstants.FILE_NO_SHARE;
    int attrs = SmbConstants.ATTR_NORMAL;

    final res = await _openFile(path, share, uncPath,
        openFlags: flags, access: access, sharing: sharing, attrs: attrs);
    await _closeFile(share, path, res.$1);
    return res.$2;
  }

  @override
  Future<SmbFile> createFolder(String path) async {
    String share = SmbConnect.getShare(path);
    var uncPath = SmbConnect.getUncPath(path);
    SmbTree tree = await shareTree(share);

    var req = SmbComCreateDirectory(configuration, uncPath);
    var resp = SmbComBlankResponse(configuration);

    tree.prepare(req);
    await tree.transport.sendrecv(req, response: resp);

    if (resp.errorCode != 0) {
      throw "Can't create folder $path: ${SmbException.getMessageByCode(resp.errorCode)}";
    }
    return file(path);
  }

  @override
  Future<SmbFile> delete(SmbFile file) async {
    if (!file.canWrite()) {
      throw "Access denied";
      // return false;
    }
    var tree = await shareTree(file.share);
    ServerMessageBlock req;
    final resp = SmbComBlankResponse(configuration);
    if (file.isDirectory()) {
      var childs = await listFiles(file);
      for (var childFile in childs) {
        await delete(childFile);
      }
      req = SmbComDeleteDirectory(configuration, path: file.uncPath);
    } else {
      req = SmbComDelete(configuration, path: file.uncPath);
    }
    tree.prepare(req);

    await transport.sendrecv(req, response: resp);

    if (resp.errorCode != 0) {
      throw "Can't delete ${file.path}: ${SmbException.getMessageByCode(resp.errorCode)}";
    }
    return SmbFile.notExists(file.path, file.uncPath, file.share);
    // throw SmbException.getMessageByCode(req.status);
  }

  // @override
  // Future<SmbFile> copyTo(SmbFile srcFile, String dstPath,
  //     {bool replace = false}) {
  // }

  @override
  Future<SmbFile> rename(SmbFile srcFile, String dstPath,
      {bool replace = false}) async {
    String dstShare = SmbConnect.getShare(dstPath);
    if (srcFile.share != dstShare) {
      throw "Can't rename between different ${srcFile.share} != $dstShare";
    }
    var dstUncPath = SmbConnect.getUncPath(dstPath);

    final req = SmbComRename(configuration, srcFile.uncPath, dstUncPath);
    final resp = SmbComBlankResponse(configuration);
    final tree = await shareTree(srcFile.share);

    tree.prepare(req);

    await transport.sendrecv(req, response: resp);
    if (resp.errorCode != 0) {
      throw "Can't rename file ${srcFile.path} => $dstPath";
    }

    return file(dstPath);
  }

  @override
  Future<List<SmbFile>> listShares() async {
    String share = SmbConnect.IPC_SHARE;
    String path = SmbConnect.IPC_PATH;
    var tree = await shareTree(share);
    String uncPath = SmbConnect.getUncPath(path);

    var shareFile = await _openFile(path, share, uncPath,
        openFlags: DcerpcBase.pipeFlags,
        access: DcerpcBase.pipeAccess,
        sharing: SmbConstants.DEFAULT_SHARING,
        attrs: SmbConstants.ATTR_NORMAL);

    DcerpcSmb1 dcerpc = DcerpcSmb1(transport, tree, shareFile.$1);

    final msrpc = MsrpcShareEnum(host);

    final res = await dcerpc.sendrecv(msrpc);
    if (!res) {
      return [];
    }
    await _closeFile(share, path, shareFile.$1);

    SmbFile folder = SmbFile("/", uncPath, share, 0, 0, 0, 0, 0, true);

    return mapFileEntries(folder, msrpc.getEntries());
  }

  @override
  Future<List<SmbFile>> listFiles(SmbFile folder,
      [String wildcard = "*"]) async {
    var tree = await shareTree(folder.share);
    int searchAttributes = SmbConstants.ATTR_DIRECTORY |
        SmbConstants.ATTR_HIDDEN |
        SmbConstants.ATTR_SYSTEM;
    Smb1FilesEnumerator enumerator = Smb1FilesEnumerator(
        tree, transport, folder, wildcard, searchAttributes);

    final List<SmbFile> res = [];

    while (enumerator.canNext()) {
      var items = await enumerator.next();
      if (items != null) {
        var nextFiles = mapFileEntries(folder, items);
        res.addAll(nextFiles);
      }
    }
    await enumerator.close();
    return res;
  }

  Future<(int, SmbFile)> _openFile(
    String path,
    String share,
    String uncPath, {
    required int openFlags,
    required int access,
    required int sharing,
    required int attrs,
    int options = 0,
  }) async {
    SmbTree tree = await shareTree(share);

    int fid;
    SmbFile file;
    if (isCapabilitiyNtSMBS()) {
      SmbComNTCreateAndXResponse resp =
          SmbComNTCreateAndXResponse(configuration);
      SmbComNTCreateAndX req = SmbComNTCreateAndX(configuration, uncPath,
          openFlags, access, sharing, attrs, options, null);

      tree.prepare(req);
      await tree.transport.sendrecv(req, response: resp);

      if (resp.errorCode != 0) {
        throw "Can't open file $path";
      }

      fid = resp.fid;
      file = SmbFile.info(path, uncPath, share, resp);
    } else {
      SmbComOpenAndXResponse resp = SmbComOpenAndXResponse(configuration);
      var req = SmbComOpenAndX(
          configuration, uncPath, access, sharing, openFlags, attrs, null);
      tree.prepare(req);
      await tree.transport.sendrecv(req, response: resp);

      if (resp.errorCode != 0) {
        throw "Can't open file $path";
      }

      fid = resp.getFid();
      file = SmbFile.info(path, uncPath, share, resp);
    }
    return (fid, file);
  }

  Future _closeFile(String share, String path, int fid,
      [int lastWriteTime = 0]) async {
    SmbTree tree = await shareTree(share);
    final req = SmbComClose(transport.config, fid, lastWriteTime);
    final resp = SmbComBlankResponse(transport.config);
    tree.prepare(req);
    await tree.transport
        .sendrecv(req, response: resp, params: {RequestParam.NO_RETRY});

    if (resp.errorCode != 0) {
      throw "Can't close file $path";
    }
  }

  @override
  Future<Stream<Uint8List>> openRead(SmbFile file,
      [int? start, int? end]) async {
    int access = SmbConstants.O_RDONLY;
    int openFlags = 0;
    int sharing = SmbConstants.DEFAULT_SHARING;
    int attrs = SmbConstants.ATTR_NORMAL;

    SmbTree tree = await shareTree(file.share);

    final res = await _openFile(file.path, file.share, file.uncPath,
        openFlags: openFlags, access: access, sharing: sharing, attrs: attrs);

    start = start ?? 0;
    end = end ?? res.$2.size;
    int length = end - start;
    return smbOpenRead(file, tree, null, res.$1, start, length);
  }

  @override
  Future<IOSink> openWrite(SmbFile file, {bool append = false}) async {
    if (!file.isExists) {
      file = await create(file);
    }

    final res = await _openFile(file.path, file.share, file.uncPath,
        openFlags: 0,
        access: SmbConstants.FILE_WRITE_DATA,
        sharing: SmbConstants.DEFAULT_SHARING,
        attrs: SmbConstants.ATTR_NORMAL);

    var tree = await shareTree(res.$2.share);
    int position = append ? res.$2.size : 0;
    var consumer = isCapabilitiyNtSMBS()
        ? Smb1ComAndXStreamConsumer(file, tree, res.$1, position)
        : Smb1ComStreamConsumer(file, tree, res.$1, position);
    return IOSink(consumer);
  }

  int getServerTimeZoneOffset() {
    var neroResp = transport.getNegotiatedResponse();
    if (neroResp is SmbComNegotiateResponse) {
      return neroResp.getServerData().serverTimeZone * 1000 * 60;
    }
    return 0;
  }

  @override
  Future<RandomAccessFile> open(SmbFile file,
      {FileMode mode = FileMode.read}) async {
    var tree = await shareTree(file.share);
    Smb1RandomAccessFileController controller = Smb1RandomAccessFileController(
        file, tree, mode, _openFile, isCapabilitiyNtSMBS());
    return SmbRandomAccessFile(file, controller);
  }
}
