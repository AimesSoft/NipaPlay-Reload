import 'dart:convert';

/// Where a device finds the coordinator when the user never changed it.
///
/// A rehearsal or lab build may point it elsewhere with
/// `--dart-define=NIPAPLAY_MESH_COORDINATOR=https://host/mesh`; a user does it
/// in the advanced settings, which then write `mesh.json`.
const meshDefaultCoordinator = String.fromEnvironment(
  'NIPAPLAY_MESH_COORDINATOR',
  defaultValue: 'https://nipaplay.aimes-soft.com/mesh',
);

/// The two roots every release trusts: the primary root (kept on the Hong Kong
/// server) first, the standby root (kept on the standby server, which signs
/// nothing until the primary is replaced) second. Both are public certificates;
/// the private keys never leave their servers. Filled in by the maintainer
/// right after the roots are generated.
const _builtInIssuerPem = '';

/// A build made for a rehearsal carries its own throw-away roots as the
/// base64 of the PEM bundle: `--dart-define=NIPAPLAY_MESH_ISSUER_PEM_B64=...`.
const _definedIssuerPemBase64 =
    String.fromEnvironment('NIPAPLAY_MESH_ISSUER_PEM_B64');

/// Trust anchors are release inputs, never learned from the coordinator.
final String meshProductionIssuerPem = _definedIssuerPemBase64.isEmpty
    ? _builtInIssuerPem
    : utf8.decode(base64.decode(_definedIssuerPemBase64));

/// What a trust bundle (several PEM certificates) is made of.
final class MeshTrustReport {
  const MeshTrustReport(this.roots, this.problems);

  /// Hex of each root's SubjectPublicKeyInfo, in bundle order.
  final List<String> roots;

  /// Empty when the bundle can be shipped.
  final List<String> problems;

  bool get ok => problems.isEmpty;
}

/// Checks a bundle the way a release must be checked before it is built:
/// not empty, every PEM block parses as an X.509 certificate, every one is a
/// self-issued Ed25519 CA allowed to sign certificates and not yet expired,
/// and there are at least [minimumRoots] different ones (primary and standby).
MeshTrustReport inspectMeshTrust(
  String pem, {
  DateTime? now,
  int minimumRoots = 2,
}) {
  final problems = <String>[];
  final roots = <String>[];
  final blocks = RegExp(
    r'-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\s]+?)-----END CERTIFICATE-----',
  ).allMatches(pem).toList();
  if (pem.trim().isEmpty) {
    return const MeshTrustReport([], ['The trust bundle is empty.']);
  }
  final stripped = pem.replaceAll(
    RegExp(
        r'-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\s]+?-----END CERTIFICATE-----'),
    '',
  );
  if (stripped.trim().isNotEmpty) {
    problems
        .add('The trust bundle contains something that is not a certificate.');
  }
  for (var i = 0; i < blocks.length; i++) {
    final label = 'Root ${i + 1}';
    final List<int> der;
    try {
      der = base64.decode(blocks[i].group(1)!.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      problems.add('$label is not valid base64.');
      continue;
    }
    try {
      final info = _parseCertificate(der);
      if (!info.selfIssued) problems.add('$label is not self-issued.');
      if (!info.isCa) problems.add('$label is not a CA certificate.');
      if (!info.canSignCertificates) {
        problems.add('$label may not sign certificates (keyCertSign).');
      }
      if (!info.ed25519) problems.add('$label does not use an Ed25519 key.');
      if (!info.notAfter.isAfter(now ?? DateTime.now().toUtc())) {
        problems.add('$label has expired.');
      }
      if (roots.contains(info.publicKey)) {
        problems.add('$label repeats an earlier root.');
      }
      roots.add(info.publicKey);
    } on FormatException catch (e) {
      problems.add('$label cannot be parsed: ${e.message}');
    }
  }
  if (blocks.isEmpty) problems.add('The trust bundle holds no certificate.');
  if (blocks.length < minimumRoots || roots.toSet().length < minimumRoots) {
    problems.add(
        'The trust bundle needs $minimumRoots different roots (primary and standby), found ${roots.toSet().length}.');
  }
  return MeshTrustReport(roots, problems);
}

final class _Certificate {
  _Certificate({
    required this.selfIssued,
    required this.isCa,
    required this.canSignCertificates,
    required this.ed25519,
    required this.notAfter,
    required this.publicKey,
  });
  final bool selfIssued, isCa, canSignCertificates, ed25519;
  final DateTime notAfter;
  final String publicKey;
}

final class _Tlv {
  _Tlv(this.tag, this.bytes, this.start, this.end);
  final int tag;
  final List<int> bytes;
  final int start, end;
  List<int> get content => bytes.sublist(start, end);
  List<int> get raw => bytes.sublist(_rawStart, end);
  late int _rawStart;
}

List<_Tlv> _children(List<int> bytes) {
  final out = <_Tlv>[];
  var i = 0;
  while (i < bytes.length) {
    final begin = i;
    final tag = bytes[i++];
    if (i >= bytes.length) throw const FormatException('truncated DER');
    var length = bytes[i++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || i + count > bytes.length) {
        throw const FormatException('bad DER length');
      }
      length = 0;
      for (var k = 0; k < count; k++) {
        length = (length << 8) | bytes[i++];
      }
    }
    if (i + length > bytes.length) throw const FormatException('truncated DER');
    out.add(_Tlv(tag, bytes, i, i + length).._rawStart = begin);
    i += length;
  }
  return out;
}

String _oid(List<int> content) {
  if (content.isEmpty) throw const FormatException('empty OID');
  final parts = <int>[content[0] ~/ 40, content[0] % 40];
  var value = 0;
  for (final byte in content.skip(1)) {
    value = (value << 7) | (byte & 0x7f);
    if (byte & 0x80 == 0) {
      parts.add(value);
      value = 0;
    }
  }
  return parts.join('.');
}

DateTime _time(_Tlv tlv) {
  final text = ascii.decode(tlv.content);
  final match = tlv.tag == 0x17
      ? RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?Z$')
          .firstMatch(text)
      : RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?Z$')
          .firstMatch(text);
  if (match == null) throw const FormatException('bad validity time');
  var year = int.parse(match.group(1)!);
  if (tlv.tag == 0x17) year += year >= 50 ? 1900 : 2000;
  return DateTime.utc(
    year,
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
  );
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

_Certificate _parseCertificate(List<int> der) {
  final top = _children(der);
  if (top.length != 1 || top[0].tag != 0x30) {
    throw const FormatException('not a certificate');
  }
  final parts = _children(top[0].content);
  if (parts.length != 3 || parts[0].tag != 0x30) {
    throw const FormatException('not a certificate');
  }
  final tbs = _children(parts[0].content);
  var index = 0;
  if (tbs.isNotEmpty && tbs[0].tag == 0xa0) index++; // version
  // serial, signature algorithm, issuer, validity, subject, SPKI
  if (tbs.length < index + 6) {
    throw const FormatException('short TBSCertificate');
  }
  final issuer = tbs[index + 2];
  final validity = _children(tbs[index + 3].content);
  final subject = tbs[index + 4];
  final spki = tbs[index + 5];
  if (validity.length != 2) throw const FormatException('bad validity');
  final algorithm = _children(spki.content);
  final keyAlgorithm = _children(algorithm[0].content);
  final ed25519 =
      keyAlgorithm.isNotEmpty && _oid(keyAlgorithm[0].content) == '1.3.101.112';
  var isCa = false;
  var keyCertSign = false;
  for (final tlv in tbs.skip(index + 6)) {
    if (tlv.tag != 0xa3) continue;
    final extensions = _children(_children(tlv.content).single.content);
    for (final extension in extensions) {
      final fields = _children(extension.content);
      final oid = _oid(fields[0].content);
      final value = _children(fields.last.content);
      if (oid == '2.5.29.19' && value.isNotEmpty) {
        final basic = _children(value[0].content);
        isCa = basic.isNotEmpty &&
            basic[0].tag == 0x01 &&
            basic[0].content.first != 0;
      } else if (oid == '2.5.29.15' && value.isNotEmpty) {
        final bits = value[0].content; // unused-bits byte, then flags
        keyCertSign = bits.length > 1 && (bits[1] & 0x04) != 0;
      }
    }
  }
  return _Certificate(
    selfIssued: _hex(issuer.raw) == _hex(subject.raw),
    isCa: isCa,
    canSignCertificates: keyCertSign,
    ed25519: ed25519,
    notAfter: _time(validity[1]),
    publicKey: _hex(spki.raw),
  );
}
