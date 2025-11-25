import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:smb_connect/src/utils/extensions.dart';

import 'kdf_counter_parameters.dart';

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
///  <li>the part of the fixedInputData that comes AFTER the counter OR null </li>
///  <li>the length of the counter in bits (not bytes)</li>
/// </ul>
/// Resulting function calls assuming an 8 bit counter.
/// <ul>
/// <li>1.  KDFCounterParameters(ki,     null,                                     "Label || 0x00 || Context || [L]_2]",    8);</li>
/// <li>2.  KDFCounterParameters(ki,     "Label || 0x00 || Context || [L]_2]",     null,                                    8);</li>
/// <li>3a. KDFCounterParameters(ki,     "Label || 0x00",                        "Context || [L]_2]",                    8);</li>
/// <li>3b. KDFCounterParameters(ki,     "Label || 0x00",                        "[L]_2] || Context",                    8);</li>
/// <li>3c. KDFCounterParameters(ki,     "Label",                                 "0x00 || Context || [L]_2]",            8);</li>
/// </ul>
class KDFCounterBytesGenerator {
  static const int MAX_VALUE = 0x7fffffff;
  static final BigInt INTEGER_MAX = BigInt.from(MAX_VALUE);

  // fields set by the constructor
  final Mac prf;
  final int h;
  // fields set by init
  Uint8List? _fixedInputDataCtrPrefix;
  Uint8List? _fixedInputDataAfterCtr;
  int maxSizeExcl = 0;
  // ios is i defined as an octet string (the binary representation)
  late Uint8List _ios;
  // operational
  int _generatedBytes = 0;
  // k is used as buffer for all K(i) values
  final Uint8List _k;

  KDFCounterBytesGenerator(this.prf)
      : h = prf.macSize,
        _k = Uint8List(prf.macSize);

  void init(KDFCounterParameters param) {
    // if (!(param is KDFCounterParameters))
    //     {
    //         throw IllegalArgumentException("Wrong type of arguments given");
    //     }

    KDFCounterParameters kdfParams = param; //(KDFCounterParameters)param;

    // --- init mac based PRF ---

    prf.init(KeyParameter(kdfParams.getKI()));

    // --- set arguments ---

    _fixedInputDataCtrPrefix = kdfParams.getFixedInputDataCounterPrefix();
    _fixedInputDataAfterCtr = kdfParams.getFixedInputDataCounterSuffix();

    int r = kdfParams.getR();
    _ios = Uint8List(r ~/ 8);

    // BigInteger maxSize = TWO.pow(r).multiply(BigInteger.valueOf(h));
    BigInt maxSize = BigInt.two.pow(r) * BigInt.from(h);
    maxSizeExcl =
        maxSize.compareTo(INTEGER_MAX) == 1 ? MAX_VALUE : maxSize.toInt();

    // --- set operational state ---

    _generatedBytes = 0;
  }

  int generateBytes(Uint8List out, int outOff, int len) {
    int generatedBytesAfter = _generatedBytes + len;
    if (generatedBytesAfter < 0 || generatedBytesAfter >= maxSizeExcl) {
      throw "Current KDFCTR may only be used for $maxSizeExcl bytes";
    }

    if (_generatedBytes % h == 0) {
      _generateNext();
    }

    // copy what is left in the currentT (1..hash
    int toGenerate = len;
    int posInK = _generatedBytes % h;
    int leftInK = h - _generatedBytes % h;
    int toCopy = min(leftInK, toGenerate);
    arrayCopy(_k, posInK, out, outOff, toCopy);
    _generatedBytes += toCopy;
    toGenerate -= toCopy;
    outOff += toCopy;

    while (toGenerate > 0) {
      _generateNext();
      toCopy = min(h, toGenerate);
      arrayCopy(_k, 0, out, outOff, toCopy);
      _generatedBytes += toCopy;
      toGenerate -= toCopy;
      outOff += toCopy;
    }

    return len;
  }

  void _generateNext() {
    int i = _generatedBytes ~/ h + 1;

    // encode i into counter buffer
    switch (_ios.length) {
      case 4:
        _ios[0] = (i >>> 24);
        _ios[_ios.length - 3] = (i >>> 16);
        _ios[_ios.length - 2] = (i >>> 8);
        _ios[_ios.length - 1] = i;
      // fall through
      case 3:
        _ios[_ios.length - 3] = (i >>> 16);
        _ios[_ios.length - 2] = (i >>> 8);
        _ios[_ios.length - 1] = i;
      // fall through
      case 2:
        _ios[_ios.length - 2] = (i >>> 8);
        _ios[_ios.length - 1] = i;
      // fall through
      case 1:
        _ios[_ios.length - 1] = i;
        break;
      default:
        throw "Unsupported size of counter i";
    }

    // special case for K(0): K(0) is empty, so no update
    prf.update(_fixedInputDataCtrPrefix!, 0, _fixedInputDataCtrPrefix!.length);
    prf.update(_ios, 0, _ios.length);
    prf.update(_fixedInputDataAfterCtr!, 0, _fixedInputDataAfterCtr!.length);
    prf.doFinal(_k, 0);
  }
}
