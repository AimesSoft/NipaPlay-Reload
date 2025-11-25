import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/dcerpc/msrpc/lsarpc.dart';
import 'package:smb_connect/src/dcerpc/msrpc/netdfs.dart';
import 'package:smb_connect/src/dcerpc/msrpc/samr.dart';
import 'package:smb_connect/src/dcerpc/msrpc/srvsvc.dart';
import 'package:smb_connect/src/dcerpc/uuid.dart';
import 'package:smb_connect/src/utils/strings.dart';

class DcerpcBinding {
  static final Map<String, String> INTERFACES = {
    "srvsvc": srvsvcGetSyntax(),
    "lsarpc": lsarpcGetSyntax(),
    "samr": samrGetSyntax(),
    "netdfs": netdfsGetSyntax(),
    "netlogon": "12345678-1234-abcd-ef00-01234567cffb:1.0",
    "wkssvc": "6BFFD098-A112-3610-9833-46C3F87E345A:1.0",
    // "samr": "12345778-1234-ABCD-EF00-0123456789AC:1.0",
  };

  String? proto;
  Map<String, Object>? _options;
  String server;
  String? endpoint;
  UUID? uuid;
  int _major = 0;
  int _minor = 0;

  DcerpcBinding(this.proto, this.server);

  String? getEndpoint() {
    return endpoint;
  }

  UUID? getUuid() {
    return uuid;
  }

  int getMajor() {
    return _major;
  }

  int getMinor() {
    return _minor;
  }

  void setOption(String key, Object val) {
    if (key == "endpoint") {
      endpoint = val.toString();
      String lep = endpoint!.toLowerCase();
      if (lep.startsWith("\\pipe\\")) {
        String? iface = INTERFACES[lep.substring(6)];
        if (iface != null) {
          int c, p;
          c = iface.indexOf(':');
          p = iface.indexOf('.', c + 1);
          uuid = UUID.str(iface.substring(0, c));
          _major = int.parse(iface.substring(c + 1, p));
          _minor = int.parse(iface.substring(p + 1));
          return;
        }
      }
      throw DcerpcException("Bad endpoint: $endpoint");
    }
    _options ??= {};
    _options![key] = val;
  }

  Object? getOption(String key) {
    if (key == "endpoint") {
      return endpoint;
    }
    return _options?[key];
  }

  @override
  String toString() {
    String ret = "$proto:$server[$endpoint";
    _options?.entries.forEach((entry) {
      ret += ",${entry.key}=${entry.value}";
    });
    ret += "]";
    return ret;
  }

  ///
  /// Bindings are in the form:
  /// proto:\\server[key1=val1,key2=val2]
  /// or
  /// proto:server[key1=val1,key2=val2]
  /// or
  /// proto:[key1=val1,key2=val2]
  ///
  /// If a key is absent it is assumed to be 'endpoint'. Thus the
  /// following are equivalent:
  /// proto:\\ts0.win.net[endpoint=\pipe\srvsvc]
  /// proto:ts0.win.net[\pipe\srvsvc]
  ///
  /// If the server is absent it is set to "127.0.0.1"
  ///
  static DcerpcBinding parse(String str) {
    int state, mark, si;
    var arr = str.toChars();
    String? proto, key;
    DcerpcBinding? binding;

    state = mark = si = 0;
    do {
      var ch = arr[si];

      switch (state) {
        case 0:
          if (ch == ':') {
            proto = str.substring(mark, si);
            mark = si + 1;
            state = 1;
          }
          break;
        case 1:
          if (ch == '\\') {
            mark = si + 1;
            break;
          }
          state = 2;
        case 2:
          if (ch == '[') {
            String server = str.substring(mark, si).trim();
            if (server.isEmpty) {
              // this can also be a v6 address within brackets, look ahead required
              int nexts = str.indexOf('[', si + 1);
              int nexte = str.indexOf(']', si);
              if (nexts >= 0 && nexte >= 0 && nexte == nexts - 1) {
                server = str.substring(si, nexte + 1);
                si = nexts;
              } else {
                server = "127.0.0.1";
              }
            }
            binding = DcerpcBinding(proto, server);
            mark = si + 1;
            state = 5;
          }
          break;
        case 5:
          if (ch == '=') {
            key = str.substring(mark, si).trim();
            mark = si + 1;
          } else if (ch == ',' || ch == ']') {
            String val = str.substring(mark, si).trim();
            mark = si + 1;
            key ??= "endpoint";
            if (binding != null) {
              binding.setOption(key, val);
            }
            key = null;
          }
          break;
        default:
          si = arr.length;
      }

      si++;
    } while (si < arr.length);

    if (binding == null || binding.getEndpoint() == null) {
      throw "Invalid binding URL: $str";
    }

    return binding;
  }
}
