import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/ntlmssp/ntlm_flags.dart';
import 'package:smb_connect/src/ntlmssp/ntlm_message.dart';
import 'package:smb_connect/src/utils/extensions.dart';

///
/// Represents an NTLMSSP Type-1 message.
///
class Type1Message extends NtlmPacket {
  final String? suppliedDomain;
  final String? suppliedWorkstation;

  Type1Message.supplied(
      this.suppliedDomain, this.suppliedWorkstation, int flags) {
    this.flags = flags;
  }

  /// Creates a Type-1 message with the specified parameters.
  Type1Message(Configuration config, int flags, this.suppliedDomain,
      this.suppliedWorkstation) {
    this.flags = flags | getDefaultFlags(config);
  }

  /// Returns the default flags for a generic Type-1 message in the
  /// current environment.
  static int getDefaultFlags(Configuration config) {
    return NtlmFlags.NTLMSSP_NEGOTIATE_NTLM |
        NtlmFlags.NTLMSSP_NEGOTIATE_VERSION |
        (config.isUseUnicode
            ? NtlmFlags.NTLMSSP_NEGOTIATE_UNICODE
            : NtlmFlags.NTLMSSP_NEGOTIATE_OEM);
  }

  @override
  Uint8List toByteArray() {
    int flags = this.flags;
    int size =
        8 * 4 + ((flags & NtlmFlags.NTLMSSP_NEGOTIATE_VERSION) != 0 ? 8 : 0);

    Uint8List domain = Uint8List(0);
    String? suppliedDomainString = suppliedDomain;
    if ((flags & NtlmFlags.NTLMSSP_NEGOTIATE_VERSION) == 0 &&
        suppliedDomainString != null &&
        suppliedDomainString.isNotEmpty) {
      flags |= NtlmFlags.NTLMSSP_NEGOTIATE_OEM_DOMAIN_SUPPLIED;
      domain = NtlmPacket.getOEMEncoding()
          .encode(suppliedDomainString.toUpperCase());
      domain = NtlmPacket.getOEMEncoding()
          .encode(suppliedDomainString.toUpperCase());
      size += domain.length;
    } else {
      flags &= (NtlmFlags.NTLMSSP_NEGOTIATE_OEM_DOMAIN_SUPPLIED ^ 0xffffffff);
    }

    Uint8List workstation = Uint8List(0);
    String? suppliedWorkstationString = suppliedWorkstation;
    if ((flags & NtlmFlags.NTLMSSP_NEGOTIATE_VERSION) == 0 &&
        suppliedWorkstationString != null &&
        suppliedWorkstationString.isNotEmpty) {
      flags |= NtlmFlags.NTLMSSP_NEGOTIATE_OEM_WORKSTATION_SUPPLIED;
      workstation = NtlmPacket.getOEMEncoding()
          .encode(suppliedWorkstationString.toUpperCase());
      workstation = NtlmPacket.getOEMEncoding()
          .encode(suppliedWorkstationString.toUpperCase());
      size += workstation.length;
    } else {
      flags &=
          (NtlmFlags.NTLMSSP_NEGOTIATE_OEM_WORKSTATION_SUPPLIED ^ 0xffffffff);
    }

    Uint8List resBuff = Uint8List(size);
    int pos = 0;

    byteArrayCopy(
        src: NtlmPacket.NTLMSSP_HEADER,
        srcOffset: 0,
        dst: resBuff,
        dstOffset: 0);
    pos += NtlmPacket.NTLMSSP_HEADER.length;

    NtlmPacket.writeULong(resBuff, pos, NtlmPacket.NTLMSSP_TYPE1);
    pos += 4;

    NtlmPacket.writeULong(resBuff, pos, flags);
    pos += 4;

    int domOffOff = NtlmPacket.writeSecurityBuffer(resBuff, pos, domain);
    pos += 8;

    int wsOffOff = NtlmPacket.writeSecurityBuffer(resBuff, pos, workstation);
    pos += 8;

    if ((flags & NtlmFlags.NTLMSSP_NEGOTIATE_VERSION) != 0) {
      byteArrayCopy(
          src: NtlmPacket.NTLMSSP_VERSION,
          srcOffset: 0,
          dst: resBuff,
          dstOffset: pos,
          length: NtlmPacket.NTLMSSP_VERSION.length);
      pos += NtlmPacket.NTLMSSP_VERSION.length;
    }

    pos +=
        NtlmPacket.writeSecurityBufferContent(resBuff, pos, domOffOff, domain);
    pos += NtlmPacket.writeSecurityBufferContent(
        resBuff, pos, wsOffOff, workstation);
    return resBuff;
  }

  @override
  String toString() {
    return "Type1Message[suppliedDomain=$suppliedDomain,suppliedWorkstation=$suppliedWorkstation,flags=0x${flags.toRadixString(16)}]";
  }

  factory Type1Message.parse(Uint8List material) {
    int pos = 0;
    for (int i = 0; i < 8; i++) {
      if (material[i] != NtlmPacket.NTLMSSP_HEADER[i]) {
        throw SmbIOException("Not an NTLMSSP message.");
      }
    }
    pos += 8;

    if (NtlmPacket.readULong(material, pos) != NtlmPacket.NTLMSSP_TYPE1) {
      throw SmbIOException("Not a Type 1 message.");
    }
    pos += 4;

    int flags = NtlmPacket.readULong(material, pos);
    pos += 4;

    String suppliedDomain = "";
    if ((flags & NtlmFlags.NTLMSSP_NEGOTIATE_OEM_DOMAIN_SUPPLIED) != 0) {
      Uint8List domain = NtlmPacket.readSecurityBuffer(material, pos);
      suppliedDomain = NtlmPacket.getOEMEncoding().decode(domain);
    }
    pos += 8;
    String suppliedWorkstation = "";
    if ((flags & NtlmFlags.NTLMSSP_NEGOTIATE_OEM_WORKSTATION_SUPPLIED) != 0) {
      Uint8List workstation = NtlmPacket.readSecurityBuffer(material, pos);
      suppliedWorkstation = NtlmPacket.getOEMEncoding().decode(workstation);
    }
    pos += 8;
    return Type1Message.supplied(suppliedDomain, suppliedWorkstation, flags);
  }
}
