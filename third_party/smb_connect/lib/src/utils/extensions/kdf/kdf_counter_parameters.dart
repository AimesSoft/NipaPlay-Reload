import 'dart:typed_data';

import 'package:smb_connect/src/utils/extensions.dart';

/// This KDF has been defined by the publicly available NIST SP 800-108 specification.
/// NIST SP800-108 allows for alternative orderings of the input fields, meaning that the input can be formated in multiple ways.
/// There are 3 supported formats:  - Below [i]_2 is a counter of r-bits length concatenated to the fixedInputData.
/// <ul>
/// <li>1: K(i) := PRF( KI, [i]_2 || Label || 0x00 || Context || [L]_2 ) with the counter at the very beginning of the fixedInputData (The default implementation has this format)</li>
/// <li>2: K(i) := PRF( KI, Label || 0x00 || Context || [L]_2 || [i]_2 ) with the counter at the very end of the fixedInputData</li>
/// <li>3a: K(i) := PRF( KI, Label || 0x00 || [i]_2 || Context || [L]_2 ) OR:</li>
/// <li>3b: K(i) := PRF( KI, Label || 0x00 || [i]_2 || [L]_2 || Context ) OR:</li>
/// <li>3c: K(i) := PRF( KI, Label || [i]_2 || 0x00 || Context || [L]_2 ) etc... with the counter somewhere in the 'middle' of the fixedInputData.</li>
/// </ul>
/// This function must be called with the following KDFCounterParameters():
/// <ul>
///  <li>KI</li>
///  <li>The part of the fixedInputData that comes BEFORE the counter OR null</li>
///  <li>the part of the fixedInputData that comes AFTER the counter OR null</li>
///  <li>the length of the counter in bits (not bytes)</li>
///  </ul>
/// Resulting function calls assuming an 8 bit counter.
/// <ul>
/// <li>1.  KDFCounterParameters(ki,     null,                                     "Label || 0x00 || Context || [L]_2]",    8); </li>
/// <li>2.  KDFCounterParameters(ki,     "Label || 0x00 || Context || [L]_2]",     null,                                    8); </li>
/// <li>3a. KDFCounterParameters(ki,     "Label || 0x00",                        "Context || [L]_2]",                    8);  </li>
/// <li>3b. KDFCounterParameters(ki,     "Label || 0x00",                        "[L]_2] || Context",                    8);</li>
/// <li>3c. KDFCounterParameters(ki,     "Label",                                 "0x00 || Context || [L]_2]",            8); </li>
/// </ul>
class KDFCounterParameters {
  final Uint8List _ki;
  final Uint8List _fixedInputDataCounterPrefix;
  final Uint8List _fixedInputDataCounterSuffix;
  final int _r;

  /// Base constructor - suffix fixed input data only.
  KDFCounterParameters.suffix(
      Uint8List ki, Uint8List fixedInputDataCounterSuffix, int r)
      : this(ki, null, fixedInputDataCounterSuffix, r);

  /// Base constructor - prefix and suffix fixed input data.
  KDFCounterParameters(this._ki, Uint8List? fixedInputDataCounterPrefix,
      Uint8List? fixedInputDataCounterSuffix, this._r)
      : _fixedInputDataCounterPrefix =
            fixedInputDataCounterPrefix ?? Uint8List(0),
        _fixedInputDataCounterSuffix =
            fixedInputDataCounterSuffix ?? Uint8List(0) {
    // if (ki == null) {
    //   throw IllegalArgumentException("A KDF requires Ki (a seed) as input");
    // }
    // this.ki = Arrays.clone(ki);

    // if (fixedInputDataCounterPrefix == null) {
    //   this.fixedInputDataCounterPrefix = byte[0];
    // } else {
    //   this.fixedInputDataCounterPrefix =
    //       Arrays.clone(fixedInputDataCounterPrefix);
    // }

    // if (fixedInputDataCounterSuffix == null) {
    //   this.fixedInputDataCounterSuffix = byte[0];
    // } else {
    //   this.fixedInputDataCounterSuffix =
    //       Arrays.clone(fixedInputDataCounterSuffix);
    // }

    if (_r != 8 && _r != 16 && _r != 24 && _r != 32) {
      throw "Length of counter should be 8, 16, 24 or 32";
    }
  }

  Uint8List getKI() {
    return _ki;
  }

  Uint8List getFixedInputData() {
    //Retained for backwards compatibility
    return _fixedInputDataCounterSuffix
        .toUint8List(); //Arrays.clone(fixedInputDataCounterSuffix);
  }

  Uint8List getFixedInputDataCounterPrefix() {
    return _fixedInputDataCounterPrefix
        .toUint8List(); //Arrays.clone(fixedInputDataCounterPrefix);
  }

  Uint8List getFixedInputDataCounterSuffix() {
    return _fixedInputDataCounterSuffix
        .toUint8List(); //Arrays.clone(fixedInputDataCounterSuffix);
  }

  int getR() {
    return _r;
  }
}
