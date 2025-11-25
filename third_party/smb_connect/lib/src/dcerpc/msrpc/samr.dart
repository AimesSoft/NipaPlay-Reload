import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_message.dart';
import 'package:smb_connect/src/dcerpc/msrpc/lsarpc.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_object.dart';
import 'package:smb_connect/src/dcerpc/rpc.dart';

String samrGetSyntax() {
  return "12345778-1234-abcd-ef00-0123456789ac:1.0";
}

class SamrCloseHandle extends DcerpcMessage {
  static const int ACB_DISABLED = 1;
  static const int ACB_HOMDIRREQ = 2;
  static const int ACB_PWNOTREQ = 4;
  static const int ACB_TEMPDUP = 8;
  static const int ACB_NORMAL = 16;
  static const int ACB_MNS = 32;
  static const int ACB_DOMTRUST = 64;
  static const int ACB_WSTRUST = 128;
  static const int ACB_SVRTRUST = 256;
  static const int ACB_PWNOEXP = 512;
  static const int ACB_AUTOLOCK = 1024;
  static const int ACB_ENC_TXT_PWD_ALLOWED = 2048;
  static const int ACB_SMARTCARD_REQUIRED = 4096;
  static const int ACB_TRUSTED_FOR_DELEGATION = 8192;
  static const int ACB_NOT_DELEGATED = 16384;
  static const int ACB_USE_DES_KEY_ONLY = 32768;
  static const int ACB_DONT_REQUIRE_PREAUTH = 65536;

  @override
  int getOpnum() {
    return 0x01;
  }

  int retval = 0;
  RpcPolicyHandle handle;

  SamrCloseHandle(this.handle);

  @override
  void encodeIn(NdrBuffer buf) {
    handle.encode(buf);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    retval = buf.decNdrLong();
  }
}

class SamrConnect2 extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x39;
  }

  int retval = 0;
  String? systemName;
  int accessMask;
  RpcPolicyHandle handle;

  SamrConnect2(this.systemName, this.accessMask, this.handle);

  @override
  void encodeIn(NdrBuffer buf) {
    buf.encNdrReferent(systemName, 1);
    if (systemName != null) {
      buf.encNdrString(systemName!);
    }
    buf.encNdrLong(accessMask);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    handle.decode(buf);
    retval = buf.decNdrLong();
  }
}

class SamrConnect4 extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x3e;
  }

  int retval = 0;
  String? systemName;
  int unknown;
  int accessMask;
  RpcPolicyHandle handle;

  SamrConnect4(this.systemName, this.unknown, this.accessMask, this.handle);

  @override
  void encodeIn(NdrBuffer buf) {
    buf.encNdrReferent(systemName, 1);
    if (systemName != null) {
      buf.encNdrString(systemName!);
    }
    buf.encNdrLong(unknown);
    buf.encNdrLong(accessMask);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    handle.decode(buf);
    retval = buf.decNdrLong();
  }
}

class SamrOpenDomain extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x07;
  }

  int retval = 0;
  RpcPolicyHandle handle;
  int accessMask;
  RpcSidT sid;
  RpcPolicyHandle domainHandle;

  SamrOpenDomain(this.handle, this.accessMask, this.sid, this.domainHandle);

  @override
  void encodeIn(NdrBuffer buf) {
    handle.encode(buf);
    buf.encNdrLong(accessMask);
    sid.encode(buf);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    domainHandle.decode(buf);
    retval = buf.decNdrLong();
  }
}

class SamrSamEntry extends NdrObject {
  int idx = 0;
  RpcUnicodeString? name;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(idx);
    dst.encNdrShort(name!.length);
    dst.encNdrShort(name!.maximumLength);
    dst.encNdrReferent(name!.buffer, 1);

    if (name!.buffer != null) {
      dst = dst.deferred;
      int nameBufferl = name!.length ~/ 2;
      int nameBuffers = name!.maximumLength ~/ 2;
      dst.encNdrLong(nameBuffers);
      dst.encNdrLong(0);
      dst.encNdrLong(nameBufferl);
      int nameBufferi = dst.index;
      dst.advance(2 * nameBufferl);

      dst = dst.derive(nameBufferi);
      for (int i = 0; i < nameBufferl; i++) {
        dst.encNdrShort(name!.buffer![i]);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    idx = src.decNdrLong();
    src.align(4);
    name ??= RpcUnicodeString();
    name!.length = src.decNdrShort();
    name!.maximumLength = src.decNdrShort();
    int nameBufferp = src.decNdrLong();

    if (nameBufferp != 0) {
      src = src.deferred;
      int nameBuffers = src.decNdrLong();
      src.decNdrLong();
      int nameBufferl = src.decNdrLong();
      int nameBufferi = src.index;
      src.advance(2 * nameBufferl);

      if (name!.buffer == null) {
        if (nameBuffers < 0 || nameBuffers > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        name!.buffer = Uint8List(nameBuffers);
      }
      src = src.derive(nameBufferi);
      for (int i = 0; i < nameBufferl; i++) {
        name!.buffer![i] = src.decNdrShort();
      }
    }
  }
}

class SamrSamArray extends NdrObject {
  int count = 0;
  List<SamrSamEntry>? entries;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(entries, 1);

    if (entries != null) {
      dst = dst.deferred;
      int entriess = count;
      dst.encNdrLong(entriess);
      int entriesi = dst.index;
      dst.advance(12 * entriess);

      dst = dst.derive(entriesi);
      for (int i = 0; i < entriess; i++) {
        entries![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int entriesp = src.decNdrLong();

    if (entriesp != 0) {
      src = src.deferred;
      int entriess = src.decNdrLong();
      int entriesi = src.index;
      src.advance(12 * entriess);

      if (entries == null) {
        if (entriess < 0 || entriess > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        entries = List.generate(entriess, (index) => SamrSamEntry());
      }
      src = src.derive(entriesi);
      for (int i = 0; i < entriess; i++) {
        entries![i].decode(src);
      }
    }
  }
}

class SamrEnumerateAliasesInDomain extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x0f;
  }

  int retval = 0;
  RpcPolicyHandle domainHandle;
  int resumeHandle;
  int acctFlags;
  SamrSamArray? sam;
  int numEntries;

  SamrEnumerateAliasesInDomain(this.domainHandle, this.resumeHandle,
      this.acctFlags, this.sam, this.numEntries);

  @override
  void encodeIn(NdrBuffer buf) {
    domainHandle.encode(buf);
    buf.encNdrLong(resumeHandle);
    buf.encNdrLong(acctFlags);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    resumeHandle = buf.decNdrLong();
    int samp = buf.decNdrLong();
    if (samp != 0) {
      sam ??= SamrSamArray();
      sam!.decode(buf);
    }
    numEntries = buf.decNdrLong();
    retval = buf.decNdrLong();
  }
}

class SamrOpenAlias extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x1b;
  }

  int retval = 0;
  RpcPolicyHandle domainHandle;
  int accessMask;
  int rid;
  RpcPolicyHandle aliasHandle;

  SamrOpenAlias(this.domainHandle, this.accessMask, this.rid, this.aliasHandle);

  @override
  void encodeIn(NdrBuffer buf) {
    domainHandle.encode(buf);
    buf.encNdrLong(accessMask);
    buf.encNdrLong(rid);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    aliasHandle.decode(buf);
    retval = buf.decNdrLong();
  }
}

class SamrGetMembersInAlias extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x21;
  }

  int retval = 0;
  RpcPolicyHandle aliasHandle;
  LsarpcSidArray sids;

  SamrGetMembersInAlias(this.aliasHandle, this.sids);

  @override
  void encodeIn(NdrBuffer buf) {
    aliasHandle.encode(buf);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    sids.decode(buf);
    retval = buf.decNdrLong();
  }
}

class SamrRidWithAttribute extends NdrObject {
  static const int SE_GROUP_MANDATORY = 1;
  static const int SE_GROUP_ENABLED_BY_DEFAULT = 2;
  static const int SE_GROUP_ENABLED = 4;
  static const int SE_GROUP_OWNER = 8;
  static const int SE_GROUP_USE_FOR_DENY_ONLY = 16;
  static const int SE_GROUP_RESOURCE = 536870912;
  static const int SE_GROUP_LOGON_ID = -1073741824;

  int rid = 0;
  int attributes = 0;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(rid);
    dst.encNdrLong(attributes);
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    rid = src.decNdrLong();
    attributes = src.decNdrLong();
  }
}

class SamrRidWithAttributeArray extends NdrObject {
  int count = 0;
  List<SamrRidWithAttribute>? rids;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(rids, 1);

    if (rids != null) {
      dst = dst.deferred;
      int ridss = count;
      dst.encNdrLong(ridss);
      int ridsi = dst.index;
      dst.advance(8 * ridss);

      dst = dst.derive(ridsi);
      for (int i = 0; i < ridss; i++) {
        rids![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int ridsp = src.decNdrLong();

    if (ridsp != 0) {
      src = src.deferred;
      int ridss = src.decNdrLong();
      int ridsi = src.index;
      src.advance(8 * ridss);

      if (rids == null) {
        if (ridss < 0 || ridss > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        rids = List.generate(
            ridss,
            (index) =>
                SamrRidWithAttribute()); // samr_SamrRidWithAttribute[ridss];
      }
      src = src.derive(ridsi);
      for (int i = 0; i < ridss; i++) {
        // if (rids[i] == null) {
        //   rids[i] = samr_SamrRidWithAttribute();
        // }
        rids![i].decode(src);
      }
    }
  }
}
