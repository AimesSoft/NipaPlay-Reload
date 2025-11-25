import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_message.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_object.dart';

import '../ndr/ndr_long.dart';

String netdfsGetSyntax() {
  return "4fc742e0-4a10-11cf-8273-00aa004ae673:3.0";
}

class NetDfsInfo1 extends NdrObject {
  static const int DFS_VOLUME_FLAVOR_STANDALONE = 0x100;
  static const int DFS_VOLUME_FLAVOR_AD_BLOB = 0x200;
  static const int DFS_STORAGE_STATE_OFFLINE = 0x0001;
  static const int DFS_STORAGE_STATE_ONLINE = 0x0002;
  static const int DFS_STORAGE_STATE_ACTIVE = 0x0004;

  String? entryPath;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrReferent(entryPath, 1);

    if (entryPath != null) {
      dst = dst.deferred;
      dst.encNdrString(entryPath!);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    int entryPathp = src.decNdrLong();

    if (entryPathp != 0) {
      src = src.deferred;
      entryPath = src.decNdrString();
    }
  }
}

class NetDfsEnumArray1 extends NdrObject {
  int count = 0;
  List<NetDfsInfo1>? s;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(s, 1);

    if (s != null) {
      dst = dst.deferred;
      int ss = count;
      dst.encNdrLong(ss);
      int si = dst.index;
      dst.advance(4 * ss);

      dst = dst.derive(si);
      for (int i = 0; i < ss; i++) {
        s![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int sp = src.decNdrLong();

    if (sp != 0) {
      src = src.deferred;
      int ss = src.decNdrLong();
      int si = src.index;
      src.advance(4 * ss);

      if (s == null) {
        if (ss < 0 || ss > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        s = List.generate(ss, (index) => NetDfsInfo1());
      }
      src = src.derive(si);
      for (int i = 0; i < ss; i++) {
        s![i].decode(src);
      }
    }
  }
}

class NetDfsStorageInfo extends NdrObject {
  int state = 0;
  String? serverName;
  String? shareName;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(state);
    dst.encNdrReferent(serverName, 1);
    dst.encNdrReferent(shareName, 1);

    if (serverName != null) {
      dst = dst.deferred;
      dst.encNdrString(serverName!);
    }
    if (shareName != null) {
      dst = dst.deferred;
      dst.encNdrString(shareName!);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    state = src.decNdrLong();
    int serverNamep = src.decNdrLong();
    int shareNamep = src.decNdrLong();

    if (serverNamep != 0) {
      src = src.deferred;
      serverName = src.decNdrString();
    }
    if (shareNamep != 0) {
      src = src.deferred;
      shareName = src.decNdrString();
    }
  }
}

class NetDfsInfo3 extends NdrObject {
  String? path;
  String? comment;
  int state = 0;
  int numStores = 0;
  List<NetDfsStorageInfo>? stores;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrReferent(path, 1);
    dst.encNdrReferent(comment, 1);
    dst.encNdrLong(state);
    dst.encNdrLong(numStores);
    dst.encNdrReferent(stores, 1);

    if (path != null) {
      dst = dst.deferred;
      dst.encNdrString(path!);
    }
    if (comment != null) {
      dst = dst.deferred;
      dst.encNdrString(comment!);
    }
    if (stores != null) {
      dst = dst.deferred;
      int storess = numStores;
      dst.encNdrLong(storess);
      int storesi = dst.index;
      dst.advance(12 * storess);

      dst = dst.derive(storesi);
      for (int i = 0; i < storess; i++) {
        stores![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    int pathp = src.decNdrLong();
    int commentp = src.decNdrLong();
    state = src.decNdrLong();
    numStores = src.decNdrLong();
    int storesp = src.decNdrLong();

    if (pathp != 0) {
      src = src.deferred;
      path = src.decNdrString();
    }
    if (commentp != 0) {
      src = src.deferred;
      comment = src.decNdrString();
    }
    if (storesp != 0) {
      src = src.deferred;
      int storess = src.decNdrLong();
      int storesi = src.index;
      src.advance(12 * storess);

      if (stores == null) {
        if (storess < 0 || storess > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        stores = List.generate(storess, (index) => NetDfsStorageInfo());
      }
      src = src.derive(storesi);
      for (int i = 0; i < storess; i++) {
        stores![i].decode(src);
      }
    }
  }
}

class NetDfsEnumArray3 extends NdrObject {
  int count = 0;
  List<NetDfsInfo3>? s;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(s, 1);

    if (s != null) {
      dst = dst.deferred;
      int ss = count;
      dst.encNdrLong(ss);
      int si = dst.index;
      dst.advance(20 * ss);

      dst = dst.derive(si);
      for (int i = 0; i < ss; i++) {
        s![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int sp = src.decNdrLong();

    if (sp != 0) {
      src = src.deferred;
      int ss = src.decNdrLong();
      int si = src.index;
      src.advance(20 * ss);

      if (s == null) {
        if (ss < 0 || ss > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        s = List.generate(ss, (index) => NetDfsInfo3());
      }
      src = src.derive(si);
      for (int i = 0; i < ss; i++) {
        s![i].decode(src);
      }
    }
  }
}

class NetDfsInfo200 extends NdrObject {
  String? dfsName;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrReferent(dfsName, 1);

    if (dfsName != null) {
      dst = dst.deferred;
      dst.encNdrString(dfsName!);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    int dfsNamep = src.decNdrLong();

    if (dfsNamep != 0) {
      src = src.deferred;
      dfsName = src.decNdrString();
    }
  }
}

class NetDfsEnumArray200 extends NdrObject {
  int count = 0;
  List<NetDfsInfo200>? s;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(s, 1);

    if (s != null) {
      dst = dst.deferred;
      int ss = count;
      dst.encNdrLong(ss);
      int si = dst.index;
      dst.advance(4 * ss);

      dst = dst.derive(si);
      for (int i = 0; i < ss; i++) {
        s![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int sp = src.decNdrLong();

    if (sp != 0) {
      src = src.deferred;
      int ss = src.decNdrLong();
      int si = src.index;
      src.advance(4 * ss);

      if (s == null) {
        if (ss < 0 || ss > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        s = List.generate(ss, (index) => NetDfsInfo200());
      }
      src = src.derive(si);
      for (int i = 0; i < ss; i++) {
        s![i].decode(src);
      }
    }
  }
}

class NetDfsInfo300 extends NdrObject {
  int flags = 0;
  String? dfsName;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(flags);
    dst.encNdrReferent(dfsName, 1);

    if (dfsName != null) {
      dst = dst.deferred;
      dst.encNdrString(dfsName!);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    flags = src.decNdrLong();
    int dfsNamep = src.decNdrLong();

    if (dfsNamep != 0) {
      src = src.deferred;
      dfsName = src.decNdrString();
    }
  }
}

class NetDfsEnumArray300 extends NdrObject {
  int count = 0;
  List<NetDfsInfo300>? s;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(s, 1);

    if (s != null) {
      dst = dst.deferred;
      int ss = count;
      dst.encNdrLong(ss);
      int si = dst.index;
      dst.advance(8 * ss);

      dst = dst.derive(si);
      for (int i = 0; i < ss; i++) {
        s![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int sp = src.decNdrLong();

    if (sp != 0) {
      src = src.deferred;
      int ss = src.decNdrLong();
      int si = src.index;
      src.advance(8 * ss);

      if (s == null) {
        if (ss < 0 || ss > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        s = List.generate(ss, (index) => NetDfsInfo300());
      }
      src = src.derive(si);
      for (int i = 0; i < ss; i++) {
        s![i].decode(src);
      }
    }
  }
}

class NetDfsEnumStruct extends NdrObject {
  int level = 0;
  NdrObject? e;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(level);
    int descr = level;
    dst.encNdrLong(descr);
    dst.encNdrReferent(e, 1);

    if (e != null) {
      dst = dst.deferred;
      e!.encode(dst);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    level = src.decNdrLong();
    src.decNdrLong(); /* union discriminant */
    int ep = src.decNdrLong();

    if (ep != 0) {
      e ??= NetDfsEnumArray1();
      src = src.deferred;
      e!.decode(src);
    }
  }
}

class NetdfsNetrDfsEnumEx extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x15;
  }

  int retval = 0;
  String? dfsName;
  int level = 0;
  int prefmaxlen;
  NetDfsEnumStruct? info;
  NdrLong? totalentries;

  NetdfsNetrDfsEnumEx(
    this.dfsName,
    this.level,
    this.prefmaxlen,
    this.info,
    this.totalentries,
  );

  @override
  void encodeIn(NdrBuffer buf) {
    buf.encNdrString(dfsName!);
    buf.encNdrLong(level);
    buf.encNdrLong(prefmaxlen);
    buf.encNdrReferent(info, 1);
    info!.encode(buf);
    buf.encNdrReferent(totalentries, 1);
    totalentries?.encode(buf);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    int infop = buf.decNdrLong();
    if (infop != 0) {
      info ??= NetDfsEnumStruct();
      info!.decode(buf);
    }
    int totalentriesp = buf.decNdrLong();
    if (totalentriesp != 0) {
      totalentries!.decode(buf);
    }
    retval = buf.decNdrLong();
  }
}
