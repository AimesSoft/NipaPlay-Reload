import 'dart:io';
import 'dart:typed_data';

import 'package:smb_connect/src/buffer_cache.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/smb_transport.dart';
import 'package:smb_connect/src/credentials.dart';
import 'package:smb_connect/src/dialect_version.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/encoding.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/time_zone.dart';

class BaseConfiguration implements Configuration {
  static const defaultNativeLanman = "smb_connect";
  static final _secureRandom = SecureRandom.secure();

  @override
  final bool debugPrint;
  @override
  final bool debugPrintLowLevel;
  @override
  final bool forceSmb1;

  @override
  final TimeZone localTimezone;
  @override
  final SecureRandom random;
  @override
  final BufferCache bufferCache;
  @override
  final bool isUseBatching;
  @override
  final bool isUseUnicode;

  static const isUseNtStatus = true;
  static const isUseExtendedSecurity = true;
  static const isUseNTSmbs = true;
  static const isUseLargeReadWrite = true;
  @override
  bool isPort139FailoverEnabled;
  @override
  final CharEncoding oemEncoding;
  @override
  int flags2;
  @override
  int capabilities;
  // int sessionLimit = SmbConstants.DEFAULT_SSN_LIMIT;
  @override
  final int responseTimeout;
  @override
  final int soTimeout;
  @override
  final int connTimeout;
  // int sessionTimeout = SmbConstants.DEFAULT_SO_TIMEOUT;
  @override
  final String nativeOs;
  @override
  final String nativeLanman;
  @override
  final Credentials credentials;
  @override
  String? domain;
  @override
  String? username;
  @override
  String? password;
  @override
  final DialectVersion minimumVersion;
  @override
  final DialectVersion maximumVersion;
  @override
  final int pid;
  @override
  final Uint8List machineId;
  @override
  final int listSize;
  @override
  final int listCount;
  @override
  final int maximumBufferSize;
  @override
  final int transactionBufferSize;
  @override
  final int bufferCacheSize;
  @override
  final int sendBufferSize;
  @override
  final int receiveBufferSize;

  BaseConfiguration({
    required this.credentials,
    required this.username,
    required this.password,
    required this.domain,
    this.debugPrint = false,
    this.debugPrintLowLevel = false,
    this.forceSmb1 = false,
    this.minimumVersion = DialectVersion.SMB1,
    this.maximumVersion = DialectVersion.SMB210,
    this.isPort139FailoverEnabled = false,
    this.isUseBatching = false,
    this.isUseUnicode = true,
    this.listSize = 65435,
    this.listCount = 200,
    this.maximumBufferSize = 0x10000,
    this.transactionBufferSize = 0xFFFF - 512,
    this.bufferCacheSize = 16,
    this.sendBufferSize = SmbConstants.DEFAULT_SND_BUF_SIZE,
    this.receiveBufferSize = SmbConstants.DEFAULT_RCV_BUF_SIZE,
    this.responseTimeout = SmbConstants.DEFAULT_RESPONSE_TIMEOUT,
    this.soTimeout = SmbConstants.DEFAULT_SO_TIMEOUT,
    this.connTimeout = SmbConstants.DEFAULT_CONN_TIMEOUT,
    this.capabilities = 0,
    this.flags2 = 0,
    int? pid,
    Uint8List? machineId,
    CharEncoding? oemEncoding,
    String? nativeOs,
    this.nativeLanman = defaultNativeLanman,
    TimeZone? localTimezone,
    SecureRandom? random,
    BufferCache? bufferCache,
  })  : localTimezone = localTimezone ?? TimeZone.getDefault(),
        random = random ?? _secureRandom,
        bufferCache = bufferCache ?? BufferCacheImpl(maximumBufferSize),
        machineId = machineId ?? _secureRandom.nextBytes(32),
        oemEncoding = oemEncoding ?? SmbConstants.DEFAULT_OEM_ENCODING,
        nativeOs = nativeOs ?? Platform.operatingSystem,
        pid = pid ?? _secureRandom.nextInt(65536) {
    if (flags2 == 0) {
      flags2 = SmbConstants.FLAGS2_LONG_FILENAMES |
          SmbConstants.FLAGS2_EXTENDED_ATTRIBUTES |
          (isUseExtendedSecurity
              ? SmbConstants.FLAGS2_EXTENDED_SECURITY_NEGOTIATION
              : 0) |
          // (signingPreferred ? SmbConstants.FLAGS2_SECURITY_SIGNATURES : 0) |
          (isUseNtStatus ? SmbConstants.FLAGS2_STATUS32 : 0) |
          (isUseUnicode ? SmbConstants.FLAGS2_UNICODE : 0); // || forceUnicode
    }

    if (capabilities == 0) {
      capabilities = (isUseNTSmbs ? SmbConstants.CAP_NT_SMBS : 0) |
          (isUseNtStatus ? SmbConstants.CAP_STATUS32 : 0) |
          (isUseExtendedSecurity ? SmbConstants.CAP_EXTENDED_SECURITY : 0) |
          (isUseLargeReadWrite ? SmbConstants.CAP_LARGE_READX : 0) |
          (isUseLargeReadWrite ? SmbConstants.CAP_LARGE_WRITEX : 0) |
          (isUseUnicode ? SmbConstants.CAP_UNICODE : 0);
    }
  }

  @override
  int getBatchLimit(int cmd) {
    if (cmd == SmbComConstants.SMB_COM_QUERY_INFORMATION) {
      return 0;
    }
    // int? set = batchLimits[cmd];
    // if (set != null) {
    //   return set;
    // }

    // set = doGetBatchLimit(cmd);
    // if (set != null) {
    // batchLimits[cmd] = set;
    // return set;
    // }

    // set = DEFAULT_BATCH_LIMITS[cmd];
    // if (set != null) {
    //   return set;
    // }
    return 1;
  }

  // int? doGetBatchLimit(String cmd) {
  //   return null;
  // }
}
