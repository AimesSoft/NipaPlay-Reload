import 'dart:typed_data';

import 'package:pointycastle/pointycastle.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/smb/ssp_context.dart';
import 'package:smb_connect/src/spnego/neg_token_init.dart';
import 'package:smb_connect/src/spnego/neg_token_targ.dart';
import 'package:smb_connect/src/spnego/spnego_token.dart';
import 'package:smb_connect/src/utils/extensions.dart';

/// This class used to wrap a {@link SSPContext} to provide SPNEGO feature.
///
/// @author Shun
class SpnegoContext implements SSPContext {
  static ASN1ObjectIdentifier SPNEGO_MECH_OID =
      ASN1ObjectIdentifier.fromIdentifierString("1.3.6.1.5.5.2");

  SSPContext _mechContext;

  bool _firstResponse = true;
  bool _completed = false;

  List<ASN1ObjectIdentifier> mechs;
  ASN1ObjectIdentifier? selectedMech;
  List<ASN1ObjectIdentifier>? remoteMechs;

  bool _disableMic;
  bool _requireMic;

  /// Instance a <code>SpnegoContext</code> object by wrapping a {@link SSPContext}
  /// with the same mechanism this {@link SSPContext} used.
  SpnegoContext.supp(SSPContext source)
      : this(source, source.getSupportedMechs());

  /// Instance a <code>SpnegoContext</code> object by wrapping a {@link SSPContext}
  /// with specified mechanism.
  SpnegoContext(this._mechContext, this.mechs)
      : _disableMic = !Configuration.isEnforceSpnegoIntegrity &&
            Configuration.isDisableSpnegoIntegrity,
        _requireMic = Configuration.isEnforceSpnegoIntegrity;

  @override
  List<ASN1ObjectIdentifier> getSupportedMechs() {
    return [SPNEGO_MECH_OID];
  }

  @override
  int getFlags() {
    return _mechContext.getFlags();
  }

  @override
  bool isSupported(ASN1ObjectIdentifier mechanism) {
    // prevent nesting
    return false;
  }

  @override
  Uint8List? getSigningKey() {
    return _mechContext.getSigningKey();
  }

  /// Initialize the GSSContext to provide SPNEGO feature.
  @override
  Uint8List? initSecContext(Uint8List inputBuf, int offset, int len) {
    SpnegoToken? resp;
    if (_completed) {
      throw SmbConnectException("Already complete");
    } else if (len == 0) {
      resp = _initialToken();
    } else {
      resp = _negotitate(inputBuf, offset, len);
    }

    if (resp == null) {
      return null;
    }
    return resp.toByteArray();
  }

  SpnegoToken? _negotitate(Uint8List inputBuf, int offset, int len) {
    SpnegoToken spToken = _getToken(inputBuf, offset, len);
    Uint8List? inputToken;
    if (spToken is NegTokenInit) {
      NegTokenInit tinit = spToken;
      List<ASN1ObjectIdentifier> rm = tinit.getMechanisms()!;
      remoteMechs = rm;
      ASN1ObjectIdentifier prefMech = rm[0];
      // only use token if the optimistic mechanism is supported
      if (_mechContext.isSupported(prefMech)) {
        inputToken = tinit.mechanismToken;
      } else {
        ASN1ObjectIdentifier? found;
        for (ASN1ObjectIdentifier mech in rm) {
          if (_mechContext.isSupported(mech)) {
            found = mech;
            break;
          }
        }
        if (found == null) {
          throw SmbException("Server does advertise any supported mechanism");
        }
      }
    } else if (spToken is NegTokenTarg) {
      NegTokenTarg targ = spToken;

      if (_firstResponse) {
        if (targ.mechanism == null ||
            !_mechContext.isSupported(targ.mechanism!)) {
          throw SmbException(
              "Server chose an unsupported mechanism ${targ.mechanism}");
        }
        selectedMech = targ.mechanism!;
        if (targ.result == NegTokenTarg.REQUEST_MIC) {
          _requireMic = true;
        }
        _firstResponse = false;
      } else {
        if (targ.mechanism != null && targ.mechanism != selectedMech) {
          throw SmbException("Server switched mechanism");
        }
      }
      inputToken = targ.mechanismToken;
    } else {
      throw SmbException("Invalid token");
    }

    if (spToken is NegTokenTarg && _mechContext.isEstablished()) {
      // already established, but server hasn't completed yet
      NegTokenTarg targ = spToken;

      if (targ.result == NegTokenTarg.ACCEPT_INCOMPLETE &&
          targ.mechanismToken == null &&
          targ.mechanismListMIC != null) {
        // this indicates that mechlistMIC is required by the server
        _verifyMechListMIC(targ.mechanismListMIC);
        return NegTokenTarg(NegTokenTarg.UNSPECIFIED_RESULT, null, null,
            _calculateMechListMIC());
      } else if (targ.result != NegTokenTarg.ACCEPT_COMPLETED) {
        throw SmbException("SPNEGO negotiation did not complete");
      }
      _verifyMechListMIC(targ.mechanismListMIC);
      _completed = true;
      return null;
    }

    if (inputToken == null) {
      return _initialToken();
    }

    Uint8List? mechMIC;
    Uint8List? responseToken =
        _mechContext.initSecContext(inputToken, 0, inputToken.length);

    if (spToken is NegTokenTarg) {
      NegTokenTarg targ = spToken;
      if (targ.result == NegTokenTarg.ACCEPT_COMPLETED &&
          _mechContext.isEstablished()) {
        // server sent final token
        _verifyMechListMIC(targ.mechanismListMIC);
        if (!_disableMic || _requireMic) {
          mechMIC = _calculateMechListMIC();
        }
        _completed = true;
      } else if (_mechContext.isMICAvailable() &&
          (!_disableMic || _requireMic)) {
        mechMIC = _calculateMechListMIC();
      } else if (targ.result == NegTokenTarg.REJECTED) {
        throw SmbException("SPNEGO mechanism was rejected");
      }
    }

    if (responseToken == null && _mechContext.isEstablished()) {
      return null;
    }

    return NegTokenTarg(
        NegTokenTarg.UNSPECIFIED_RESULT, null, responseToken, mechMIC);
  }

  Uint8List? _calculateMechListMIC() {
    if (!_mechContext.isMICAvailable()) {
      return null;
    }

    List<ASN1ObjectIdentifier> lm = mechs;
    Uint8List ml = _encodeMechs(lm);
    Uint8List mechanismListMIC = _mechContext.calculateMIC(ml);
    return mechanismListMIC;
  }

  void _verifyMechListMIC(Uint8List? mechanismListMIC) {
    if (_disableMic) {
      return;
    }

    // No MIC verification if not present and not required
    // or if the chosen mechanism is our preferred one
    if ((mechanismListMIC == null || !_mechContext.supportsIntegrity()) &&
        _requireMic &&
        !_mechContext.isPreferredMech(selectedMech)) {
      throw SmbConnectException(
          "SPNEGO integrity is required but not available");
    }

    // otherwise we ignore the absence of a MIC
    if (!_mechContext.isMICAvailable() || mechanismListMIC == null) {
      return;
    }

    try {
      Uint8List ml = _encodeMechs(mechs);
      _mechContext.verifyMIC(ml, mechanismListMIC);
    } catch (e) {
      throw SmbConnectException("Failed to verify mechanismListMIC", e);
    }
  }

  static Uint8List _encodeMechs(List<ASN1ObjectIdentifier> mechs) {
    try {
      var seq = ASN1Sequence();
      for (var id in mechs) {
        seq.add(id);
      }
      return seq.encode();
    } catch (e) {
      //IOException
      throw SmbConnectException("Failed to encode mechList", e);
    }
  }

  SpnegoToken _initialToken() {
    Uint8List mechToken = _mechContext.initSecContext(Uint8List(0), 0, 0)!;
    return NegTokenInit(
      mechanisms: mechs,
      contextFlags: _mechContext.getFlags(),
      mechanismToken: mechToken,
      mechanismListMIC: null,
    );
  }

  @override
  bool isEstablished() {
    return _completed && _mechContext.isEstablished();
  }

  static SpnegoToken _getToken(Uint8List token, int off, int len) {
    Uint8List b = Uint8List(len);
    if (off == 0 && token.length == len) {
      b = token;
    } else {
      byteArrayCopy(
        src: token,
        srcOffset: off,
        dst: b,
        dstOffset: 0,
        length: len,
      );
    }
    return _getTokenBuff(b);
  }

  static SpnegoToken _getTokenBuff(Uint8List token) {
    try {
      switch (token[0]) {
        case 0x60:
          return NegTokenInit.parse(token);
        case 0xa1:
          return NegTokenTarg.parse(token);
        default:
          throw SpnegoException("Invalid token type");
      }
    } catch (e) {
      //IOException
      throw SpnegoException("Invalid token");
    }
  }

  @override
  bool supportsIntegrity() {
    return _mechContext.supportsIntegrity();
  }

  @override
  bool isPreferredMech(ASN1ObjectIdentifier? mech) =>
      _mechContext.isPreferredMech(mech);

  @override
  Uint8List calculateMIC(Uint8List data) {
    if (!_completed) {
      throw SmbConnectException("Context is not established");
    }
    return _mechContext.calculateMIC(data);
  }

  @override
  void verifyMIC(Uint8List data, Uint8List mic) {
    if (!_completed) {
      throw SmbConnectException("Context is not established");
    }
    _mechContext.verifyMIC(data, mic);
  }

  @override
  bool isMICAvailable() {
    if (!_completed) {
      return false;
    }
    return _mechContext.isMICAvailable();
  }

  @override
  String toString() {
    return "SPNEGO[$_mechContext]";
  }

  @override
  void dispose() {
    _mechContext.dispose();
  }
}
