import 'connect/impl/smb2/smb2_constants.dart';

enum DialectVersion {
  /// Legacy
  SMB1(false, -1),

  /// SMB 2.02 - Windows Vista+
  SMB202(true, Smb2Constants.SMB2_DIALECT_0202),

  /// SMB 2.1 - Windows 7/Server 2008R2
  SMB210(true, Smb2Constants.SMB2_DIALECT_0210),

  /// SMB 3.0 - Windows 8/Server 2012
  SMB300(true, Smb2Constants.SMB2_DIALECT_0300),

  /// SMB 3.0.2 - Windows 8.1/Server 2012R2
  SMB302(true, Smb2Constants.SMB2_DIALECT_0302),

  /// SMB 3.1.1 - Windows 10/Server 2016
  SMB311(true, Smb2Constants.SMB2_DIALECT_0311);

  final bool smb2;
  final int dialect;

  const DialectVersion(this.smb2, this.dialect);

  bool isSMB2() {
    return smb2;
  }

  int getDialect() {
    if (!smb2) {
      throw Error(); //"new UnsupportedOperationException()");
    }
    return dialect;
  }

  bool atLeast(DialectVersion v) {
    return index >= v.index;
  }

  bool atMost(DialectVersion v) {
    return index <= v.index;
  }

  static DialectVersion min(DialectVersion a, DialectVersion b) {
    if (a.atMost(b)) {
      return a;
    }
    return b;
  }

  static DialectVersion max(DialectVersion a, DialectVersion b) {
    if (a.atLeast(b)) {
      return a;
    }
    return b;
  }

  static Set<DialectVersion> range(DialectVersion? min, DialectVersion? max) {
    Set<DialectVersion> vers = {};
    for (DialectVersion ver in values) {
      if (min != null && !ver.atLeast(min)) {
        continue;
      }

      if (max != null && !ver.atMost(max)) {
        continue;
      }

      vers.add(ver);
    }
    return vers;
  }
}
