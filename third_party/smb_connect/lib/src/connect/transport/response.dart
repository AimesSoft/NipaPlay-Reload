import 'dart:typed_data';
import 'package:smb_connect/src/connect/transport/message.dart';

abstract class Response extends Message {
  /// whether the response is received
  bool isReceived();

  /// Set received status
  void setReceived();

  /// Unset received status
  void clearReceived();

  /// number of credits granted by the server
  int getGrantedCredits();

  /// status code
  int getErrorCode();

  void setMid(int k);

  /// mid
  int getMid();

  /// whether signature verification is successful
  bool verifySignature(Uint8List buffer, int i, int size);

  /// whether signature verification failed
  bool isVerifyFailed();

  /// whether the response is an error
  bool isError();

  /// Set error status
  void error();

  /// the message timeout
  int? getExpiration();

  /// message timeout
  void setExpiration(int? exp);

  void reset();

  /// an exception linked to an error
  Exception? getException();

  void setException(Exception? e);

  /// chained response
  Response? getNextResponse();
}
