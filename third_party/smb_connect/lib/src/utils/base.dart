import 'package:pointycastle/api.dart';
import 'dart:math';

int currentTimeMillis() => DateTime.now().millisecondsSinceEpoch;

class _Protected {
  const _Protected();
}

const Object protected = _Protected();

typedef SecureRandom = Random;

typedef MessageDigest = Digest;
