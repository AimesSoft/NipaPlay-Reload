import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1/primitives/asn1_object_identifier.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/crypto/crypto.dart';
import 'package:smb_connect/src/fixes/atomic_integer.dart';
import 'package:smb_connect/src/ntlmssp/type3_message.dart';
import 'package:smb_connect/src/smb/ntlm_nt_hash_authenticator.dart';
import 'package:smb_connect/src/smb/ntlm_password_authenticator.dart';
import 'package:smb_connect/src/smb/ssp_context.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

import '../ntlmssp/ntlm_flags.dart';
import '../ntlmssp/type1_message.dart';
import '../ntlmssp/type2_message.dart';

///
/// For initiating NTLM authentication (including NTLMv2). If you want to add NTLMv2 authentication support to something
/// this is what you want to use
///
class NtlmContext implements SSPContext {
  static const String S2C_SIGN_CONSTANT =
      "session key to server-to-client signing key magic constant";
  static const String S2C_SEAL_CONSTANT =
      "session key to server-to-client sealing key magic constant";

  static const String C2S_SIGN_CONSTANT =
      "session key to client-to-server signing key magic constant";
  static const String C2S_SEAL_CONSTANT =
      "session key to client-to-server sealing key magic constant";

  static ASN1ObjectIdentifier NTLMSSP_OID =
      ASN1ObjectIdentifier.fromIdentifierString("1.3.6.1.4.1.311.2.2.10");

  final NtlmPasswordAuthenticator _auth;
  int _ntlmsspFlags;
  final String? _workstation;
  bool _isEstablished = false;
  Uint8List? _serverChallenge;
  Uint8List? _masterKey;
  // String? _netbiosName;

  final bool _requireKeyExchange;
  final _signSequence = AtomicInteger(0);
  final _verifySequence = AtomicInteger(0);
  int _state = 1;

  Configuration config;

  String? targetName;
  Uint8List? _type1Bytes;

  Uint8List? _signKey;
  Uint8List? _verifyKey;
  Uint8List? _sealClientKey;
  Uint8List? _sealServerKey;

  StreamCipher? _sealClientHandle;
  StreamCipher? _sealServerHandle;

  NtlmContext(this.config, this._auth, this._requireKeyExchange)
      : _ntlmsspFlags = NtlmFlags.NTLMSSP_REQUEST_TARGET |
            NtlmFlags.NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY |
            NtlmFlags.NTLMSSP_NEGOTIATE_128,
        _workstation = Configuration.netbiosHostname {
    if (!_auth.isAnonymous()) {
      _ntlmsspFlags |= NtlmFlags.NTLMSSP_NEGOTIATE_SIGN |
          NtlmFlags.NTLMSSP_NEGOTIATE_ALWAYS_SIGN |
          NtlmFlags.NTLMSSP_NEGOTIATE_KEY_EXCH;
    } else if (_auth.isGuest()) {
      _ntlmsspFlags |= NtlmFlags.NTLMSSP_NEGOTIATE_KEY_EXCH;
    } else {
      _ntlmsspFlags |= NtlmFlags.NTLMSSP_NEGOTIATE_ANONYMOUS;
    }
  }

  @override
  List<ASN1ObjectIdentifier> getSupportedMechs() {
    return [NTLMSSP_OID];
  }

  @override
  String toString() {
    String ret =
        "NtlmContext[auth=$_auth,ntlmsspFlags=0x${Hexdump.toHexString(_ntlmsspFlags, 8)},workstation=$_workstation,isEstablished=$_isEstablished,state=$_state,serverChallenge=";
    if (_serverChallenge == null) {
      ret += "null";
    } else {
      ret += Hexdump.toHexStringBuff(_serverChallenge);
    }
    ret += ",signingKey=";
    if (_masterKey == null) {
      ret += "null";
    } else {
      ret += Hexdump.toHexStringBuff(_masterKey);
    }
    ret += "]";
    return ret;
  }

  @override
  int getFlags() {
    return 0;
  }

  @override
  bool isSupported(ASN1ObjectIdentifier mechanism) {
    return NTLMSSP_OID.objectIdentifierAsString ==
        mechanism.objectIdentifierAsString;
  }

  @override
  bool isPreferredMech(ASN1ObjectIdentifier? mechanism) {
    return _auth.isPreferredMech(mechanism);
  }

  @override
  bool isEstablished() {
    return _isEstablished;
  }

  Uint8List? getServerChallenge() {
    return _serverChallenge;
  }

  @override
  Uint8List? getSigningKey() {
    return _masterKey;
  }

  // @override
  // String? getNetbiosName() {
  //   return _netbiosName;
  // }

  @override
  Uint8List initSecContext(Uint8List token, int offset, int len) {
    switch (_state) {
      case 1:
        return makeNegotiate(token);
      case 2:
        return makeAuthenticate(token);
      default:
        throw SmbException("Invalid state");
    }
  }

  @protected
  Uint8List makeAuthenticate(Uint8List token) {
    try {
      Type2Message msg2 = Type2Message.parse(token);
      _serverChallenge = msg2.challenge;

      if (_requireKeyExchange) {
        if (Configuration.isEnforceSpnegoIntegrity &&
            (!msg2.getFlag(NtlmFlags.NTLMSSP_NEGOTIATE_KEY_EXCH) ||
                !msg2.getFlag(
                    NtlmFlags.NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY))) {
          throw SmbUnsupportedOperationException(
              "Server does not support extended NTLMv2 key exchange");
        }

        if (!msg2.getFlag(NtlmFlags.NTLMSSP_NEGOTIATE_128)) {
          throw SmbUnsupportedOperationException(
              "Server does not support 128-bit keys");
        }
      }

      _ntlmsspFlags &= msg2.flags;
      Type3Message msg3 = createType3Message(msg2);
      msg3.setupMIC(_type1Bytes!, token);

      Uint8List out = msg3.toByteArray();
      _masterKey = msg3.masterKey;

      if (_masterKey != null &&
          (_ntlmsspFlags &
                  NtlmFlags.NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY) !=
              0) {
        initSessionSecurity(_masterKey!);
      }

      _isEstablished = true;
      _state++;
      return out;
    } catch (e) {
      //SmbException
      if (e is SmbException) {
        rethrow;
      }
      throw SmbException(e.toString(), e);
    }
  }

  @protected
  Type3Message createType3Message(Type2Message msg2) {
    if (_auth is NtlmNtHashAuthenticator) {
      return Type3Message.passHash(
          config,
          msg2,
          targetName,
          _auth.getNTHash(),
          _auth.getUserDomain(),
          _auth.getUsername(),
          _workstation,
          _ntlmsspFlags);
    }

    return Type3Message.pass(
        config,
        msg2,
        targetName,
        _auth.isGuest() ? Configuration.guestPassword : _auth.getPassword(),
        _auth.isGuest() ? null : _auth.getUserDomain(),
        _auth.isGuest() ? Configuration.guestUsername : _auth.getUsername(),
        _workstation,
        _ntlmsspFlags,
        nonAnonymous: _auth.isGuest() || !_auth.isAnonymous());
  }

  @protected
  Uint8List makeNegotiate(Uint8List token) {
    Type1Message msg1 = Type1Message(
        config, _ntlmsspFlags, _auth.getUserDomain(), _workstation);
    Uint8List out = msg1.toByteArray();
    _type1Bytes = out;
    _state++;
    return out;
  }

  @protected
  void initSessionSecurity(Uint8List mk) {
    _signKey = _deriveKey(mk, C2S_SIGN_CONSTANT);
    _verifyKey = _deriveKey(mk, S2C_SIGN_CONSTANT);

    _sealClientKey = _deriveKey(mk, C2S_SEAL_CONSTANT);
    _sealClientHandle = Crypto.getArcfour(_sealClientKey!);

    _sealServerKey = _deriveKey(mk, S2C_SEAL_CONSTANT);
    _sealServerHandle = Crypto.getArcfour(_sealServerKey!);
  }

  static Uint8List _deriveKey(Uint8List masterKey, String cnst) {
    MessageDigest md5 = Crypto.getMD5();
    md5.updateBuff(masterKey);
    md5.updateBuff(cnst.getASCIIBytes());
    md5.updateByte(0);
    return md5.digest();
  }

  @override
  bool supportsIntegrity() {
    return true;
  }

  @override
  bool isMICAvailable() {
    return !_auth.isGuest() && _signKey != null && _verifyKey != null;
  }

  @override
  Uint8List calculateMIC(Uint8List data) {
    Uint8List? sk = _signKey;
    if (sk == null) {
      throw SmbConnectException("Signing is not initialized");
    }

    int seqNum = _signSequence.getAndIncrement();
    Uint8List seqBytes = Uint8List(4);
    SMBUtil.writeInt4(seqNum, seqBytes, 0);

    MessageDigest mac = Crypto.getHMACT64(sk);
    mac.updateBuff(seqBytes); // sequence
    mac.updateBuff(data); // data
    Uint8List dgst = mac.digest();
    Uint8List trunc = Uint8List(8);
    byteArrayCopy(src: dgst, srcOffset: 0, dst: trunc, dstOffset: 0, length: 8);

    if ((_ntlmsspFlags & NtlmFlags.NTLMSSP_NEGOTIATE_KEY_EXCH) != 0) {
      try {
        trunc = _sealClientHandle!.process(trunc);
      } catch (e) {
        //GeneralSecurityException
        throw SmbConnectException("Failed to encrypt MIC", e);
      }
    }

    Uint8List sig = Uint8List(16);
    SMBUtil.writeInt4(1, sig, 0); // version
    byteArrayCopy(
        src: trunc,
        srcOffset: 0,
        dst: sig,
        dstOffset: 4,
        length: 8); // checksum
    SMBUtil.writeInt4(seqNum, sig, 12); // seqNum

    return sig;
  }

  @override
  void verifyMIC(Uint8List data, Uint8List mic) {
    Uint8List? sk = _verifyKey;
    if (sk == null) {
      throw SmbConnectException("Signing is not initialized");
    }

    int ver = SMBUtil.readInt4(mic, 0);
    if (ver != 1) {
      throw SmbUnsupportedOperationException("Invalid signature version");
    }

    MessageDigest mac = Crypto.getHMACT64(sk);
    int seq = SMBUtil.readInt4(mic, 12);
    mac.update(mic, 12, 4); // sequence
    Uint8List dgst = mac.process(data);
    Uint8List trunc = dgst.sublist(0, 8);

    bool encrypted =
        (_ntlmsspFlags & NtlmFlags.NTLMSSP_NEGOTIATE_KEY_EXCH) != 0;
    if (encrypted) {
      try {
        trunc = _sealServerHandle!.process(trunc);
      } catch (e) {
        //GeneralSecurityException
        throw SmbConnectException("Failed to decrypt MIC", e);
      }
    }

    int expectSeq = _verifySequence.getAndIncrement();
    if (expectSeq != seq) {
      throw SmbConnectException(
          "Invalid MIC sequence, expect $expectSeq have $seq");
    }

    Uint8List verify = Uint8List(8);
    byteArrayCopy(src: mic, srcOffset: 4, dst: verify, dstOffset: 0, length: 8);
    if (!isEqualMessageDigest(trunc, verify)) {
      throw SmbConnectException("Invalid MIC");
    }
  }

  @override
  void dispose() {
    _isEstablished = false;
    _sealClientHandle = null;
    _sealServerHandle = null;
    _sealClientKey = null;
    _sealServerKey = null;
    _masterKey = null;
    _signKey = null;
    _verifyKey = null;
    _type1Bytes = null;
  }
}
