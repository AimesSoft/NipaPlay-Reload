import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mutex/mutex.dart';
import 'package:smb_connect/src/buffer_cache.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_response.dart';
import 'package:smb_connect/src/connect/common/request.dart' as request2;
import 'package:smb_connect/src/connect/common/smb_negotiation.dart';
import 'package:smb_connect/src/connect/common/smb_negotiation_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_blank_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_negotiate.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_negotiate_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_read_and_x_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/nego/smb2_negotiate_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/nego/smb2_negotiate_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/transport/request.dart';
import 'package:smb_connect/src/connect/transport/response.dart';
import 'package:smb_connect/src/crypto/crypto.dart';
import 'package:smb_connect/src/dialect_version.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/fixes/atomic_integer.dart';
import 'package:smb_connect/src/smb/nt_status.dart';
import 'package:smb_connect/src/smb/request_param.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/bytes.dart';
import 'package:smb_connect/src/utils/encdec.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/socket/socket_reader.dart';
import 'package:smb_connect/src/utils/socket/socket_writer.dart';

import '../fixes/semaphore.dart';

typedef CompleteResponse = ({
  CommonServerMessageBlockResponse response,
  Completer<CommonServerMessageBlockResponse> completer
});

typedef OnSmbDisconnect = Function(SmbTransport transport);

class SmbTransport {
  bool _smb2 = false;
  final Configuration config;
  OnSmbDisconnect? onDisconnect;
  // final Address _address;
  final String host;
  int _port;

  final Uint8List _sbuf = Uint8List(1024);
  final _mid = AtomicInteger(0);

  late Socket _socket;
  late SocketReader2 _inp;
  late SocketWriter _out;

  late final bool _signingEnforced;
  // ignore: prefer_final_fields
  int _desiredCredits = 512;
  final Semaphore _credits = Semaphore(1, true);
  SmbNegotiationResponse? _negotiated;
  Uint8List _preauthIntegrityHash = Uint8List(64);

  final Map<int, CompleteResponse> responses = {};

  SmbTransport(
    this.config,
    this.host, [
    this._port = 0,
    this._signingEnforced =
        false, //_signingEnforced = forceSigning || config.isSigningEnforced();
  ]);

  Future close() async {
    if (config.debugPrint) {
      print("Smb transport close called");
    }
    await _inp.close();
    // await _out.close();
    await _socket.close();
  }

  SmbNegotiationResponse? getNegotiatedResponse() => _negotiated;

  Future<bool> ensureConnected() async {
    if (_negotiated != null) {
      return true;
    }
    return await _connect();
  }

  /// Negotiate Protocol Request / Response
  Future<bool> _connect() async {
    try {
      SmbNegotiation resp = await _negotiate();

      // if (resp.response == null) {
      //   throw SmbException("Failed to connect.");
      // }

      if (!resp.response.isValid(resp.request)) {
        throw SmbException("This client is not compatible with the server.");
      }

      // bool serverRequireSig = resp.response.isSigningRequired();
      // bool serverEnableSig = resp.response.isSigningEnabled();
      // if ( log.isDebugEnabled() ) {
      //     log.debug(
      //         "Signature negotiation enforced $_signingEnforced (server $serverRequireSig) enabled "
      //                 + this.getContext().getConfig().isSigningEnabled() + " (server $serverEnableSig)");
      // }

      // Adjust negotiated values
      // _tconHostName = _address.getHostName();
      _negotiated = resp.response;
      if (resp.response.getSelectedDialect()?.atLeast(DialectVersion.SMB311) ==
          true) {
        _updatePreauthHash(resp.requestBuffer!);
        _updatePreauthHash(resp.responseBuffer!);
      }
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }

  Future<bool> disconnect(bool hard, [bool inUse = true]) async {
    if (config.debugPrint) {
      print("SmbTransport was disconnect call");
    }
    await _socket.close();
    return true;
  }

  void onListenReader() async {
    if (responses.isNotEmpty) {
      var key = await _peekKey();
      while (key != null) {
        var completer = responses.remove(key);
        if (completer != null) {
          await _doRecv(completer.response);
          completer.response.setReceived();
          // bool isAsync = completer.response is ServerMessageBlock2 &&
          //     (completer.response as ServerMessageBlock2).async;
          if (completer.response.isReceived()) {
            // print("Success complete response $key");
            completer.completer.complete(completer.response);
          } else {
            responses[key] = completer;
            // print("Recvd async");
          }
        } else {
          print("Error complete response $key");
        }
        key = null;
        if (responses.isNotEmpty && _inp.available() > 0) {
          key = await _peekKey();
        }
      }
    }
  }

  Future<SmbNegotiation> _negotiate() async {
    // We cannot use Transport.sendrecv() yet because
    // the Transport thread is not setup until doConnect()
    // returns and we want to suppress all communication
    // until we have properly negotiated.
    //
    if (_port == 139) {
      await _ssn139();
    } else {
      if (_port == 0) {
        _port = SmbConstants.DEFAULT_PORT; // 445
      }
      var socket = await Socket.connect(host, SmbConstants.DEFAULT_PORT,
          timeout: Duration(milliseconds: config.soTimeout));
      _socket = socket;
      // ignore: unawaited_futures
      socket.done.then((e) {
        if (config.debugPrint) {
          print("Smb socket diconnected from done");
        }
        onDisconnect?.call(this);
      });

      _inp = SocketReader2(socket, onListenReader,
          debugPrint: config.debugPrintLowLevel);
      _out = SocketWriter(socket, debugPrint: config.debugPrintLowLevel);
    }

    if (isSMB2()) {
      //  || config.isUseSMB2OnlyNegotiation()
      return await _negotiate2(null);
    }

    SmbComNegotiate comNeg = SmbComNegotiate(config, _signingEnforced);
    await _negotiateWrite(comNeg, true);
    await _negotiatePeek();

    SmbNegotiationResponse? resp;

    if (!isSMB2()) {
      if (config.minimumVersion.isSMB2()) {
        throw SmbConnectException("Server does not support SMB2");
      }
      resp = SmbComNegotiateResponse(config);
      resp.decode(_sbuf, 4);
      resp.setReceived();
      _sbuf.fill();
    } else {
      Smb2NegotiateResponse r = Smb2NegotiateResponse(config);
      r.decode(_sbuf, 4);
      r.setReceived();
      _sbuf.fill();

      if (r.dialectRevision == Smb2Constants.SMB2_DIALECT_ANY) {
        return await _negotiate2(r);
      } else if (r.dialectRevision != Smb2Constants.SMB2_DIALECT_0202) {
        throw SmbConnectException(
            "Server returned invalid dialect verison in multi protocol negotiation");
      }
      // FIXME: permits & credits
      int permits = r.getInitialCredits();
      if (permits > 0) {
        _credits.release(permits);
      }
      return SmbNegotiation(
          Smb2NegotiateRequest(
              config,
              _signingEnforced
                  ? Smb2Constants.SMB2_NEGOTIATE_SIGNING_REQUIRED
                  : Smb2Constants.SMB2_NEGOTIATE_SIGNING_ENABLED),
          r,
          null,
          null);
    }

    /// FIXME: permits & credits
    int permits = resp.getInitialCredits();
    if (permits > 0) {
      _credits.release(permits);
    }
    _sbuf.fill();
    return SmbNegotiation(comNeg, resp, null, null);
  }

  Future<void> _ssn139() async {
    // Name calledName = Name(config, _address.firstCalledName(), 0x20, null);
    // do {
    //   _socket = await Socket.connect(_host, 139);
    //   // if ( this.localAddr != null )
    //   //     this.socket.bind(new InetSocketAddress(this.localAddr, this.localPort));
    //   // this.socket.setSoTimeout(this.transportContext.getConfig().soTimeout);

    //   _inp = SocketReader2(_socket);
    //   _out = SocketWriter(_socket);

    //   SessionServicePacket ssp = SessionRequestPacket.name(
    //       config, calledName, tc.getNameServiceClient().getLocalName());
    //   _out.write(_wbuf, 0, ssp.writeWireFormat(_wbuf, 0));
    //   if (await readn(_inp, _wbuf, 0, 4) < 4) {
    //     // try {
    //     _socket.close();
    //     // } catch (ioe) {
    //     //IOException
    //     // log.debug("Failed to close socket", ioe);
    //     // }
    //     throw SmbException("EOF during NetBIOS session request");
    //   }
    //   switch (_rbuf[0] & 0xFF) {
    //     case SessionServicePacket.POSITIVE_SESSION_RESPONSE:
    //       // if ( log.isDebugEnabled() ) {
    //       //     log.debug("session established ok with " + _address);
    //       // }
    //       return;
    //     case SessionServicePacket.NEGATIVE_SESSION_RESPONSE:
    //       int errorCode = await _inp.readByte() & 0xFF;
    //       switch (errorCode) {
    //         case NbtException.CALLED_NOT_PRESENT:
    //         case NbtException.NOT_LISTENING_CALLED:
    //           _socket.close();
    //           break;
    //         default:
    //           disconnect(true);
    //           throw NbtException(NbtException.ERR_SSN_SRVC, errorCode);
    //       }
    //       break;
    //     case -1:
    //       disconnect(true);
    //       throw NbtException(
    //           NbtException.ERR_SSN_SRVC, NbtException.CONNECTION_REFUSED);
    //     default:
    //       disconnect(true);
    //       throw NbtException(NbtException.ERR_SSN_SRVC, 0);
    //   }
    // } while ((calledName.name = _address.nextCalledName(tc)) != null);

    throw SmbIOException(
        "Failed to establish session with $host on port $_port");
  }

  Future<int> _negotiateWrite(
      CommonServerMessageBlockRequest req, bool setmid) async {
    if (setmid) {
      makeKey(req);
    } else {
      req.setMid(0);
      _mid.set(1);
    }
    int n = req.encode(_sbuf, 4);
    Encdec.encUint32BE(n & 0xFFFF, _sbuf, 0);

    /// 4 int ssn msg header */
    _out.write(_sbuf, 0, 4 + n);
    await _out.flush();
    _sbuf.fill();
    return n;
  }

  Future<void> _negotiatePeek() async {
    /// Note the Transport thread isn't running yet so we can
    /// read from the socket here.
    if (await _peekKey() == null) {
      /// try to read header */
      throw "transport closed in negotiate"; //IOException("transport closed in negotiate")
    }
    int size = Encdec.decUint16BE(_sbuf, 2) & 0xFFFF;
    if (size < 33 || (4 + size) > _sbuf.length) {
      throw "Invalid payload size: $size"; //IOException("Invalid payload size: $size")
    }
    int hdrSize = isSMB2()
        ? Smb2Constants.SMB2_HEADER_LENGTH
        : SmbConstants.SMB1_HEADER_LENGTH;
    await readn(_inp, _sbuf, 4 + hdrSize, size - hdrSize);
  }

  Future<SmbNegotiation> _negotiate2(Smb2NegotiateResponse? first) async {
    int securityMode = _getRequestSecurityMode(first);

    // further negotiation needed
    Smb2NegotiateRequest smb2neg = Smb2NegotiateRequest(config, securityMode);
    Smb2NegotiateResponse? r;
    Uint8List? negoReqBuffer;
    Uint8List? negoRespBuffer;
    try {
      smb2neg.setRequestCredits(
          max(1, _desiredCredits - _credits.availablePermits()));

      int reqLen = await _negotiateWrite(smb2neg, first != null);
      bool doPreauth = config.maximumVersion.atLeast(DialectVersion.SMB311);
      if (doPreauth) {
        negoReqBuffer = Uint8List(reqLen);
        byteArrayCopy(
            src: _sbuf,
            srcOffset: 4,
            dst: negoReqBuffer,
            dstOffset: 0,
            length: reqLen);
      }

      await _negotiatePeek();

      r = smb2neg.initResponse(config);
      int respLen = r.decode(_sbuf, 4);
      r.setReceived();
      _sbuf.fill();

      if (doPreauth) {
        negoRespBuffer = Uint8List(respLen);
        byteArrayCopy(
            src: _sbuf,
            srcOffset: 4,
            dst: negoRespBuffer,
            dstOffset: 0,
            length: respLen);
      } else {
        negoReqBuffer = null;
      }
      return SmbNegotiation(smb2neg, r, negoReqBuffer, negoRespBuffer);
    } finally {
      int grantedCredits = r?.getGrantedCredits() ?? 0;
      if (grantedCredits == 0) {
        grantedCredits = 1;
      }
      _credits.release(grantedCredits);
      _sbuf.fill();
    }
  }

  int makeKey(Request request) {
    int m = _mid.incrementAndGet() - 1;
    if (!isSMB2()) {
      m = (m % 32000);
    }
    (request as CommonServerMessageBlock).setMid(m);
    return m;
  }

  Future<int?> _peekKey() async {
    do {
      var n = await readn(_inp, _sbuf, 0, 4);
      if (n < 4) {
        return null;
      }
    } while (_sbuf[0] == 0x85);

    /// Dodge NetBIOS keep-alive */
    /// read smb header */
    if ((await readn(_inp, _sbuf, 4, SmbConstants.SMB1_HEADER_LENGTH)) <
        SmbConstants.SMB1_HEADER_LENGTH) {
      return null;
    }

    while (true) {
      ///
      /// 01234567
      /// 00SSFSMB
      /// 0 - 0's
      /// S - size of payload
      /// FSMB - 0xFF SMB magic #

      if (_sbuf[0] == 0x00 &&
          _sbuf[4] == 0xFE &&
          _sbuf[5] == Bytes.S_Byte && //'S'
          _sbuf[6] == Bytes.M_Byte && //'M'
          _sbuf[7] == Bytes.B_Byte) {
        //'B'
        _smb2 = true;
        // also read the rest of the header
        int lenDiff =
            Smb2Constants.SMB2_HEADER_LENGTH - SmbConstants.SMB1_HEADER_LENGTH;
        if (await readn(
                _inp, _sbuf, 4 + SmbConstants.SMB1_HEADER_LENGTH, lenDiff) <
            lenDiff) {
          return null;
        }
        return Encdec.decUint64LE(_sbuf, 28);
      }

      if (_sbuf[0] == 0x00 &&
          _sbuf[1] == 0x00 &&
          (_sbuf[4] == 0xFF) &&
          _sbuf[5] == Bytes.S_Byte && //'S'
          _sbuf[6] == Bytes.M_Byte && //'M'
          _sbuf[7] == Bytes.B_Byte) {
        //'B'
        break;

        /// all good (SMB) */
      }

      /// out of phase maybe? */
      /// inch forward 1 int and try again */
      for (int i = 0; i < 35; i++) {
        // log.warn("Possibly out of phase, trying to resync " + Hexdump.toHexString(_sbuf, 0, 16));
        _sbuf[i] = _sbuf[i + 1];
      }
      int b;
      if ((b = await _inp.readByte()) == -1) {
        return null;
      }
      _sbuf[35] = b;
    }

    ///
    /// Unless key returned is null or invalid Transport.loop() always
    /// calls doRecv() after and no one else but the transport thread
    /// should call doRecv(). Therefore it is ok to expect that the data
    /// in sbuf will be preserved for copying into BUF in doRecv().

    return Encdec.decUint16LE(_sbuf, 34) & 0xFFFF;
  }

  int _getRequestSecurityMode(Smb2NegotiateResponse? first) {
    int securityMode = Smb2Constants.SMB2_NEGOTIATE_SIGNING_ENABLED;
    if (_signingEnforced || (first != null && first.isSigningRequired())) {
      securityMode = Smb2Constants.SMB2_NEGOTIATE_SIGNING_REQUIRED |
          Smb2Constants.SMB2_NEGOTIATE_SIGNING_ENABLED;
    }

    return securityMode;
  }

  void _updatePreauthHash(Uint8List input) {
    _preauthIntegrityHash =
        calculatePreauthHash(input, 0, input.length, _preauthIntegrityHash);
  }

  Uint8List calculatePreauthHash(
      Uint8List input, int off, int len, Uint8List? oldHash) {
    if (!_smb2 || _negotiated == null) {
      throw SmbUnsupportedOperationException();
    }

    Smb2NegotiateResponse resp = _negotiated as Smb2NegotiateResponse;
    if (resp.getSelectedDialect()?.atLeast(DialectVersion.SMB311) != true) {
      throw SmbUnsupportedOperationException();
    }

    MessageDigest dgst;
    switch (resp.selectedPreauthHash) {
      case 1:
        dgst = Crypto.getSHA512();
        break;
      default:
        throw SmbUnsupportedOperationException();
    }

    if (oldHash != null) {
      dgst.updateBuff(oldHash);
    }
    dgst.update(input, off, len);
    return dgst.digest();
  }

  BufferCache getBufferCache() {
    return BufferCacheImpl(config.maximumBufferSize); // getBufferCacheSize());
  }

  Future<T?> send<T extends CommonServerMessageBlockResponse>(
      CommonServerMessageBlockRequest request, T? response) async {
    try {
      var resp = response ?? request.getResponse() as T;
      await doSend(request);
      // await _doRecv(resp);
      return resp;
    } catch (e) {
      return null;
    }
  }

  final Mutex sendrecvMutex = Mutex();

  Future<SmbComTransactionResponse> sendrecvComTransaction(
      SmbComTransaction request, SmbComTransactionResponse response,
      [Set<RequestParam>? params]) async {
    response.setCommand(request.getCommand());
    SmbComTransaction req = request; // as SmbComTransaction;
    SmbComTransactionResponse resp = response; // as SmbComTransactionResponse;
    resp.reset();
    _negotiated?.setupRequest(request);

    ///
    /// First request w/ interim response
    ///
    try {
      req.setBuffer(config.bufferCache.getBuffer());
      req.nextElement();
      if (req.hasMoreElements()) {
        SmbComBlankResponse interim = SmbComBlankResponse(config);
        await sendrecv(req, response: interim, params: params);
        if (interim.getErrorCode() != 0) {
          // checkStatus(req, interim);
        }
        req.nextElement().getMid();
      } else {
        makeKey(req);
      }

      try {
        resp.clearReceived();
        int timeout = getResponseTimeout(req);
        if (params?.contains(RequestParam.NO_TIMEOUT) != true) {
          resp.setExpiration(currentTimeMillis() + timeout);
        } else {
          resp.setExpiration(null);
        }

        final txbuf = config.bufferCache.getBuffer();
        resp.setBuffer(txbuf);

        ///
        /// Send multiple fragments
        ///
        bool hasMore;
        do {
          // doSend0(req);
          await doSend(req, params);
          hasMore = req.hasMoreElements();
          if (hasMore) {
            req.nextElement();
          }
        } while (hasMore);

        ///
        /// Receive multiple fragments
        ///
        await waitResponse(req.getMid(), response);

        if (resp.getErrorCode() != 0) {
          // checkStatus(req, resp);
        }
        return response;
      } finally {
        var buff = resp.releaseBuffer();
        if (buff != null) {
          config.bufferCache.releaseBuffer(buff);
        }
      }
    } catch (ie) {
      // throw new TransportException(ie);
    } finally {
      var buff = req.releaseBuffer();
      if (buff != null) {
        config.bufferCache.releaseBuffer(buff);
      }
    }
    return response;
  }

  Future<T> sendrecv<T extends CommonServerMessageBlockResponse>(
    CommonServerMessageBlockRequest request, {
    CommonServerMessageBlockResponse? response,
    Set<RequestParam>? params,
  }) async {
    await sendrecvMutex.acquire();
    try {
      if (response == null) {
        if (request is request2.Request) {
          response = request.initResponse(config);
        } else {
          response = request.getResponse()!;
        }
      } else {
        response.setCommand(request.getCommand());
      }
      response.reset();
      _negotiated?.setupRequest(request);

      for (var i = 0; i < 5; i++) {
        await doSend(request, params);

        if (params?.contains(RequestParam.RETAIN_PAYLOAD) == true) {
          response.setRetainPayload();
        }

        try {
          var resp = await waitResponse(request.getMid(), response);
          if (config.debugPrint) {
            print("Recv $resp");
          }
          return resp as T;
        } on TimeoutException catch (_) {
          if (config.debugPrint) {
            print("SmbTransport sent TimeoutException $i");
          }
        }
      }
      throw SmbException("SmbTransport cant send request: $request");
    } finally {
      sendrecvMutex.release();
    }
  }

  AtomicInteger nextMessageId = AtomicInteger(2);

  @protected
  Future<void> doSend(CommonServerMessageBlockRequest request,
      [Set<RequestParam>? params]) async {
    CommonServerMessageBlockRequest? chain = request;
    while (chain != null) {
      if (chain.getMid() == 0) {
        chain.setMid(nextMessageId.getAndIncrement());
      }
      chain = chain.getNext();
    }

    int reqCredits = 1;
    if (request.getCreditCost() == 0) {
      request.setRequestCredits(reqCredits);
    } else if (request is ServerMessageBlock2Request && request.credit == 0) {
      request.credit = 1;
    }
    if (config.debugPrint) {
      print("Send $request");
    }
    CommonServerMessageBlock smb = request as CommonServerMessageBlock;
    Uint8List buffer = getBufferCache().getBuffer();
    try {
      // synchronize around encode and write so that the ordering for
      // SMB1 signing can be maintained
      int n = smb.encode(buffer, 4);
      Encdec.encUint32BE(
          n & 0xFFFF, buffer, 0); /* 4 byte session message header */
      //
      // For some reason this can sometimes get broken up into another
      // "NBSS Continuation Message" frame according to WireShark
      _out.write(buffer, 0, 4 + n);
      await _out.flush();
    } finally {
      getBufferCache().releaseBuffer(buffer);
    }
    // if ( !request.isResponseAsync() ) {
    //   _credits.release(grantedCredits);
    // }
  }

  Duration waitResponseTimeout = Duration(seconds: 3);

  Future<CommonServerMessageBlockResponse> waitResponse(
    int key,
    CommonServerMessageBlockResponse response,
  ) async {
    Completer<CommonServerMessageBlockResponse> completer = Completer();
    responses[key] = (response: response, completer: completer);
    return completer.future.timeout(waitResponseTimeout);
  }

  @protected
  Future<void> _doRecv(Response response) async {
    CommonServerMessageBlock resp = response as CommonServerMessageBlock;
    _negotiated!.setupResponse(response);
    if (isSMB2()) {
      await _doRecvSMB2(resp);
    } else {
      await _doRecvSMB1(resp);
    }
  }

  Future<void> _doRecvSMB2(CommonServerMessageBlock response) async {
    int size =
        (Encdec.decUint16BE(_sbuf, 2) & 0xFFFF) | (_sbuf[1] & 0xFF) << 16;
    if (size < (Smb2Constants.SMB2_HEADER_LENGTH + 1)) {
      throw SmbIOException("Invalid payload size: $size");
    }

    if (_sbuf[0] != 0x00 ||
            _sbuf[4] != 0xFE ||
            _sbuf[5] != Bytes.S_Byte || // 'S' ||
            _sbuf[6] != Bytes.M_Byte || // 'M' ||
            _sbuf[7] != Bytes.B_Byte //'B'
        ) {
      throw SmbIOException("Houston we have a synchronization problem");
    }

    int nextCommand = Encdec.decUint32LE(_sbuf, 4 + 20);
    int maximumBufferSize = config.maximumBufferSize;
    int msgSize = nextCommand != 0 ? nextCommand : size;
    if (msgSize > maximumBufferSize) {
      throw SmbIOException(
          "Message size $msgSize exceeds maxiumum buffer size $maximumBufferSize");
    }

    ServerMessageBlock2Response? cur = response as ServerMessageBlock2Response;
    Uint8List buffer = getBufferCache().getBuffer();
    try {
      int rl = nextCommand != 0 ? nextCommand : size;

      // read and decode first
      byteArrayCopy(
          src: _sbuf,
          srcOffset: 4,
          dst: buffer,
          dstOffset: 0,
          length: Smb2Constants.SMB2_HEADER_LENGTH);
      await readn(_inp, buffer, Smb2Constants.SMB2_HEADER_LENGTH,
          rl - Smb2Constants.SMB2_HEADER_LENGTH);

      cur.setReadSize(rl);
      int len = cur.decode(buffer, 0);

      if (len > rl) {
        throw SmbIOException("WHAT? ( read $rl decoded $len ): $cur");
      } else if (nextCommand != 0 && len > nextCommand) {
        throw SmbIOException("Overlapping commands");
      }
      size -= rl;

      while (size > 0 && nextCommand != 0) {
        cur = cur?.getNextResponse() as ServerMessageBlock2Response?;
        if (cur == null) {
          await _inp.skip(size);
          break;
        }

        // read next header
        await readn(_inp, buffer, 0, Smb2Constants.SMB2_HEADER_LENGTH);
        nextCommand = Encdec.decUint32LE(buffer, 20);

        if ((nextCommand != 0 && nextCommand > maximumBufferSize) ||
            (nextCommand == 0 && size > maximumBufferSize)) {
          throw SmbIOException(
              "Message size ${nextCommand != 0 ? nextCommand : size} exceeds maxiumum buffer size $maximumBufferSize");
        }

        rl = nextCommand != 0 ? nextCommand : size;

        cur.setReadSize(rl);
        await readn(_inp, buffer, Smb2Constants.SMB2_HEADER_LENGTH,
            rl - Smb2Constants.SMB2_HEADER_LENGTH);

        len = cur.decode(buffer, 0, compound: true);
        if (len > rl) {
          throw SmbIOException("WHAT? ( read $rl decoded $len ): $cur");
        } else if (nextCommand != 0 && len > nextCommand) {
          throw SmbIOException("Overlapping commands");
        }
        size -= rl;
      }
    } finally {
      getBufferCache().releaseBuffer(buffer);
    }
  }

  Future<void> _doRecvSMB1(CommonServerMessageBlock resp) async {
    Uint8List buffer = getBufferCache().getBuffer();
    try {
      byteArrayCopy(
        src: _sbuf,
        srcOffset: 0,
        dst: buffer,
        dstOffset: 0,
        length: 4 + SmbConstants.SMB1_HEADER_LENGTH,
      );
      int size = (Encdec.decUint16BE(buffer, 2) & 0xFFFF);
      if (size < (SmbConstants.SMB1_HEADER_LENGTH + 1) ||
          (4 + size) > min(0xFFFF, config.maximumBufferSize)) {
        throw SmbIOException("Invalid payload size: $size");
      }
      int errorCode = Encdec.decUint32LE(buffer, 9) & 0xFFFFFFFF;
      if (resp.getCommand() == SmbComConstants.SMB_COM_READ_ANDX &&
          (errorCode == 0 || errorCode == NtStatus.NT_STATUS_BUFFER_OVERFLOW)) {
        // overflow indicator normal for pipe
        SmbComReadAndXResponse r = resp as SmbComReadAndXResponse;
        int off = SmbConstants.SMB1_HEADER_LENGTH;

        /// WordCount thru dataOffset always 27 */
        await readn(_inp, buffer, 4 + off, 27);
        off += 27;
        resp.decode(buffer, 4);

        /// EMC can send pad w/o data */
        int pad = r.getDataOffset() - off;
        if (r.getByteCount() > 0 && pad > 0 && pad < 4) {
          await readn(_inp, buffer, 4 + off, pad);
        }

        if (r.getDataLength() > 0) {
          await readn(_inp, r.getData()!, r.getOffset(), r.getDataLength());

          /// read direct */
        }
      } else {
        await readn(_inp, buffer, 4 + SmbConstants.SMB1_HEADER_LENGTH,
            size - SmbConstants.SMB1_HEADER_LENGTH);
        resp.decode(buffer, 4);
      }
    } finally {
      getBufferCache().releaseBuffer(buffer);
    }
  }

  // bool _checkStatus(ServerMessageBlock req, ServerMessageBlock resp) {
  //   bool cont = false;
  //   if (resp.getErrorCode() == 0x30002) {
  //     // if using DOS error codes this indicates a DFS referral
  //     resp.setErrorCode(NtStatus.NT_STATUS_PATH_NOT_COVERED);
  //   } else {
  //     resp.setErrorCode(SmbException.getStatusByCode(resp.getErrorCode()));
  //   }
  //   switch (resp.getErrorCode()) {
  //     case NtStatus.NT_STATUS_OK:
  //       cont = true;
  //       break;
  //     case NtStatus.NT_STATUS_ACCESS_DENIED:
  //     case NtStatus.NT_STATUS_WRONG_PASSWORD:
  //     case NtStatus.NT_STATUS_LOGON_FAILURE:
  //     case NtStatus.NT_STATUS_ACCOUNT_RESTRICTION:
  //     case NtStatus.NT_STATUS_INVALID_LOGON_HOURS:
  //     case NtStatus.NT_STATUS_INVALID_WORKSTATION:
  //     case NtStatus.NT_STATUS_PASSWORD_EXPIRED:
  //     case NtStatus.NT_STATUS_ACCOUNT_DISABLED:
  //     case NtStatus.NT_STATUS_ACCOUNT_LOCKED_OUT:
  //     case NtStatus.NT_STATUS_TRUSTED_DOMAIN_FAILURE:
  //       throw SmbAuthException(
  //           SmbException.getMessageByCode(resp.getErrorCode()));
  //     case 0xC00000BB: // NT_STATUS_NOT_SUPPORTED
  //       throw SmbUnsupportedOperationException();
  //     case NtStatus.NT_STATUS_PATH_NOT_COVERED:
  //     // samba fails to report the proper status for some operations
  //     case 0xC00000A2: // NT_STATUS_MEDIA_WRITE_PROTECTED
  //       // FIXME: checkReferral(resp, req.getPath(), req);
  //       break;
  //     case NtStatus.NT_STATUS_BUFFER_OVERFLOW:
  //       break; /* normal for DCERPC named pipes */
  //     case NtStatus.NT_STATUS_MORE_PROCESSING_REQUIRED:
  //       break; /* normal for NTLMSSP */
  //     default:
  //       // if (log.isDebugEnabled()) {
  //       //   log.debug("Error code: 0x" +
  //       //       Hexdump.toHexString(resp.getErrorCode(), 8) +
  //       //       " for " +
  //       //       req.getClass().getSimpleName());
  //       // }
  //       throw SmbException.code(resp.getErrorCode(), null);
  //   }
  //   if (resp.isVerifyFailed()) {
  //     throw SmbException("Signature verification failed.");
  //   }
  //   return cont;
  // }

  @protected
  int getResponseTimeout(Request req) {
    if (req is CommonServerMessageBlockRequest) {
      int? overrideTimeout = req.getOverrideTimeout();
      if (overrideTimeout != null) {
        return overrideTimeout;
      }
    }
    return config.responseTimeout;
  }

  bool isSMB2() {
    if (config.forceSmb1) {
      return false;
    }
    return _smb2;
  }

  bool isSigningEnforced() => _signingEnforced;

  /// Read bytes from the input stream into a buffer
  static Future<int> readn(
      SocketReader inp, Uint8List b, int off, int len) async {
    int i = 0, n = -5;

    if (off + len > b.length) {
      throw SmbIOException("Buffer too short, bufsize ${b.length} read $len");
    }

    while (i < len) {
      n = await inp.read(b, off + i, len - i);
      if (n <= 0) {
        break;
      }
      i += n;
    }

    return i;
  }
}

class BufferCacheImpl extends BufferCache {
  final int bufferSize;
  BufferCacheImpl(this.bufferSize);

  @override
  Uint8List getBuffer() {
    return Uint8List(bufferSize);
  }

  @override
  void releaseBuffer(Uint8List buf) {}
}
