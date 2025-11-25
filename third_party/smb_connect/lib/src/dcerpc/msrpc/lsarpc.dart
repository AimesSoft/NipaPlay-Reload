import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_message.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_object.dart';
import 'package:smb_connect/src/dcerpc/rpc.dart';

import '../ndr/ndr_small.dart';

String lsarpcGetSyntax() {
  return "12345778-1234-abcd-ef00-0123456789ab:0.0";
}

class LsarpcQosInfo extends NdrObject {
  int length = 0;
  int impersonationLevel = 0;
  int contextMode = 0;
  int effectiveOnly = 0;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(length);
    dst.encNdrShort(impersonationLevel);
    dst.encNdrSmall(contextMode);
    dst.encNdrSmall(effectiveOnly);
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    length = src.decNdrLong();
    impersonationLevel = src.decNdrShort();
    contextMode = src.decNdrSmall();
    effectiveOnly = src.decNdrSmall();
  }
}

class LsarpcObjectAttributes extends NdrObject {
  int length = 0;
  NdrSmall? rootDirectory;
  RpcUnicodeString? objectName;
  int attributes = 0;
  int securityDescriptor = 0;
  LsarpcQosInfo? securityQualityOfService;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(length);
    dst.encNdrReferent(rootDirectory, 1);
    dst.encNdrReferent(objectName, 1);
    dst.encNdrLong(attributes);
    dst.encNdrLong(securityDescriptor);
    dst.encNdrReferent(securityQualityOfService, 1);

    if (rootDirectory != null) {
      dst = dst.deferred;
      rootDirectory!.encode(dst);
    }
    if (objectName != null) {
      dst = dst.deferred;
      objectName!.encode(dst);
    }
    if (securityQualityOfService != null) {
      dst = dst.deferred;
      securityQualityOfService!.encode(dst);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    length = src.decNdrLong();
    int rootDirectoryp = src.decNdrLong();
    int objectNamep = src.decNdrLong();
    attributes = src.decNdrLong();
    securityDescriptor = src.decNdrLong();
    int securityQualityOfServicep = src.decNdrLong();

    if (rootDirectoryp != 0) {
      src = src.deferred;
      rootDirectory!.decode(src);
    }
    if (objectNamep != 0) {
      objectName ??= RpcUnicodeString();
      src = src.deferred;
      objectName!.decode(src);
    }
    if (securityQualityOfServicep != 0) {
      securityQualityOfService ??= LsarpcQosInfo();
      src = src.deferred;
      securityQualityOfService!.decode(src);
    }
  }
}

class LsarpcDomainInfo extends NdrObject {
  RpcUnicodeString? name;
  RpcSidT? sid;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrShort(name!.length);
    dst.encNdrShort(name!.maximumLength);
    dst.encNdrReferent(name!.buffer, 1);
    dst.encNdrReferent(sid, 1);

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
    if (sid != null) {
      dst = dst.deferred;
      sid!.encode(dst);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    src.align(4);
    name ??= RpcUnicodeString();
    name!.length = src.decNdrShort();
    name!.maximumLength = src.decNdrShort();
    int nameBufferp = src.decNdrLong();
    int sidp = src.decNdrLong();

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
    if (sidp != 0) {
      sid ??= RpcSidT();
      src = src.deferred;
      sid!.decode(src);
    }
  }
}

class LsarpcDnsDomainInfo extends NdrObject {
  RpcUnicodeString? name;
  RpcUnicodeString? dnsDomain;
  RpcUnicodeString? dnsForest;
  RpcUuidT? domainGuid;
  RpcSidT? sid;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrShort(name!.length);
    dst.encNdrShort(name!.maximumLength);
    dst.encNdrReferent(name!.buffer, 1);
    dst.encNdrShort(dnsDomain!.length);
    dst.encNdrShort(dnsDomain!.maximumLength);
    dst.encNdrReferent(dnsDomain!.buffer, 1);
    dst.encNdrShort(dnsForest!.length);
    dst.encNdrShort(dnsForest!.maximumLength);
    dst.encNdrReferent(dnsForest!.buffer, 1);
    dst.encNdrLong(domainGuid!.timeLow);
    dst.encNdrShort(domainGuid!.timeMid);
    dst.encNdrShort(domainGuid!.timeHiAndVersion);
    dst.encNdrSmall(domainGuid!.clockSeqHiAndReserved);
    dst.encNdrSmall(domainGuid!.clockSeqLow);
    int domainGuidNodes = 6;
    int domainGuidNodei = dst.index;
    dst.advance(1 * domainGuidNodes);
    dst.encNdrReferent(sid, 1);

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
    if (dnsDomain!.buffer != null) {
      dst = dst.deferred;
      int dnsDomainBufferl = dnsDomain!.length ~/ 2;
      int dnsDomainBuffers = dnsDomain!.maximumLength ~/ 2;
      dst.encNdrLong(dnsDomainBuffers);
      dst.encNdrLong(0);
      dst.encNdrLong(dnsDomainBufferl);
      int dnsDomainBufferi = dst.index;
      dst.advance(2 * dnsDomainBufferl);

      dst = dst.derive(dnsDomainBufferi);
      for (int i = 0; i < dnsDomainBufferl; i++) {
        dst.encNdrShort(dnsDomain!.buffer![i]);
      }
    }
    if (dnsForest!.buffer != null) {
      dst = dst.deferred;
      int dnsForestBufferl = dnsForest!.length ~/ 2;
      int dnsForestBuffers = dnsForest!.maximumLength ~/ 2;
      dst.encNdrLong(dnsForestBuffers);
      dst.encNdrLong(0);
      dst.encNdrLong(dnsForestBufferl);
      int dnsForestBufferi = dst.index;
      dst.advance(2 * dnsForestBufferl);

      dst = dst.derive(dnsForestBufferi);
      for (int i = 0; i < dnsForestBufferl; i++) {
        dst.encNdrShort(dnsForest!.buffer![i]);
      }
    }
    dst = dst.derive(domainGuidNodei);
    for (int i = 0; i < domainGuidNodes; i++) {
      dst.encNdrSmall(domainGuid!.node![i]);
    }
    if (sid != null) {
      dst = dst.deferred;
      sid!.encode(dst);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    src.align(4);
    name ??= RpcUnicodeString();
    name!.length = src.decNdrShort();
    name!.maximumLength = src.decNdrShort();
    int nameBufferp = src.decNdrLong();
    src.align(4);
    dnsDomain ??= RpcUnicodeString();
    dnsDomain!.length = src.decNdrShort();
    dnsDomain!.maximumLength = src.decNdrShort();
    int dnsDomainBufferp = src.decNdrLong();
    src.align(4);
    dnsForest ??= RpcUnicodeString();
    dnsForest!.length = src.decNdrShort();
    dnsForest!.maximumLength = src.decNdrShort();
    int dnsForestBufferp = src.decNdrLong();
    src.align(4);
    domainGuid ??= RpcUuidT();
    domainGuid!.timeLow = src.decNdrLong();
    domainGuid!.timeMid = src.decNdrShort();
    domainGuid!.timeHiAndVersion = src.decNdrShort();
    domainGuid!.clockSeqHiAndReserved = src.decNdrSmall();
    domainGuid!.clockSeqLow = src.decNdrSmall();
    int domainGuidNodes = 6;
    int domainGuidNodei = src.index;
    src.advance(1 * domainGuidNodes);
    int sidp = src.decNdrLong();

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
    if (dnsDomainBufferp != 0) {
      src = src.deferred;
      int dnsDomainBuffers = src.decNdrLong();
      src.decNdrLong();
      int dnsDomainBufferl = src.decNdrLong();
      int dnsDomainBufferi = src.index;
      src.advance(2 * dnsDomainBufferl);

      if (dnsDomain!.buffer == null) {
        if (dnsDomainBuffers < 0 || dnsDomainBuffers > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        dnsDomain!.buffer = Uint8List(dnsDomainBuffers);
      }
      src = src.derive(dnsDomainBufferi);
      for (int i = 0; i < dnsDomainBufferl; i++) {
        dnsDomain!.buffer![i] = src.decNdrShort();
      }
    }
    if (dnsForestBufferp != 0) {
      src = src.deferred;
      int dnsForestBuffers = src.decNdrLong();
      src.decNdrLong();
      int dnsForestBufferl = src.decNdrLong();
      int dnsForestBufferi = src.index;
      src.advance(2 * dnsForestBufferl);

      if (dnsForest!.buffer == null) {
        if (dnsForestBuffers < 0 || dnsForestBuffers > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        dnsForest!.buffer = Uint8List(dnsForestBuffers);
      }
      src = src.derive(dnsForestBufferi);
      for (int i = 0; i < dnsForestBufferl; i++) {
        dnsForest!.buffer![i] = src.decNdrShort();
      }
    }
    if (domainGuid!.node == null) {
      if (domainGuidNodes < 0 || domainGuidNodes > 0xFFFF) {
        throw NdrException(NdrException.INVALID_CONFORMANCE);
      }
      domainGuid!.node = Uint8List(domainGuidNodes);
    }
    src = src.derive(domainGuidNodei);
    for (int i = 0; i < domainGuidNodes; i++) {
      domainGuid!.node![i] = src.decNdrSmall();
    }
    if (sidp != 0) {
      sid ??= RpcSidT();
      src = src.deferred;
      sid!.decode(src);
    }
  }
}

class LsarpcSidPtr extends NdrObject {
  static const int POLICY_INFO_AUDIT_EVENTS = 2;
  static const int POLICY_INFO_PRIMARY_DOMAIN = 3;
  static const int POLICY_INFO_ACCOUNT_DOMAIN = 5;
  static const int POLICY_INFO_SERVER_ROLE = 6;
  static const int POLICY_INFO_MODIFICATION = 9;
  static const int POLICY_INFO_DNS_DOMAIN = 12;

  RpcSidT? sid;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrReferent(sid, 1);

    if (sid != null) {
      dst = dst.deferred;
      sid!.encode(dst);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    int sidp = src.decNdrLong();

    if (sidp != 0) {
      sid ??= RpcSidT();
      src = src.deferred;
      sid!.decode(src);
    }
  }
}

class LsarpcSidArray extends NdrObject {
  int numSids = 0;
  List<LsarpcSidPtr>? sids;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(numSids);
    dst.encNdrReferent(sids, 1);

    if (sids != null) {
      dst = dst.deferred;
      int sidss = numSids;
      dst.encNdrLong(sidss);
      int sidsi = dst.index;
      dst.advance(4 * sidss);

      dst = dst.derive(sidsi);
      for (int i = 0; i < sidss; i++) {
        sids![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    numSids = src.decNdrLong();
    int sidsp = src.decNdrLong();

    if (sidsp != 0) {
      src = src.deferred;
      int sidss = src.decNdrLong();
      int sidsi = src.index;
      src.advance(4 * sidss);

      if (sids == null) {
        if (sidss < 0 || sidss > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        sids = List.generate(sidss, (index) => LsarpcSidPtr());
      }
      src = src.derive(sidsi);
      for (int i = 0; i < sidss; i++) {
        sids![i].decode(src);
      }
    }
  }
}

class LsarpcTranslatedSid extends NdrObject {
  static const int SID_NAME_USE_NONE = 0;
  static const int SID_NAME_USER = 1;
  static const int SID_NAME_DOM_GRP = 2;
  static const int SID_NAME_DOMAIN = 3;
  static const int SID_NAME_ALIAS = 4;
  static const int SID_NAME_WKN_GRP = 5;
  static const int SID_NAME_DELETED = 6;
  static const int SID_NAME_INVALID = 7;
  static const int SID_NAME_UNKNOWN = 8;

  int sidType = 0;
  int rid = 0;
  int sidIndex = 0;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrShort(sidType);
    dst.encNdrLong(rid);
    dst.encNdrLong(sidIndex);
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    sidType = src.decNdrShort();
    rid = src.decNdrLong();
    sidIndex = src.decNdrLong();
  }
}

class LsarpcTransSidArray extends NdrObject {
  int count = 0;
  List<LsarpcTranslatedSid>? sids;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(sids, 1);

    if (sids != null) {
      dst = dst.deferred;
      int sidss = count;
      dst.encNdrLong(sidss);
      int sidsi = dst.index;
      dst.advance(12 * sidss);

      dst = dst.derive(sidsi);
      for (int i = 0; i < sidss; i++) {
        sids![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int sidsp = src.decNdrLong();

    if (sidsp != 0) {
      src = src.deferred;
      int sidss = src.decNdrLong();
      int sidsi = src.index;
      src.advance(12 * sidss);

      if (sids == null) {
        if (sidss < 0 || sidss > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        sids = List.generate(sidss, (index) => LsarpcTranslatedSid());
      }
      src = src.derive(sidsi);
      for (int i = 0; i < sidss; i++) {
        sids![i].decode(src);
      }
    }
  }
}

class LsarpcTrustInformation extends NdrObject {
  RpcUnicodeString? name;
  RpcSidT? sid;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrShort(name!.length);
    dst.encNdrShort(name!.maximumLength);
    dst.encNdrReferent(name!.buffer, 1);
    dst.encNdrReferent(sid, 1);

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
    if (sid != null) {
      dst = dst.deferred;
      sid!.encode(dst);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    src.align(4);
    name ??= RpcUnicodeString();
    name!.length = src.decNdrShort();
    name!.maximumLength = src.decNdrShort();
    int nameBufferp = src.decNdrLong();
    int sidp = src.decNdrLong();

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
    if (sidp != 0) {
      sid ??= RpcSidT();
      src = src.deferred;
      sid!.decode(src);
    }
  }
}

class LsarpcRefDomainList extends NdrObject {
  int count = 0;
  List<LsarpcTrustInformation>? domains;
  int maxCount = 0;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(domains, 1);
    dst.encNdrLong(maxCount);

    if (domains != null) {
      dst = dst.deferred;
      int domainss = count;
      dst.encNdrLong(domainss);
      int domainsi = dst.index;
      dst.advance(12 * domainss);

      dst = dst.derive(domainsi);
      for (int i = 0; i < domainss; i++) {
        domains![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int domainsp = src.decNdrLong();
    maxCount = src.decNdrLong();

    if (domainsp != 0) {
      src = src.deferred;
      int domainss = src.decNdrLong();
      int domainsi = src.index;
      src.advance(12 * domainss);

      if (domains == null) {
        if (domainss < 0 || domainss > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        domains = List.generate(domainss, (index) => LsarpcTrustInformation());
      }
      src = src.derive(domainsi);
      for (int i = 0; i < domainss; i++) {
        domains![i].decode(src);
      }
    }
  }
}

class LsarpcTranslatedName extends NdrObject {
  int sidType = 0;
  RpcUnicodeString? name;
  int sidIndex = 0;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrShort(sidType);
    dst.encNdrShort(name!.length);
    dst.encNdrShort(name!.maximumLength);
    dst.encNdrReferent(name!.buffer, 1);
    dst.encNdrLong(sidIndex);

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
    sidType = src.decNdrShort();
    src.align(4);
    name ??= RpcUnicodeString();
    name!.length = src.decNdrShort();
    name!.maximumLength = src.decNdrShort();
    int nameBufferp = src.decNdrLong();
    sidIndex = src.decNdrLong();

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

class LsarpcTransNameArray extends NdrObject {
  int count = 0;
  List<LsarpcTranslatedName>? names;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(count);
    dst.encNdrReferent(names, 1);

    if (names != null) {
      dst = dst.deferred;
      int namess = count;
      dst.encNdrLong(namess);
      int namesi = dst.index;
      dst.advance(16 * namess);

      dst = dst.derive(namesi);
      for (int i = 0; i < namess; i++) {
        names![i].encode(dst);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    count = src.decNdrLong();
    int namesp = src.decNdrLong();

    if (namesp != 0) {
      src = src.deferred;
      int namess = src.decNdrLong();
      int namesi = src.index;
      src.advance(16 * namess);

      if (names == null) {
        if (namess < 0 || namess > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        names = List.generate(namess, (index) => LsarpcTranslatedName());
      }
      src = src.derive(namesi);
      for (int i = 0; i < namess; i++) {
        names![i].decode(src);
      }
    }
  }
}

class LsarpcClose extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x00;
  }

  int retval = 0;
  RpcPolicyHandle handle;

  LsarpcClose(this.handle);

  @override
  void encodeIn(NdrBuffer buf) {
    handle.encode(buf);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    handle.decode(buf);
    retval = buf.decNdrLong();
  }
}

class LsarpcQueryInformationPolicy extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x07;
  }

  int retval = 0;
  RpcPolicyHandle handle;
  int level;
  NdrObject info;

  LsarpcQueryInformationPolicy(
    this.handle,
    this.level,
    this.info,
  );

  @override
  void encodeIn(NdrBuffer buf) {
    handle.encode(buf);
    buf.encNdrShort(level);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    int infop = buf.decNdrLong();
    if (infop != 0) {
      buf.decNdrShort(); /* union discriminant */
      info.decode(buf);
    }
    retval = buf.decNdrLong();
  }
}

class LsarpcLookupSids extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x0f;
  }

  int retval = 0;
  RpcPolicyHandle handle;
  LsarpcSidArray sids;
  LsarpcRefDomainList? domains;
  LsarpcTransNameArray names;
  int level;
  int count;

  LsarpcLookupSids(
    this.handle,
    this.sids,
    this.domains,
    this.names,
    this.level,
    this.count,
  );

  @override
  void encodeIn(NdrBuffer buf) {
    handle.encode(buf);
    sids.encode(buf);
    names.encode(buf);
    buf.encNdrShort(level);
    buf.encNdrLong(count);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    int domainsp = buf.decNdrLong();
    if (domainsp != 0) {
      domains ??= LsarpcRefDomainList();
      domains!.decode(buf);
    }
    names.decode(buf);
    count = buf.decNdrLong();
    retval = buf.decNdrLong();
  }
}

class LsarpcOpenPolicy2 extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x2c;
  }

  int retval = 0;
  String? systemName;
  LsarpcObjectAttributes objectAttributes;
  int desiredAccess;
  RpcPolicyHandle policyHandle;

  LsarpcOpenPolicy2(this.systemName, this.objectAttributes, this.desiredAccess,
      this.policyHandle);

  @override
  void encodeIn(NdrBuffer buf) {
    buf.encNdrReferent(systemName, 1);
    if (systemName != null) {
      buf.encNdrString(systemName!);
    }
    objectAttributes.encode(buf);
    buf.encNdrLong(desiredAccess);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    policyHandle.decode(buf);
    retval = buf.decNdrLong();
  }
}

class LsarpcQueryInformationPolicy2 extends DcerpcMessage {
  @override
  int getOpnum() {
    return 0x2e;
  }

  int retval = 0;
  RpcPolicyHandle handle;
  int level;
  NdrObject info;

  LsarpcQueryInformationPolicy2(this.handle, this.level, this.info);

  @override
  void encodeIn(NdrBuffer buf) {
    handle.encode(buf);
    buf.encNdrShort(level);
  }

  @override
  void decodeOut(NdrBuffer buf) {
    int infop = buf.decNdrLong();
    if (infop != 0) {
      buf.decNdrShort(); /* union discriminant */
      info.decode(buf);
    }
    retval = buf.decNdrLong();
  }
}
