import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:smb_connect/src/connect/dcerpc.dart';
import 'package:smb_connect/src/connect/fscc/file_rename_information2.dart';
import 'package:smb_connect/src/connect/fscc/smb_basic_file_info.dart';
import 'package:smb_connect/src/connect/impl/smb2/create/smb2_close_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/create/smb2_close_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/create/smb2_create_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/create/smb2_create_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/dcerpc.dart';
import 'package:smb_connect/src/connect/impl/smb2/info/smb2_set_info_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_files_enumerator.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_random_access_file_controller.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_session.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_stream_consumer.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_tree.dart';
import 'package:smb_connect/src/connect/smb_connect.dart';
import 'package:smb_connect/src/connect/smb_file.dart';
import 'package:smb_connect/src/connect/smb_file_stream.dart';
import 'package:smb_connect/src/connect/smb_random_access_file.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';
import 'package:smb_connect/src/dcerpc/msrpc/msrpc_share_enum.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/smb/nt_status.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class Smb2Connect extends SmbConnect {
  Smb2Connect(super.configuration, super.transport);

  @override
  Smb2Session initSession() {
    var session = Smb2Session(transport.config, transport);
    return session;
  }

  @override
  SmbTree initTree(String share) {
    var session = initSession();
    var tree = Smb2Tree(transport, session, share, null);
    return tree;
  }

  Future<Smb2CreateResponse> openCloseRequest({
    required String path,
    required String uncPath,
    required String share,
    required int createDisposition,
    required int createOptions,
    required int fileAttributes,
    required int desiredAccess,
    required int shareAccess,
    ServerMessageBlock2? cmd,
  }) async {
    SmbTree tree = await shareTree(share);
    Smb2CreateRequest createReq = Smb2CreateRequest(configuration, uncPath);
    createReq.setCreateDisposition(createDisposition);
    createReq.setCreateOptions(createOptions);
    createReq.setFileAttributes(fileAttributes);
    createReq.setDesiredAccess(desiredAccess);
    createReq.setShareAccess(shareAccess);

    String fullPath = "\\$host\\$share$uncPath";
    createReq.setFullUNCPath(null, host, fullPath);

    Smb2CloseRequest closeReq =
        Smb2CloseRequest(configuration, fileName: uncPath);
    closeReq.setCloseFlags(Smb2CloseResponse.SMB2_CLOSE_FLAG_POSTQUERY_ATTRIB);
    if (cmd != null) {
      createReq.chain(cmd);
      cmd.chain(closeReq);
    } else {
      createReq.chain(closeReq);
    }
    tree.prepare(createReq);
    return await tree.transport.sendrecv(createReq);
  }

  Future<SmbFile> openCloseFile(
      {required String path,
      required int createDisposition,
      required int createOptions,
      required int fileAttributes,
      required int desiredAccess,
      required int shareAccess}) async {
    String share = SmbConnect.getShare(path);
    String uncPath = SmbConnect.getUncPath(path);
    var createResp = await openCloseRequest(
        path: path,
        uncPath: uncPath,
        share: share,
        createDisposition: createDisposition,
        createOptions: createOptions,
        fileAttributes: fileAttributes,
        desiredAccess: desiredAccess,
        shareAccess: shareAccess);

    if (SmbConnect.responseStatusNotFound(createResp.status)) {
      return SmbFile.notExists(path, uncPath, share);
    }
    if (createResp.status != NtStatus.NT_STATUS_OK) {
      throw SmbException.getMessageByCode(createResp.status);
    }

    var next = createResp.next;
    Smb2CloseResponse? closeResp = next is Smb2CloseResponse ? next : null;
    SmbBasicFileInfo info;
    if (closeResp != null &&
        (closeResp.getCloseFlags() &
                Smb2CloseResponse.SMB2_CLOSE_FLAG_POSTQUERY_ATTRIB) !=
            0) {
      info = closeResp;
    } else {
      info = createResp;
    }
    return SmbFile.info(path, uncPath, share, info);
  }

  @override
  Future<SmbFile> file(String path) async {
    return await openCloseFile(
        path: path,
        createDisposition: Smb2Constants.FILE_OPEN,
        createOptions: 0,
        fileAttributes: SmbConstants.ATTR_NORMAL,
        desiredAccess: SmbConstants.FILE_READ_ATTRIBUTES,
        shareAccess:
            SmbConstants.FILE_SHARE_READ | SmbConstants.FILE_SHARE_WRITE);
  }

  @override
  Future<SmbFile> createFile(String path) async {
    return await openCloseFile(
        path: path,
        createDisposition: Smb2Constants.FILE_OPEN_IF,
        createOptions: 0,
        fileAttributes: SmbConstants.ATTR_NORMAL,
        desiredAccess: SmbConstants.O_RDWR,
        shareAccess: 0);
  }

  @override
  Future<SmbFile> createFolder(String path) async {
    return await openCloseFile(
      path: path,
      createDisposition: Smb2Constants.FILE_OPEN_IF,
      createOptions: Smb2Constants.FILE_DIRECTORY_FILE,
      fileAttributes: SmbConstants.ATTR_DIRECTORY,
      desiredAccess: SmbConstants.O_RDWR,
      shareAccess: SmbConstants.FILE_NO_SHARE,
    );
  }

  @override
  Future<SmbFile> delete(SmbFile file) async {
    if (!file.canWrite()) {
      throw "Access denied";
    }
    // if (!file.isExists) {
    //   return true;
    // }
    if (file.isDirectory()) {
      var childs = await listFiles(file);
      for (var childFile in childs) {
        await delete(childFile);
      }
    }
    int desiredAccess = 0x10000; // delete
    var req = await openCloseRequest(
        path: file.path,
        uncPath: file.uncPath,
        share: file.share,
        createDisposition: Smb2Constants.FILE_OPEN,
        createOptions: Smb2Constants.FILE_DELETE_ON_CLOSE,
        fileAttributes: SmbConstants.ATTR_NORMAL,
        desiredAccess: desiredAccess,
        shareAccess: 0);
    if (req.status != NtStatus.NT_STATUS_OK) {
      throw SmbException.getMessageByCode(req.status);
    }
    return SmbFile.notExists(file.path, file.uncPath, file.share);
  }

  @override
  Future<SmbFile> rename(SmbFile srcFile, String dstPath,
      {bool replace = false}) async {
    var dstFile = await file(dstPath);
    if (dstFile.isExists && !replace) {
      throw "File ${dstFile.path} already exists!";
    }
    if (srcFile.share != dstFile.share) {
      throw "Cannot rename between different shares: ${srcFile.share} != ${dstFile.share}.";
    }
    if (dstFile.isExists) {
      await delete(dstFile);
    }
    final fi = FileRenameInformation2(dstFile.uncPath.substring(1), replace);
    Smb2SetInfoRequest renameReq = Smb2SetInfoRequest(configuration, fi, fi);

    var resp = await openCloseRequest(
        path: srcFile.path,
        uncPath: srcFile.uncPath,
        share: srcFile.share,
        createDisposition: Smb2Constants.FILE_OPEN,
        createOptions: 0,
        fileAttributes: SmbConstants.ATTR_NORMAL,
        desiredAccess: SmbConstants.FILE_WRITE_ATTRIBUTES | SmbConstants.DELETE,
        shareAccess:
            SmbConstants.FILE_SHARE_READ | SmbConstants.FILE_SHARE_WRITE,
        cmd: renameReq);
    if (resp.status != NtStatus.NT_STATUS_OK) {
      throw SmbException.getMessageByCode(resp.status);
    }
    return await file(dstPath);
  }

  @override
  Future<List<SmbFile>> listShares() async {
    String share = SmbConnect.IPC_SHARE;
    String path = SmbConnect.IPC_PATH;
    var tree = await shareTree(share);
    String uncPath = SmbConnect.getUncPath(path);

    Smb2CreateRequest createReq = Smb2CreateRequest(configuration, uncPath);
    createReq.setCreateDisposition(Smb2Constants.FILE_OPEN);
    createReq.setCreateOptions(0);
    createReq.setFileAttributes(SmbConstants.ATTR_NORMAL);
    createReq.setDesiredAccess(DcerpcBase.pipeAccess);
    createReq.setShareAccess(SmbConstants.DEFAULT_SHARING);
    String fullPath = "\\$host\\$share$uncPath";
    createReq.setFullUNCPath(null, host, fullPath);

    tree.prepare(createReq);
    final resp = await tree.transport.sendrecv<Smb2CreateResponse>(createReq);

    DcerpcSmb2 dcerpc = DcerpcSmb2(transport, tree, resp);

    final msrpc = MsrpcShareEnum(host);

    final res = await dcerpc.sendrecv(msrpc);
    if (!res) {
      return [];
    }

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

    Smb2FilesEnumerator enumerator = Smb2FilesEnumerator(
        tree, transport, folder, wildcard, searchAttributes);
    final List<SmbFile> res = [];
    while (enumerator.canNext()) {
      final entries = await enumerator.next();
      if (entries != null) {
        res.addAll(mapFileEntries(folder, entries));
      }
    }
    await enumerator.close();
    return res;
  }

  Future<Smb2CreateResponse> openFile(SmbFile file,
      {required int access,
      required int openFlags,
      required int sharing,
      required int attrs}) async {
    SmbTree tree = await shareTree(file.share);

    int flags = openFlags;
    Smb2CreateRequest req = Smb2CreateRequest(configuration, file.uncPath);
    req.setDesiredAccess(access);
    String fullPath = "\\$host\\${file.share}${file.uncPath}";
    req.setFullUNCPath(null, host, fullPath);

    if (flags.isFlag(SmbConstants.O_TRUNC) &&
        flags.isFlag(SmbConstants.O_CREAT)) {
      req.setCreateDisposition(Smb2Constants.FILE_OVERWRITE_IF);
    } else if (flags.isFlag(SmbConstants.O_TRUNC)) {
      req.setCreateDisposition(Smb2Constants.FILE_OVERWRITE);
    } else if (flags.isFlag(SmbConstants.O_EXCL)) {
      req.setCreateDisposition(Smb2Constants.FILE_CREATE);
    } else if (flags.isFlag(SmbConstants.O_CREAT)) {
      req.setCreateDisposition(Smb2Constants.FILE_OPEN_IF);
    } else {
      req.setCreateDisposition(Smb2Constants.FILE_OPEN);
    }

    req.setShareAccess(sharing);
    req.setFileAttributes(attrs);
    tree.prepare(req);
    return await tree.transport.sendrecv(req);
  }

  @override
  Future<Stream<Uint8List>> openRead(SmbFile file,
      [int? start, int? end]) async {
    var resp = await openFile(file,
        access: SmbConstants.O_RDONLY,
        openFlags: 0,
        sharing: SmbConstants.DEFAULT_SHARING,
        attrs: SmbConstants.ATTR_NORMAL);
    if (resp.status != NtStatus.NT_STATUS_OK) {
      throw SmbException.getMessageByCode(resp.status);
    }

    var tree = await shareTree(file.share);
    start = start ?? 0;
    end = end ?? resp.getSize(); // ?? file.size;
    int length = end - start;
    return smbOpenRead(file, tree, resp.fileId, 0, start, length);
  }

  @override
  Future<IOSink> openWrite(SmbFile file, {bool append = false}) async {
    if (!file.isExists) {
      file = await create(file);
    }
    var resp = await openFile(file,
        access: SmbConstants.FILE_WRITE_DATA, //SmbConstants.O_RDONLY,
        openFlags: 0,
        sharing: SmbConstants.DEFAULT_SHARING,
        attrs: SmbConstants.ATTR_NORMAL);
    if (resp.status != NtStatus.NT_STATUS_OK) {
      throw SmbException.getMessageByCode(resp.status);
    }
    var tree = await shareTree(file.share);
    int position = append ? file.size : 0;
    var consumer = Smb2StreamConsumer(file, tree, resp.fileId, position);
    return IOSink(consumer);
  }

  @override
  Future<RandomAccessFile> open(SmbFile file,
      {FileMode mode = FileMode.read}) async {
    var tree = await shareTree(file.share);
    // SmbFileReader? reader;
    // SmbWriter? writer;
    Smb2RandomAccessFileController controller =
        Smb2RandomAccessFileController(file, tree, mode, openFile);
    // if (mode == FileMode.read ||
    //     mode == FileMode.write ||
    //     mode == FileMode.append) {
    //   reader = Smb2FileReader(controller);
    // }
    // if (mode == FileMode.append ||
    //     mode == FileMode.write ||
    //     mode == FileMode.writeOnly ||
    //     mode == FileMode.writeOnlyAppend) {
    //   writer = Smb2Writer(controller);
    // }

    return SmbRandomAccessFile(file, controller);
  }
}
