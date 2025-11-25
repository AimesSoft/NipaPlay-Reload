import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/smb_transport.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_bind.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_binding.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_constants.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_message.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/fixes/atomic_integer.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/extensions.dart';

enum DcerpcState { none, binding, bind }

abstract class DcerpcBase {
  /// The pipe should be opened read-only.
  static const int PIPE_TYPE_RDONLY = SmbConstants.O_RDONLY;

  /// The pipe should be opened only for writing.
  static const int PIPE_TYPE_WRONLY = SmbConstants.O_WRONLY;

  /// The pipe should be opened for both reading and writing.
  static const int PIPE_TYPE_RDWR = SmbConstants.O_RDWR;

  /// Pipe operations should behave like the <code>CallNamedPipe</code> Win32 Named Pipe function.
  static const int PIPE_TYPE_CALL = 0x0100;

  /// Pipe operations should behave like the <code>TransactNamedPipe</code> Win32 Named Pipe function.
  static const int PIPE_TYPE_TRANSACT = 0x0200;

  /// Pipe is used for DCE
  static const int PIPE_TYPE_DCE_TRANSACT = 0x0200 | 0x0400;

  /// Pipe should use it's own exclusive transport connection
  static const int PIPE_TYPE_UNSHARED = 0x800;

  /* This 0x20000 bit is going to get chopped! */
  static const int pipeFlags =
      (0x2019F << 16) | PIPE_TYPE_RDWR | PIPE_TYPE_DCE_TRANSACT;
  static const int pipeAccess = (pipeFlags & 7) | 0x20000;
  static const maxRecv = 4280;

  final SmbTransport transport;
  final SmbTree tree;
  // final int access;
  DcerpcState _state = DcerpcState.none;
  final AtomicInteger _msgNum = AtomicInteger();

  DcerpcBase(this.transport, this.tree);

  Future<void> bind() async {
    _state = DcerpcState.binding;
    var url =
        "ncacn_np:${transport.host}[endpoint=\\PIPE\\srvsvc,address=${transport.host}]";
    DcerpcMessage bind = DcerpcBind(binding: parseBinding(url));
    await sendrecv(bind);
  }

  Future<bool> sendrecv(DcerpcMessage msg) async {
    if (_state == DcerpcState.none) {
      await bind();
    }
    final inB = transport.config.bufferCache.getBuffer();
    final out = transport.config.bufferCache.getBuffer();

    NdrBuffer buf = NdrBuffer(out, 0);
    msg.flags = 3;
    msg.callId = _msgNum.incrementAndGet();
    msg.encode(buf);
    // int off = 0;
    // int length = msg.length;
    int n = await doSendRecieve(out, 0, msg.length, inB);
    // print(n);

    if (n != 0) {
      NdrBuffer hdrBuf = NdrBuffer(inB, 0);
      _setupReceivedFragment(hdrBuf);
      hdrBuf.index = 0;
      msg.decodeHeader(hdrBuf);
    }

    NdrBuffer msgBuf;
    if (n != 0 && !msg.isFlagSet(DcerpcConstants.DCERPC_LAST_FRAG)) {
      msgBuf = NdrBuffer(_receiveMoreFragments(msg, inB), 0);
    } else {
      msgBuf = NdrBuffer(inB, 0);
    }
    msg.decode(msgBuf);
    return msg.result == 0;
  }

  Uint8List _receiveMoreFragments(DcerpcMessage msg, Uint8List inp) {
    int off = msg.ptype == 2 ? msg.length : 24;
    Uint8List fragBytes = Uint8List(maxRecv);
    NdrBuffer fragBuf = NdrBuffer(fragBytes, 0);
    while (!msg.isFlagSet(DcerpcConstants.DCERPC_LAST_FRAG)) {
      // doReceiveFragment(fragBytes);
      _setupReceivedFragment(fragBuf);
      fragBuf.reset();
      msg.decodeHeader(fragBuf);
      int stubFragLen = msg.length - 24;
      if ((off + stubFragLen) > inp.length) {
        // shouldn't happen if allochint is correct or greater
        Uint8List tmp = Uint8List(off + stubFragLen);
        // System.arraycopy(inp, 0, tmp, 0, off);
        byteArrayCopy(
            src: inp, srcOffset: 0, dst: tmp, dstOffset: 0, length: off);
        inp = tmp;
      }
      byteArrayCopy(
          src: fragBytes,
          srcOffset: 24,
          dst: inp,
          dstOffset: off,
          length: stubFragLen);
      off += stubFragLen;
    }
    return inp;
  }

  Future<int> doSendRecieve(
      Uint8List buf, int offset, int length, Uint8List inB);

  void _setupReceivedFragment(NdrBuffer fbuf) {
    fbuf.reset();
    fbuf.index = 8;
    fbuf.setLength(fbuf.decNdrShort());
  }

  static DcerpcBinding parseBinding(String str) {
    int state, mark, si;
    var arr = str;
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
      throw DcerpcException("Invalid binding URL: $str");
    }

    return binding;
  }
}
