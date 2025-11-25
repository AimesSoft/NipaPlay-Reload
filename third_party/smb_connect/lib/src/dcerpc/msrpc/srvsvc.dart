import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';

import '../dcerpc_message.dart';
import '../ndr/ndr_buffer.dart';
import '../ndr/ndr_object.dart';

String srvsvcGetSyntax() {
  return "4b324fc8-1670-01d3-1278-5a47bf6ee188:3.0";
}

class SrvsvcShareInfo0 extends NdrObject {
  String? netname;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrReferent(netname, 1);

    if (netname != null) {
      dst = dst.deferred;
      dst.encNdrString(netname!);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    int netnamep = src.decNdrLong();

    if (netnamep != 0) {
      src = src.deferred;
      netname = src.decNdrString();
    }
  }
}

class SrvsvcShareInfoCtr0 extends NdrObject {
  int count = 0;
  List<SrvsvcShareInfo0>? array;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(array, 1);

    if (array != null) {
      dst = dst.deferred;
      int arrays = count;
      dst.encNdrLong(arrays);
      int arrayi = dst.index;
      dst.advance(4 * arrays);

      dst = dst.derive(arrayi);
      for (int i = 0; i < arrays; i++) {
        array![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int arrayp = src.decNdrLong();

    if (arrayp != 0) {
      src = src.deferred;
      int arrays = src.decNdrLong();
      int arrayi = src.index;
      src.advance(4 * arrays);

      if (array == null) {
        if (arrays < 0 || arrays > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        array = List.generate(arrays, (index) => SrvsvcShareInfo0());
      }
      src = src.derive(arrayi);
      for (int i = 0; i < arrays; i++) {
        array![i].decode(src);
      }
    }
  }
}

class SrvsvcShareInfo1 extends NdrObject {
  String? netname;
  int type = 0;
  String? remark;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrReferent(netname, 1);
    dst.encNdrLong(type);
    dst.encNdrReferent(remark, 1);

    if (netname != null) {
      dst = dst.deferred;
      dst.encNdrString(netname!);
    }
    if (remark != null) {
      dst = dst.deferred;
      dst.encNdrString(remark!);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    int netnamep = src.decNdrLong();
    type = src.decNdrLong();
    int remarkp = src.decNdrLong();

    if (netnamep != 0) {
      src = src.deferred;
      netname = src.decNdrString();
    }
    if (remarkp != 0) {
      src = src.deferred;
      remark = src.decNdrString();
    }
  }
}

class SrvsvcShareInfoCtr1 extends NdrObject {
  int count = 0;
  List<SrvsvcShareInfo1>? array;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(array, 1);

    if (array != null) {
      dst = dst.deferred;
      int arrays = count;
      dst.encNdrLong(arrays);
      int arrayi = dst.index;
      dst.advance(12 * arrays);

      dst = dst.derive(arrayi);
      for (int i = 0; i < arrays; i++) {
        array![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int arrayp = src.decNdrLong();

    if (arrayp != 0) {
      src = src.deferred;
      int arrays = src.decNdrLong();
      int arrayi = src.index;
      src.advance(12 * arrays);

      if (array == null) {
        if (arrays < 0 || arrays > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        array = List.generate(
            arrays, (index) => SrvsvcShareInfo1()); // ShareInfo1[arrays];
      }
      src = src.derive(arrayi);
      for (int i = 0; i < arrays; i++) {
        // if (array[i] == null) {
        //   array[i] = ShareInfo1();
        // }
        array![i].decode(src);
      }
    }
  }
}

class SrvsvcShareInfo502 extends NdrObject {
  String? netname;
  int type = 0;
  String? remark;
  int permissions = 0;
  int maxUses = 0;
  int currentUses = 0;
  String? path;
  String? password;
  int sdSize = 0;
  Uint8List? securityDescriptor;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrReferent(netname, 1);
    dst.encNdrLong(type);
    dst.encNdrReferent(remark, 1);
    dst.encNdrLong(permissions);
    dst.encNdrLong(maxUses);
    dst.encNdrLong(currentUses);
    dst.encNdrReferent(path, 1);
    dst.encNdrReferent(password, 1);
    dst.encNdrLong(sdSize);
    dst.encNdrReferent(securityDescriptor, 1);

    if (netname != null) {
      dst = dst.deferred;
      dst.encNdrString(netname!);
    }
    if (remark != null) {
      dst = dst.deferred;
      dst.encNdrString(remark!);
    }
    if (path != null) {
      dst = dst.deferred;
      dst.encNdrString(path!);
    }
    if (password != null) {
      dst = dst.deferred;
      dst.encNdrString(password!);
    }
    if (securityDescriptor != null) {
      dst = dst.deferred;
      int securityDescriptors = sdSize;
      dst.encNdrLong(securityDescriptors);
      int securityDescriptori = dst.index;
      dst.advance(1 * securityDescriptors);

      dst = dst.derive(securityDescriptori);
      for (int i = 0; i < securityDescriptors; i++) {
        dst.encNdrSmall(securityDescriptor![i]);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    int netnamep = src.decNdrLong();
    type = src.decNdrLong();
    int remarkp = src.decNdrLong();
    permissions = src.decNdrLong();
    maxUses = src.decNdrLong();
    currentUses = src.decNdrLong();
    int pathp = src.decNdrLong();
    int passwordp = src.decNdrLong();
    sdSize = src.decNdrLong();
    int securityDescriptorp = src.decNdrLong();

    if (netnamep != 0) {
      src = src.deferred;
      netname = src.decNdrString();
    }
    if (remarkp != 0) {
      src = src.deferred;
      remark = src.decNdrString();
    }
    if (pathp != 0) {
      src = src.deferred;
      path = src.decNdrString();
    }
    if (passwordp != 0) {
      src = src.deferred;
      password = src.decNdrString();
    }
    if (securityDescriptorp != 0) {
      src = src.deferred;
      int securityDescriptors = src.decNdrLong();
      int securityDescriptori = src.index;
      src.advance(1 * securityDescriptors);

      if (securityDescriptor == null) {
        if (securityDescriptors < 0 || securityDescriptors > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        securityDescriptor =
            Uint8List(securityDescriptors); //[securityDescriptors];
      }
      src = src.derive(securityDescriptori);
      for (int i = 0; i < securityDescriptors; i++) {
        securityDescriptor![i] = src.decNdrSmall();
      }
    }
  }
}

class SrvsvcShareInfoCtr502 extends NdrObject {
  int count = 0;
  List<SrvsvcShareInfo502>? array;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(array, 1);

    if (array != null) {
      dst = dst.deferred;
      int arrays = count;
      dst.encNdrLong(arrays);
      int arrayi = dst.index;
      dst.advance(40 * arrays);

      dst = dst.derive(arrayi);
      for (int i = 0; i < arrays; i++) {
        array![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int arrayp = src.decNdrLong();

    if (arrayp != 0) {
      src = src.deferred;
      int arrays = src.decNdrLong();
      int arrayi = src.index;
      src.advance(40 * arrays);

      if (array == null) {
        if (arrays < 0 || arrays > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        array = List.generate(arrays, (index) => SrvsvcShareInfo502());
      }
      src = src.derive(arrayi);
      for (int i = 0; i < arrays; i++) {
        array![i].decode(src);
      }
    }
  }
}

class SrvsvcShareEnumAll extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x0f;
  }

  int retval = 0;
  String? servername;
  int level;
  NdrObject? info;
  int prefmaxlen;
  int totalentries;
  int resumeHandle;

  SrvsvcShareEnumAll(this.servername, this.level, this.info, this.prefmaxlen,
      this.totalentries, this.resumeHandle);

  @override
  void encodeIn(NdrBuffer buf) {
    buf.encNdrReferent(servername, 1);
    if (servername != null) {
      buf.encNdrString(servername!);
    }
    buf.encNdrLong(level);
    int descr = level;
    buf.encNdrLong(descr);
    buf.encNdrReferent(info, 1);
    if (info != null) {
      buf = buf.deferred;
      info!.encode(buf);
    }
    buf.encNdrLong(prefmaxlen);
    buf.encNdrLong(resumeHandle);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    level = buf.decNdrLong();
    buf.decNdrLong(); /* union discriminant */
    int infop = buf.decNdrLong();
    if (infop != 0) {
      info ??= SrvsvcShareInfoCtr0();
      buf = buf.deferred;
      info!.decode(buf);
    }
    totalentries = buf.decNdrLong();
    resumeHandle = buf.decNdrLong();
    retval = buf.decNdrLong();
  }
}

class SrvsvcShareGetInfo extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x10;
  }

  int retval = 0;
  String? servername;
  String sharename;
  int level;
  NdrObject? info;

  SrvsvcShareGetInfo(this.servername, this.sharename, this.level, this.info);

  @override
  void encodeIn(NdrBuffer buf) {
    buf.encNdrReferent(servername, 1);
    if (servername != null) {
      buf.encNdrString(servername!);
    }
    buf.encNdrString(sharename);
    buf.encNdrLong(level);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    buf.decNdrLong(); /* union discriminant */
    int infop = buf.decNdrLong();
    if (infop != 0) {
      info ??= SrvsvcShareInfo0();
      buf = buf.deferred;
      info!.decode(buf);
    }
    retval = buf.decNdrLong();
  }
}

class SrvsvcServerInfo100 extends NdrObject {
  int platformId = 0;
  String? name;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(platformId);
    dst.encNdrReferent(name, 1);

    if (name != null) {
      dst = dst.deferred;
      dst.encNdrString(name!);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    platformId = src.decNdrLong();
    int namep = src.decNdrLong();

    if (namep != 0) {
      src = src.deferred;
      name = src.decNdrString();
    }
  }
}

class SrvsvcServerGetInfo extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x15;
  }

  int retval = 0;
  String? servername;
  int level;
  NdrObject? info;

  SrvsvcServerGetInfo(this.servername, this.level, this.info);

  @override
  void encodeIn(NdrBuffer buf) {
    buf.encNdrReferent(servername, 1);
    if (servername != null) {
      buf.encNdrString(servername!);
    }
    buf.encNdrLong(level);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    buf.decNdrLong(); /* union discriminant */
    int infop = buf.decNdrLong();
    if (infop != 0) {
      info ??= SrvsvcServerInfo100();
      buf = buf.deferred;
      info!.decode(buf);
    }
    retval = buf.decNdrLong();
  }
}

class SrvsvcTimeOfDayInfo extends NdrObject {
  int elapsedt = 0;
  int msecs = 0;
  int hours = 0;
  int mins = 0;
  int secs = 0;
  int hunds = 0;
  int timezone = 0;
  int tinterval = 0;
  int day = 0;
  int month = 0;
  int year = 0;
  int weekday = 0;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(elapsedt);
    dst.encNdrLong(msecs);
    dst.encNdrLong(hours);
    dst.encNdrLong(mins);
    dst.encNdrLong(secs);
    dst.encNdrLong(hunds);
    dst.encNdrLong(timezone);
    dst.encNdrLong(tinterval);
    dst.encNdrLong(day);
    dst.encNdrLong(month);
    dst.encNdrLong(year);
    dst.encNdrLong(weekday);
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    elapsedt = src.decNdrLong();
    msecs = src.decNdrLong();
    hours = src.decNdrLong();
    mins = src.decNdrLong();
    secs = src.decNdrLong();
    hunds = src.decNdrLong();
    timezone = src.decNdrLong();
    tinterval = src.decNdrLong();
    day = src.decNdrLong();
    month = src.decNdrLong();
    year = src.decNdrLong();
    weekday = src.decNdrLong();
  }
}

class SrvsvcRemoteTOD extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x1c;
  }

  int retval = 0;
  String? servername;
  SrvsvcTimeOfDayInfo? info;

  SrvsvcRemoteTOD(this.servername, this.info);

  @override
  void encodeIn(NdrBuffer buf) {
    buf.encNdrReferent(servername, 1);
    if (servername != null) {
      buf.encNdrString(servername!);
    }
  }

  @override
  void decodeOut(NdrBuffer buf) {
    int infop = buf.decNdrLong();
    if (infop != 0) {
      info ??= SrvsvcTimeOfDayInfo();
      info!.decode(buf);
    }
    retval = buf.decNdrLong();
  }
}
