import 'package:smb_connect/src/smb/nt_status.dart';
import 'package:smb_connect/src/utils/strings.dart';

import 'smb/dos_error.dart';
import 'smb/win_error.dart';

typedef SmbRuntimeException = SmbConnectException;
typedef SmbUnsupportedOperationException = Exception;
typedef SmbProtocolDecodingException = Exception;
typedef SmbIOException = Exception;
typedef SmbMalformedDataException = Exception;

class SmbAuthException extends SmbException {
  SmbAuthException(super.message);
}

typedef SmbIllegalArgumentException = Exception;
typedef SmbIllegalStateException = Exception;
typedef SpnegoException = Exception;
typedef DcerpcException = Exception;

class SmbConnectException extends Error {
  String message;
  SmbConnectException(this.message, [Object? e]);
}

class NbtException extends SmbConnectException {
  static const int serialVersionUID = 1;
  // error classes
  static const int SUCCESS = 0;
  static const int ERR_NAM_SRVC = 0x01;
  static const int ERR_SSN_SRVC = 0x02;

  // name service error codes
  static const int FMT_ERR = 0x1;
  static const int SRV_ERR = 0x2;
  static const int IMP_ERR = 0x4;
  static const int RFS_ERR = 0x5;
  static const int ACT_ERR = 0x6;
  static const int CFT_ERR = 0x7;

  // session service error codes
  static const int CONNECTION_REFUSED = -1;
  static const int NOT_LISTENING_CALLED = 0x80;
  static const int NOT_LISTENING_CALLING = 0x81;
  static const int CALLED_NOT_PRESENT = 0x82;
  static const int NO_RESOURCES = 0x83;
  static const int UNSPECIFIED = 0x8F;

  int errorClass;
  int errorCode;

  NbtException(this.errorClass, this.errorCode)
      : super(getErrorString(errorClass, errorCode));

  static String getErrorString(int errorClass, int errorCode) {
    String result = "";
    switch (errorClass) {
      case SUCCESS:
        result += "SUCCESS";
        break;
      case ERR_NAM_SRVC:
        result += "ERR_NAM_SRVC/";
        switch (errorCode) {
          case FMT_ERR:
            result += "FMT_ERR: Format Error";
          default:
            result += "Unknown error code: $errorCode";
        }
        break;
      case ERR_SSN_SRVC:
        result += "ERR_SSN_SRVC/";
        switch (errorCode) {
          case CONNECTION_REFUSED:
            result += "Connection refused";
            break;
          case NOT_LISTENING_CALLED:
            result += "Not listening on called name";
            break;
          case NOT_LISTENING_CALLING:
            result += "Not listening for calling name";
            break;
          case CALLED_NOT_PRESENT:
            result += "Called name not present";
            break;
          case NO_RESOURCES:
            result += "Called name present, but insufficient resources";
            break;
          case UNSPECIFIED:
            result += "Unspecified error";
            break;
          default:
            result += "Unknown error code: $errorCode";
        }
        break;
      default:
        result += "unknown error class: $errorClass";
    }
    return result;
  }
}

class NdrException extends SmbConnectException {
  static const int serialVersionUID = 2;
  static const String NO_NULL_REF = "ref pointer cannot be null";
  static const String INVALID_CONFORMANCE = "invalid array conformance";
  NdrException(super.message);
}

class SmbException extends Error {
  static const int serialVersionUID = 3;

  static Map<int, String> _buildErrorCodeMessages() {
    Map<int, String> res = {};
    for (int i = 0; i < NtStatus.NT_STATUS_CODES.length; i++) {
      res[NtStatus.NT_STATUS_CODES[i]] = NtStatus.NT_STATUS_MESSAGES[i];
    }
    for (int i = 0; i < DosError.DOS_ERROR_CODES.length; i++) {
      // dosErrorCodeStatusesTmp.put(DOS_ERROR_CODES[i][0], DOS_ERROR_CODES[i][1]);
      var code = DosError.DOS_ERROR_CODES[i];
      int mappedNtCode = code.$2;
      String? mappedNtMessage = res[mappedNtCode];
      if (mappedNtMessage != null) {
        res[code.$1] = mappedNtMessage;
      }
    }
    res[0] = "NT_STATUS_SUCCESS";

    return res;
  }

  static Map<int, String> _buildWinErrorCodeMessages() {
    Map<int, String> res = {};
    for (int i = 0; i < WinError.WINERR_CODES.length; i++) {
      res[WinError.WINERR_CODES[i]] = WinError.WINERR_MESSAGES[i];
    }
    return res;
  }

  static Map<int, int> _buildDosErrorCodeMessages() {
    return {for (var code in DosError.DOS_ERROR_CODES) code.$1: code.$2};
  }

  // to replace a bunch of one-off binary searches
  static final Map<int, String> _errorCodeMessages = _buildErrorCodeMessages();
  // ignore: unused_field
  static final Map<int, String> _winErrorCodeMessages =
      _buildWinErrorCodeMessages();
  static final Map<int, int> _dosErrorCodeStatuses =
      _buildDosErrorCodeMessages();

  static String getMessageByCode(int errcode) {
    return _errorCodeMessages[errcode] ??
        "0x${Hexdump.toHexString(errcode, 8)}";
  }

  static int getStatusByCode(int errcode) {
    int statusCode;
    if ((errcode & 0xC0000000) != 0) {
      statusCode = errcode;
    } else {
      statusCode =
          _dosErrorCodeStatuses[errcode] ?? NtStatus.NT_STATUS_UNSUCCESSFUL;
    }
    return statusCode;
  }

  String message;
  SmbException(this.message, [Object? e]);

  SmbException.code(int code, String? message)
      : this(message ?? "Error code: $code");
}
