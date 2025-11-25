///
/// 2.2.2.5 NEGOTIATE (flags)
/// During NTLM authentication, each of the following flags is a possible value
/// of the NegotiateFlags field of the NEGOTIATE_MESSAGE, CHALLENGE_MESSAGE,
/// and AUTHENTICATE_MESSAGE, unless otherwise noted. These flags define client
/// or server NTLM capabilities supported by the sender.
///
/// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/99d90ff4-957f-4c8a-80e4-5bfe5a9a9832?redirectedfrom=MSDN
abstract class NtlmFlags {
  /// If set, requests Unicode character set encoding.
  static const int NTLMSSP_NEGOTIATE_UNICODE = 0x00000001;

  /// If set, requests OEM character set encoding.
  static const int NTLMSSP_NEGOTIATE_OEM = 0x00000002;

  /// If set, a TargetName field of the CHALLENGE_MESSAGE (section 2.2.1.2)
  /// MUST be supplied. An alternate name for this field is
  /// NTLMSSP_REQUEST_TARGET.
  static const int NTLMSSP_REQUEST_TARGET = 0x00000004;

  /// If set, requests session key negotiation for message signatures. If the
  /// client sends NTLMSSP_NEGOTIATE_SIGN to the server in the
  /// NEGOTIATE_MESSAGE, the server MUST return NTLMSSP_NEGOTIATE_SIGN to the
  /// client in the CHALLENGE_MESSAGE. An alternate name for this field is
  /// NTLMSSP_NEGOTIATE_SIGN.
  static const int NTLMSSP_NEGOTIATE_SIGN = 0x00000010;

  /// If set, requests session key negotiation for message confidentiality. If
  /// the client sends NTLMSSP_NEGOTIATE_SEAL to the server in the
  /// NEGOTIATE_MESSAGE, the server MUST return NTLMSSP_NEGOTIATE_SEAL to the
  /// client in the CHALLENGE_MESSAGE. Clients and servers that set
  /// NTLMSSP_NEGOTIATE_SEAL SHOULD always set NTLMSSP_NEGOTIATE_56 and
  /// NTLMSSP_NEGOTIATE_128, if they are supported. An alternate name for this
  /// field is NTLMSSP_NEGOTIATE_SEAL.
  static const int NTLMSSP_NEGOTIATE_SEAL = 0x00000020;

  /// If set, requests connectionless authentication. If
  /// NTLMSSP_NEGOTIATE_DATAGRAM is set, then NTLMSSP_NEGOTIATE_KEY_EXCH MUST
  /// always be set in the AUTHENTICATE_MESSAGE to the server and the
  /// CHALLENGE_MESSAGE to the client. An alternate name for this field is
  /// NTLMSSP_NEGOTIATE_DATAGRAM.
  static const int NTLMSSP_NEGOTIATE_DATAGRAM = 0x00000040;

  /// If set, requests LAN Manager (LM) session key computation.
  /// NTLMSSP_NEGOTIATE_LM_KEY and NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY
  /// are mutually exclusive. If both NTLMSSP_NEGOTIATE_LM_KEY and
  /// NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY are requested,
  /// NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY alone MUST be returned to the
  /// client. NTLM v2 authentication session key generation MUST be supported by
  /// both the client and the DC in order to be used, and extended session
  /// security signing and sealing requires support from the client and the
  /// server to be used. An alternate name for this field is
  /// NTLMSSP_NEGOTIATE_LM_KEY.
  static const int NTLMSSP_NEGOTIATE_LM_KEY = 0x00000080;

  // /// ??? According to spec this is a reserved bit and must be set to zero
  // static const int NTLMSSP_NEGOTIATE_NETWARE = 0x00000100;

  /// If set, requests usage of the NTLM v1 session security protocol.
  /// NTLMSSP_NEGOTIATE_NTLM MUST be set in the NEGOTIATE_MESSAGE to the
  /// server and the CHALLENGE_MESSAGE to the client.
  static const int NTLMSSP_NEGOTIATE_NTLM = 0x00000200;

  /// If set, the connection SHOULD be anonymous
  static const int NTLMSSP_NEGOTIATE_ANONYMOUS = 0x00000800;

  /// If set, the domain name is provided
  static const int NTLMSSP_NEGOTIATE_OEM_DOMAIN_SUPPLIED = 0x00001000;

  /// This flag indicates whether the Workstation field is present. If this flag
  /// is not set, the Workstation field MUST be ignored. If this flag is set,
  /// the length of the Workstation field specifies whether the workstation name
  /// is nonempty or not.
  static const int NTLMSSP_NEGOTIATE_OEM_WORKSTATION_SUPPLIED = 0x00002000;

  /// f set, a session key is generated regardless of the states of
  /// NTLMSSP_NEGOTIATE_SIGN and NTLMSSP_NEGOTIATE_SEAL. A session key MUST
  /// always exist to generate the MIC (section 3.1.5.1.2) in the authenticate
  /// message. NTLMSSP_NEGOTIATE_ALWAYS_SIGN MUST be set in the
  /// NEGOTIATE_MESSAGE to the server and the CHALLENGE_MESSAGE to the client.
  /// NTLMSSP_NEGOTIATE_ALWAYS_SIGN is overridden by NTLMSSP_NEGOTIATE_SIGN and
  /// NTLMSSP_NEGOTIATE_SEAL, if they are supported.
  static const int NTLMSSP_NEGOTIATE_ALWAYS_SIGN = 0x00008000;

  /// If set, TargetName MUST be a domain name. The data corresponding to this
  /// flag is provided by the server in the TargetName field of the
  /// CHALLENGE_MESSAGE. If set, then NTLMSSP_TARGET_TYPE_SERVER MUST NOT be
  /// set. This flag MUST be ignored in the NEGOTIATE_MESSAGE and the
  /// AUTHENTICATE_MESSAGE.
  static const int NTLMSSP_TARGET_TYPE_DOMAIN = 0x00010000;

  /// If set, TargetName MUST be a server name. The data corresponding to this
  /// flag is provided by the server in the TargetName field of the
  /// CHALLENGE_MESSAGE. If this bit is set, then
  /// NTLMSSP_TARGET_TYPE_DOMAIN MUST NOT be set. This flag MUST be ignored in
  /// the NEGOTIATE_MESSAGE and the AUTHENTICATE_MESSAGE. An alternate name for
  /// this field is NTLMSSP_TARGET_TYPE_SERVER.
  static const int NTLMSSP_TARGET_TYPE_SERVER = 0x00020000;

  // /// Sent by the server in the Type 2 message to indicate that the
  // /// target authentication realm is a share (presumably for share-level
  // /// authentication).
  // static const int NTLMSSP_TARGET_TYPE_SHARE = 0x00040000;

  /// If set, requests usage of the NTLM v2 session security. NTLM v2 session
  /// security is a misnomer because it is not NTLM v2. It is NTLM v1 using the
  /// extended session security that is also in NTLM v2. NTLMSSP_NEGOTIATE_LM_KEY
  /// and NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY are mutually exclusive. If
  /// both NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY and NTLMSSP_NEGOTIATE_LM_KEY
  /// are requested, NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY alone MUST be
  /// returned to the client. NTLM v2 authentication session key generation MUST
  /// be supported by both the client and the DC in order to be used, and
  /// extended session security signing and sealing requires support from the
  /// client and the server in order to be used.
  static const int NTLMSSP_NEGOTIATE_EXTENDED_SESSIONSECURITY = 0x00080000;

  /// If set, requests an identify level token.
  static const int NTLMSSP_NEGOTIATE_IDENTIFY = 0x00100000;

  ///  If set, requests the usage of the LMOWF.
  static const int NTLMSSP_REQUEST_NON_NT_SESSION_KEY = 0x00400000;

  /// If set, indicates that the TargetInfo fields in the CHALLENGE_MESSAGE
  /// (section 2.2.1.2) are populated. An alternate name for this field is
  /// NTLMSSP_NEGOTIATE_TARGET_INFO.
  static const int NTLMSSP_NEGOTIATE_TARGET_INFO = 0x00800000;

  /// If set, requests the protocol version number. The data corresponding to
  /// this flag is provided in the Version field of the NEGOTIATE_MESSAGE,
  /// the CHALLENGE_MESSAGE, and the AUTHENTICATE_MESSAGE.
  static const int NTLMSSP_NEGOTIATE_VERSION = 0x2000000;

  /// If set, requests 128-bit session key negotiation.
  static const int NTLMSSP_NEGOTIATE_128 = 0x20000000;

  /// If set, requests an explicit key exchange. This capability SHOULD be used
  /// because it improves security for message integrity or confidentiality.
  static const int NTLMSSP_NEGOTIATE_KEY_EXCH = 0x40000000;

  /// If set, requests 56-bit encryption.
  static const int NTLMSSP_NEGOTIATE_56 = 0x80000000;
}
