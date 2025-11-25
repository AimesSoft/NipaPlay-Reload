import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/crypto/crypto.dart';
import 'package:smb_connect/src/ntlmssp/av/av_flags.dart';
import 'package:smb_connect/src/ntlmssp/av/av_pair.dart';
import 'package:smb_connect/src/ntlmssp/av/av_pairs.dart';
import 'package:smb_connect/src/ntlmssp/av/av_single_host.dart';
import 'package:smb_connect/src/ntlmssp/av/av_target_name.dart';
import 'package:smb_connect/src/ntlmssp/av/av_timestamp.dart';
import 'package:smb_connect/src/ntlmssp/ntlm_flags.dart';
import 'package:smb_connect/src/ntlmssp/ntlm_message.dart';
import 'package:smb_connect/src/ntlmssp/type2_message.dart';
import 'package:smb_connect/src/smb/ntlm_util.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';
import 'package:smb_connect/src/utils/utf16le/utf16_le.dart';

/// Represents an NTLMSSP Type-3 message.
class Type3Message extends NtlmPacket {
  final Uint8List? lmResponse;
  final Uint8List? ntResponse;
  final String? domain;
  final String? user;
  final String? workstation;
  final Uint8List? masterKey;
  final Uint8List? sessionKey;
  Uint8List? mic;
  bool micRequired;

  /// Creates a Type-3 message with the specified parameters.
  Type3Message(
    int flags,
    this.lmResponse,
    this.ntResponse,
    this.domain,
    this.user,
    this.workstation, {
    this.masterKey,
    this.sessionKey,
    this.mic,
    this.micRequired = false,
  }) {
    super.flags = flags;
  }

  /// Creates a Type-3 message in response to the given Type-2 message.
  factory Type3Message.pass(
      Configuration config,
      Type2Message type2,
      String? targetName,
      String password,
      String? domain,
      String user,
      String? workstation,
      int flags,
      {bool nonAnonymous = false}) {
    // keep old behavior of anonymous auth when no password is provided
    return Type3Message.type2(config, type2, targetName, null, password, domain,
        user, workstation, flags, nonAnonymous);
  }

  /// Creates a Type-3 message in response to the given Type-2 message.
  factory Type3Message.passHash(
      Configuration config,
      Type2Message type2,
      String? targetName,
      Uint8List passwordHash,
      String domain,
      String user,
      String? workstation,
      int flags) {
    return Type3Message.type2(config, type2, targetName, passwordHash, null,
        domain, user, workstation, flags, true);
  }

  /// Creates a Type-3 message in response to the given Type-2 message.
  factory Type3Message.type2(
      Configuration config,
      Type2Message type2,
      String? targetName,
      Uint8List? passwordHash,
      String? password,
      String? domain,
      String user,
      String? workstation,
      int flags,
      bool nonAnonymous) {
    flags = flags | getDefaultFlags(config, type2: type2);

    if ((password == null && passwordHash == null) ||
        (!nonAnonymous && (password != null && password.isEmpty))) {
      return Type3Message(flags, null, null, domain, user, workstation);
    }

    passwordHash ??= NtlmUtil.getNTHash(password!);

    switch (Configuration.lanManCompatibility) {
      case 0:
      case 1:
        if (!NtlmPacket.getFlagStatic(
            flags, NtlmFlags.NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY)) {
          final lmResponse = getLMResponseFor(config, type2, password);
          final ntResponse = getNTResponsePassHash(type2, passwordHash);
          return Type3Message(
              flags, lmResponse, ntResponse, domain, user, workstation);
        } else {
          // NTLM2 Session Response

          Uint8List clientChallenge = config.random.nextBytes(24);
          clientChallenge.fill(start: 8, end: 24, value: 0x00);

          Uint8List ntlm2Response = NtlmUtil.getNTLM2Response(
              passwordHash, type2.challenge!, clientChallenge);

          final lmResponse = clientChallenge;
          final ntResponse = ntlm2Response;

          Uint8List sessionNonce = Uint8List(16);
          byteArrayCopy(
              src: type2.challenge!,
              srcOffset: 0,
              dst: sessionNonce,
              dstOffset: 0,
              length: 8);
          byteArrayCopy(
              src: clientChallenge,
              srcOffset: 0,
              dst: sessionNonce,
              dstOffset: 8,
              length: 8);

          MessageDigest md4 = Crypto.getMD4();
          md4.updateBuff(passwordHash);
          Uint8List userSessionKey = md4.digest();

          MessageDigest hmac = Crypto.getHMACT64(userSessionKey);
          hmac.updateBuff(sessionNonce);
          Uint8List ntlm2SessionKey = hmac.digest();

          if (NtlmPacket.getFlagStatic(
              flags, NtlmFlags.NTLMSSP_NEGOTIATE_KEY_EXCH)) {
            final masterKey = config.random.nextBytes(16);

            Uint8List exchangedKey = Uint8List(16);
            StreamCipher arcfour = Crypto.getArcfour(ntlm2SessionKey);
            arcfour.processBytes(masterKey, 0, 16, exchangedKey, 0);
            return Type3Message(
                flags, lmResponse, ntResponse, domain, user, workstation,
                masterKey: masterKey, sessionKey: exchangedKey);
          } else {
            return Type3Message(
                flags, lmResponse, ntResponse, domain, user, workstation,
                masterKey: ntlm2SessionKey);
          }
        }
      case 2:
        Uint8List? nt = getNTResponsePassHash(type2, passwordHash);
        return Type3Message(flags, nt, nt, domain, user, workstation);
      case 3:
      case 4:
      case 5:
        Uint8List? ntlmClientChallengeInfo = type2.targetInformation;
        List<AvPair>? avPairs = ntlmClientChallengeInfo != null
            ? AvPairs.decode(ntlmClientChallengeInfo)
            : null;

        // print("AvPairs: $avPairs");
        // if targetInfo has an MsvAvTimestamp
        // client should not send LmChallengeResponse
        Uint8List? lmResponse;
        bool haveTimestamp = AvPairs.contains(avPairs, AvPair.MsvAvTimestamp);
        if (!haveTimestamp) {
          Uint8List lmClientChallenge = config.random.nextBytes(8);
          lmResponse = getLMv2ResponsePassHash(
              type2, domain, user, passwordHash, lmClientChallenge);
        } else {
          lmResponse = Uint8List(24);
        }

        if (avPairs != null) {
          // make sure to set the TARGET_INFO flag as we are sending
          // setFlag(NtlmFlags.NTLMSSP_NEGOTIATE_TARGET_INFO, true);
          flags = NtlmPacket.setFlagStatic(
              flags, NtlmFlags.NTLMSSP_NEGOTIATE_TARGET_INFO, true);
        }

        Uint8List responseKeyNT =
            NtlmUtil.nTOWFv2Hash(domain!, user, passwordHash);
        Uint8List ntlmClientChallenge = config.random.nextBytes(8);

        int ts = (currentTimeMillis() +
                SmbConstants.MILLISECONDS_BETWEEN_1970_AND_1601) *
            10000;
        if (haveTimestamp) {
          ts = (AvPairs.get(avPairs!, AvPair.MsvAvTimestamp) as AvTimestamp)
              .getTimestamp();
        }

        final resPairs =
            _makeAvPairs(config, targetName, avPairs, haveTimestamp, ts, flags);
        final mic = resPairs.$2;
        final micRequired = mic != null;

        final ntResponse = getNTLMv2Response(
            type2, responseKeyNT, ntlmClientChallenge, resPairs.$1, ts);

        MessageDigest hmac = Crypto.getHMACT64(responseKeyNT);
        hmac.update(ntResponse!, 0, 16); // only first 16 ints of ntResponse
        Uint8List userSessionKey = hmac.digest();

        Uint8List masterKey;
        Uint8List? sessionKey;
        if (NtlmPacket.getFlagStatic(
            flags, NtlmFlags.NTLMSSP_NEGOTIATE_KEY_EXCH)) {
          masterKey = config.random.nextBytes(16);

          Uint8List encryptedKey = Uint8List(16);
          var rc4 = Crypto.getArcfour(userSessionKey);
          rc4.processBytes(masterKey, 0, 16, encryptedKey, 0);
          sessionKey = encryptedKey;
        } else {
          masterKey = userSessionKey;
        }
        return Type3Message(
            flags, lmResponse, ntResponse, domain, user, workstation,
            masterKey: masterKey,
            sessionKey: sessionKey,
            mic: mic,
            micRequired: micRequired);
      default:
        final lmResponse = getLMResponseFor(config, type2, password);
        final ntResponse = getNTResponsePassHash(type2, passwordHash);
        return Type3Message(
            flags, lmResponse, ntResponse, domain, user, workstation);
    }
  }

  static (Uint8List? pairs, Uint8List? mic) _makeAvPairs(
      Configuration config,
      String? targetName,
      List<AvPair>? serverAvPairs,
      bool haveServerTimestamp,
      int ts,
      int flags) {
    if (!Configuration.isEnforceSpnegoIntegrity && serverAvPairs == null) {
      return (null, null);
    } else {
      serverAvPairs ??= [];
    }
    Uint8List? mic;
    if (NtlmPacket.getFlagStatic(flags, NtlmFlags.NTLMSSP_NEGOTIATE_SIGN) &&
        (Configuration.isEnforceSpnegoIntegrity ||
            (haveServerTimestamp && !Configuration.isDisableSpnegoIntegrity))) {
      // should provide MIC
      // micRequired = true;
      mic = Uint8List(16);
      int curFlags = 0;
      AvFlags? cur = AvPairs.get(serverAvPairs, AvPair.MsvAvFlags) as AvFlags?;
      if (cur != null) {
        curFlags = cur.getFlags();
      }
      curFlags |= 0x2; // MAC present
      AvPairs.replace(serverAvPairs, AvFlags.encode(curFlags));
    }

    AvPairs.replace(serverAvPairs, AvTimestamp.encode(ts));

    if (targetName != null) {
      AvPairs.replace(serverAvPairs, AvTargetName.encode(targetName));
    }

    // possibly add channel bindings
    AvPairs.replace(serverAvPairs, AvPair(0xa, Uint8List(16)));
    AvPairs.replace(serverAvPairs, AvSingleHost.cfg(config));
    var res = AvPairs.encode(serverAvPairs);
    return (res, mic);
  }

  /// Sets the MIC
  void setupMIC(Uint8List type1, Uint8List type2) {
    Uint8List? sk = masterKey;
    if (sk == null) {
      return;
    }
    MessageDigest mac = Crypto.getHMACT64(sk);
    mac.updateBuff(type1);
    mac.updateBuff(type2);
    Uint8List type3 = toByteArray();
    mac.updateBuff(type3);
    mic = mac.digest();
  }

  /// Returns the default flags for a Type-3 message created in response
  /// to the given Type-2 message in the current environment.
  static int getDefaultFlags(Configuration config, {Type2Message? type2}) {
    if (type2 == null) {
      return NtlmFlags.NTLMSSP_NEGOTIATE_NTLM |
          NtlmFlags.NTLMSSP_NEGOTIATE_VERSION |
          (config.isUseUnicode
              ? NtlmFlags.NTLMSSP_NEGOTIATE_UNICODE
              : NtlmFlags.NTLMSSP_NEGOTIATE_OEM);
    }
    int flags =
        NtlmFlags.NTLMSSP_NEGOTIATE_NTLM | NtlmFlags.NTLMSSP_NEGOTIATE_VERSION;
    flags |= type2.getFlag(NtlmFlags.NTLMSSP_NEGOTIATE_UNICODE)
        ? NtlmFlags.NTLMSSP_NEGOTIATE_UNICODE
        : NtlmFlags.NTLMSSP_NEGOTIATE_OEM;
    return flags;
  }

  /// whether a MIC should be calulated
  bool isMICRequired() {
    return micRequired;
  }

  @override
  Uint8List toByteArray() {
    int size = 64;
    bool unicode = getFlag(NtlmFlags.NTLMSSP_NEGOTIATE_UNICODE);
    var oemCp = unicode ? utf16le : NtlmPacket.getOEMEncoding();

    String? domainName = domain;
    Uint8List? domainBytes;
    if (domainName != null && domainName.isNotEmpty) {
      domainBytes = oemCp.encode(domainName).toUint8List();
      size += domainBytes.length;
    }

    String? userName = user;
    Uint8List? userBytes;
    if (userName != null && userName.isNotEmpty) {
      userBytes = unicode
          ? userName.getUNIBytes()
          : oemCp.encode(userName.toUpperCase()).toUint8List();
      size += userBytes.length;
    }

    String? workstationName = workstation;
    Uint8List? workstationBytes;
    if (workstationName != null && workstationName.isNotEmpty) {
      workstationBytes = unicode
          ? workstationName.getUNIBytes()
          : oemCp.encode(workstationName.toUpperCase()).toUint8List();
      size += workstationBytes.length;
    }

    Uint8List? micBytes = mic;
    if (micBytes != null) {
      size += 8 + 16;
    } else if (getFlag(NtlmFlags.NTLMSSP_NEGOTIATE_VERSION)) {
      size += 8;
    }

    Uint8List? lmResponseBytes = lmResponse;
    size += (lmResponseBytes != null) ? lmResponseBytes.length : 0;

    Uint8List? ntResponseBytes = ntResponse;
    size += (ntResponseBytes != null) ? ntResponseBytes.length : 0;

    Uint8List? sessionKeyBytes = sessionKey;
    size += (sessionKeyBytes != null) ? sessionKeyBytes.length : 0;

    Uint8List type3 = Uint8List(size);
    int pos = 0;

    byteArrayCopy(
        src: NtlmPacket.NTLMSSP_HEADER,
        srcOffset: 0,
        dst: type3,
        dstOffset: 0,
        length: 8);
    pos += 8;

    NtlmPacket.writeULong(type3, pos, NtlmPacket.NTLMSSP_TYPE3);
    pos += 4;

    int lmOff = NtlmPacket.writeSecurityBuffer(type3, 12, lmResponseBytes);
    pos += 8;
    int ntOff = NtlmPacket.writeSecurityBuffer(type3, 20, ntResponseBytes);
    pos += 8;
    int domOff = NtlmPacket.writeSecurityBuffer(type3, 28, domainBytes);
    pos += 8;
    int userOff = NtlmPacket.writeSecurityBuffer(type3, 36, userBytes);
    pos += 8;
    int wsOff = NtlmPacket.writeSecurityBuffer(type3, 44, workstationBytes);
    pos += 8;
    int skOff = NtlmPacket.writeSecurityBuffer(type3, 52, sessionKeyBytes);
    pos += 8;

    NtlmPacket.writeULong(type3, pos, flags);
    pos += 4;

    if (getFlag(NtlmFlags.NTLMSSP_NEGOTIATE_VERSION)) {
      byteArrayCopy(
          src: NtlmPacket.NTLMSSP_VERSION,
          srcOffset: 0,
          dst: type3,
          dstOffset: pos,
          length: NtlmPacket.NTLMSSP_VERSION.length);
      pos += NtlmPacket.NTLMSSP_VERSION.length;
    } else if (micBytes != null) {
      pos += NtlmPacket.NTLMSSP_VERSION.length;
    }

    if (micBytes != null) {
      byteArrayCopy(
          src: micBytes, srcOffset: 0, dst: type3, dstOffset: pos, length: 16);
      pos += 16;
    }

    pos += NtlmPacket.writeSecurityBufferContent(
        type3, pos, lmOff, lmResponseBytes);
    pos += NtlmPacket.writeSecurityBufferContent(
        type3, pos, ntOff, ntResponseBytes);
    pos +=
        NtlmPacket.writeSecurityBufferContent(type3, pos, domOff, domainBytes);
    pos +=
        NtlmPacket.writeSecurityBufferContent(type3, pos, userOff, userBytes);
    pos += NtlmPacket.writeSecurityBufferContent(
        type3, pos, wsOff, workstationBytes);
    pos += NtlmPacket.writeSecurityBufferContent(
        type3, pos, skOff, sessionKeyBytes);

    return type3;
  }

  @override
  String toString() {
    return "Type3Message[domain=$domain,user=$user,workstation=$workstation,lmResponse=${lmResponse == null ? "null" : "<${lmResponse!.toHexString()}>"},ntResponse=${ntResponse == null ? "null" : "<${ntResponse!.toHexString()}>"},sessionKey=${sessionKey == null ? "null" : "<${sessionKey!.toHexString()}>"},flags=0x${Hexdump.toHexString(flags, 8)}]";
  }

  /// Constructs the LanManager response to the given Type-2 message using
  /// the supplied password.
  static Uint8List? getLMResponseFor(
      Configuration config, Type2Message? type2, String? password) {
    if (type2 == null || password == null) {
      return null;
    }
    return NtlmUtil.getPreNTLMResponse(config, password, type2.challenge!);
  }

  // static Uint8List? getLMv2ResponsePass(Type2Message type2, String domain,
  //     String user, String? password, Uint8List clientChallenge) {
  //   if (password == null) {
  //     return null;
  //   }
  //   return getLMv2ResponsePassHash(
  //       type2, domain, user, NtlmUtil.getNTHash(password), clientChallenge);
  // }

  static Uint8List? getLMv2ResponsePassHash(Type2Message? type2, String? domain,
      String? user, Uint8List? passwordHash, Uint8List? clientChallenge) {
    if (type2 == null ||
        domain == null ||
        user == null ||
        passwordHash == null ||
        clientChallenge == null) {
      return null;
    }
    return NtlmUtil.getLMv2ResponseHash(
        domain, user, passwordHash, type2.challenge!, clientChallenge);
  }

  static Uint8List? getNTLMv2Response(
      Type2Message? type2,
      Uint8List? responseKeyNT,
      Uint8List? clientChallenge,
      Uint8List? clientChallengeInfo,
      int ts) {
    if (type2 == null || responseKeyNT == null || clientChallenge == null) {
      return null;
    }
    return NtlmUtil.getNTLMv2Response(responseKeyNT, type2.challenge!,
        clientChallenge, ts, clientChallengeInfo);
  }

  /// Constructs the NT response to the given Type-2 message using
  /// the supplied password.
  // static Uint8List? getNTResponsePass(Type2Message type2, String? password) {
  //   if (password == null) {
  //     return null;
  //   }
  //   return getNTResponsePassHash(type2, NtlmUtil.getNTHash(password));
  // }

  /// Constructs the NT response to the given Type-2 message using
  /// the supplied password.
  static Uint8List? getNTResponsePassHash(
      Type2Message? type2, Uint8List? passwordHash) {
    if (type2 == null || passwordHash == null) {
      return null;
    }
    return NtlmUtil.getNTLMResponseHash(passwordHash, type2.challenge!);
  }

  factory Type3Message.parse(Uint8List material) {
    int pos = 0;
    for (int i = 0; i < 8; i++) {
      if (material[i] != NtlmPacket.NTLMSSP_HEADER[i]) {
        throw SmbIOException("Not an NTLMSSP message.");
      }
    }

    pos += 8;
    if (NtlmPacket.readULong(material, pos) != NtlmPacket.NTLMSSP_TYPE3) {
      throw SmbIOException("Not a Type 3 message.");
    }
    pos += 4;

    Uint8List lmResponseBytes = NtlmPacket.readSecurityBuffer(material, pos);
    // lmResponse = lmResponseBytes;
    int lmResponseOffset = NtlmPacket.readULong(material, pos + 4);
    pos += 8;

    Uint8List ntResponseBytes = NtlmPacket.readSecurityBuffer(material, pos);
    // ntResponse = ntResponseBytes;
    int ntResponseOffset = NtlmPacket.readULong(material, pos + 4);
    pos += 8;

    Uint8List domainBytes = NtlmPacket.readSecurityBuffer(material, pos);
    int domainOffset = NtlmPacket.readULong(material, pos + 4);
    pos += 8;

    Uint8List userBytes = NtlmPacket.readSecurityBuffer(material, pos);
    int userOffset = NtlmPacket.readULong(material, pos + 4);
    pos += 8;

    Uint8List workstationBytes = NtlmPacket.readSecurityBuffer(material, pos);
    int workstationOffset = NtlmPacket.readULong(material, pos + 4);
    pos += 8;

    bool end = false;
    int flags;
    Encoding charset;
    Uint8List? sessionKey;
    if (lmResponseOffset < pos + 12 ||
        ntResponseOffset < pos + 12 ||
        domainOffset < pos + 12 ||
        userOffset < pos + 12 ||
        workstationOffset < pos + 12) {
      // no room for SK/Flags
      flags =
          NtlmFlags.NTLMSSP_NEGOTIATE_NTLM | NtlmFlags.NTLMSSP_NEGOTIATE_OEM;
      charset = NtlmPacket.getOEMEncoding();
      end = true;
    } else {
      sessionKey = NtlmPacket.readSecurityBuffer(material, pos);
      pos += 8;

      flags = NtlmPacket.readULong(material, pos);
      pos += 4;

      charset = ((flags & NtlmFlags.NTLMSSP_NEGOTIATE_UNICODE) != 0)
          ? NtlmPacket.UNI_ENCODING
          : NtlmPacket.getOEMEncoding();
    }

    final domain = charset.decode(domainBytes);
    final user = charset.decode(userBytes);
    final workstation = charset.decode(workstationBytes);

    int micLen = pos + 24; // Version + MIC
    if (end ||
        lmResponseOffset < micLen ||
        ntResponseOffset < micLen ||
        domainOffset < micLen ||
        userOffset < micLen ||
        workstationOffset < micLen) {
      return Type3Message(
          flags, lmResponseBytes, ntResponseBytes, domain, user, workstation,
          sessionKey: sessionKey);
    } else {
      pos += 8; // Version

      Uint8List mic = Uint8List(16);
      byteArrayCopy(
          src: material,
          srcOffset: pos,
          dst: mic,
          dstOffset: 0,
          length: mic.length);
      return Type3Message(
          flags, lmResponseBytes, ntResponseBytes, domain, user, workstation,
          sessionKey: sessionKey, mic: mic);
    }
  }
}
