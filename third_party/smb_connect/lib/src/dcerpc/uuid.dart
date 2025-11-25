import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/dcerpc/rpc.dart';

class UUID extends RpcUuidT {
  static final int codeUnitZero = '0'.codeUnitAt(0);
  static final int codeUnitBigA = 'A'.codeUnitAt(0);
  static final int codeUnitSmallA = 'a'.codeUnitAt(0);

  static int _hexToBin(String arr, int offset, int length) {
    int value = 0;
    int ai, count;

    count = 0;
    for (ai = offset; ai < arr.length && count < length; ai++) {
      value <<= 4;
      switch (arr[ai]) {
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
          value += arr.codeUnitAt(ai) - codeUnitZero;
          break;
        case 'A':
        case 'B':
        case 'C':
        case 'D':
        case 'E':
        case 'F':
          value += 10 + arr.codeUnitAt(ai) - codeUnitBigA;
          break;
        case 'a':
        case 'b':
        case 'c':
        case 'd':
        case 'e':
        case 'f':
          value += 10 + arr.codeUnitAt(ai) - codeUnitSmallA;
          break;
        default:
          throw SmbIllegalArgumentException(arr.substring(offset, length));
      }
      count++;
    }

    return value;
  }

  static final List<String> HEXCHARS = [
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F'
  ];

  static String _binToHex(int value, int length) {
    String res = "";
    int ai = length;
    while (ai-- > 0) {
      res = HEXCHARS[value & 0xF] + res;
      value >>>= 4;
    }
    return res;
  }

  static int _B(int i) {
    return (i & 0xFF);
  }

  static int _S(int i) {
    return (i & 0xFFFF);
  }

  /// Construct a UUID from string
  UUID.str(String str) {
    var arr = str;
    timeLow = _hexToBin(arr, 0, 8);
    timeMid = _S(_hexToBin(arr, 9, 4));
    timeHiAndVersion = _S(_hexToBin(arr, 14, 4));
    clockSeqHiAndReserved = _B(_hexToBin(arr, 19, 2));
    clockSeqLow = _B(_hexToBin(arr, 21, 2));
    node = Uint8List(6);
    node![0] = _B(_hexToBin(arr, 24, 2));
    node![1] = _B(_hexToBin(arr, 26, 2));
    node![2] = _B(_hexToBin(arr, 28, 2));
    node![3] = _B(_hexToBin(arr, 30, 2));
    node![4] = _B(_hexToBin(arr, 32, 2));
    node![5] = _B(_hexToBin(arr, 34, 2));
  }

  @override
  String toString() {
    return '${_binToHex(timeLow, 8)}-${_binToHex(timeMid, 4)}-${_binToHex(timeHiAndVersion, 4)}-${_binToHex(clockSeqHiAndReserved, 2)}${_binToHex(clockSeqLow, 2)}-${_binToHex(node![0], 2)}${_binToHex(node![1], 2)}${_binToHex(node![2], 2)}${_binToHex(node![3], 2)}${_binToHex(node![4], 2)}${_binToHex(node![5], 2)}';
  }
}
