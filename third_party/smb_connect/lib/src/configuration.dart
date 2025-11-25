import 'dart:typed_data';

import 'package:smb_connect/src/buffer_cache.dart';
import 'package:smb_connect/src/credentials.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/encoding.dart';
import 'package:smb_connect/src/utils/time_zone.dart';

import 'dialect_version.dart';

abstract class Configuration {
  bool get debugPrint;
  bool get debugPrintLowLevel;
  bool get forceSmb1;

  /// random source to use
  SecureRandom get random;

  BufferCache get bufferCache;

  /// whether DFS lookup is disabled, default false
  // bool isDfsDisabled;
  static const isDfsDisabled = true;

  /// Minimum protocol version, default SMB1
  DialectVersion get minimumVersion;

  /// Maximum protocol version, default SMB210
  DialectVersion get maximumVersion;

  /// Enforce secure negotiation, default true
  /// This does not provide any actual downgrade protection if SMB1 is allowed.
  /// It will also break connections with SMB2 servers that do not properly sign error responses.
  // bool get isRequireSecureNegotiate;
  static const isRequireSecureNegotiate = true;

  /// Enable port 139 failover, default false
  bool get isPort139FailoverEnabled;

  /// whether to announce support for unicode, default true
  bool get isUseUnicode;

  /// whether to enable support for SMB1 AndX command batching, default false
  bool get isUseBatching;

  /// OS string to report
  String get nativeOs;

  /// Lanman string to report, default smb_connect
  String get nativeLanman;

  /// receive buffer size, in bytes, default 65535
  int get receiveBufferSize;

  /// send buffer size, in bytes, default 65535
  int get sendBufferSize;

  /// socket timeout, in milliseconds, default 35000
  int get soTimeout;

  /// timeout for establishing a socket connection, in milliseconds, default 35000
  int get connTimeout;

  /// timeout for SMB sessions, in milliseconds, default 35000
  // int get sessionTimeout;

  /// timeout for SMB responses, in milliseconds, default 30000
  int get responseTimeout;

  /// local NETBIOS/short name to announce
  // String? get netbiosHostname;
  static const String? netbiosHostname = null;

  Credentials get credentials;

  /// credentials, domain name
  String? get domain;

  /// credentials, user name
  String? get username;

  /// credentials, password
  String? get password;

  /// Lanman compatibility level
  /// {href https://technet.microsoft.com/en-us/library/cc960646.aspx}
  /// 0 or 1 - LM and NTLM
  /// 2 - NTLM only
  /// 3-5 - NTLMv2 only
  /// lanman compatibility level, defaults to 3 i.e. NTLMv2 only, default 3
  static const int lanManCompatibility = 3;

  /// whether to use raw NTLMSSP tokens instead of SPNEGO wrapped ones, default false
  // bool get isUseRawNTLM;
  static const isUseRawNTLM = false;

  /// virtual circuit number to use
  static const vcNumber = 1;

  /// custom capabilities
  int get capabilities;

  /// custom flags2
  int get flags2;

  /// OEM encoding to use, default Cp850
  CharEncoding get oemEncoding;

  /// local timezone
  TimeZone get localTimezone;

  /// Process id to send, randomized if unset
  int get pid;

  /// maximum count of concurrent commands to announce, default 10
  static const int maxMpxCount = SmbConstants.DEFAULT_MAX_MPX_COUNT;

  /// whether to enable SMB signing (for everything), if available, default false
  // bool get isSigningEnabled;
  static const bool isSigningEnabled = false;

  /// This is an experimental option allowing to indicate support during protocol
  /// negotiation, SMB encryption is not implemented yet.
  /// whether SMB encryption is enabled, default false
  // bool get isEncryptionEnabled;
  static const isEncryptionEnabled = false;

  /// the maximum size of IO buffers, limits the maximum message size
  int get maximumBufferSize;

  /// maximum data size for SMB transactions default
  int get transactionBufferSize;

  /// number of buffers to keep in cache, default 16
  int get bufferCacheSize;

  /// maxmimum number of elements to request in a list request, default 200
  int get listCount;

  /// maximum data size for list/info requests (known overhead is subtracted), default 65435
  int get listSize;

  /// the batch limit for the given command
  int getBatchLimit(int cmd); //String cmd);

  /// Machine identifier
  /// ClientGuid, ... are derived from this value.
  /// Normally this should be randomly assigned for each client instance/configuration.
  /// machine identifier (32 byte)
  Uint8List get machineId;

  /// whether to disable sending/verifying SPNEGO mechanismListMIC, false
  // bool get isDisableSpnegoIntegrity;
  static const isDisableSpnegoIntegrity = false;

  /// whether to enforce verifying SPNEGO mechanismListMIC, false
  // bool get isEnforceSpnegoIntegrity;
  static const isEnforceSpnegoIntegrity = false;

  /// whether to send an AvTargetName with the NTLM exchange, true
  // bool get isSendNTLMTargetName;
  static const isSendNTLMTargetName = true;

  /// username used when guest authentication is requested, defaults to GUEST
  static const String guestUsername = "GUEST";

  /// password used when guest authentication is requested, defaults to empty string
  static const String guestPassword = "";

  // static const isDisablePlainTextPasswords =
}
