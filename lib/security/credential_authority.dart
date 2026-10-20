/// A credential belongs to the set of server addresses it was saved for.
///
/// A source may have a LAN and a WAN address. Its authority is every address
/// it has, written as space separated sorted origins; a single address is just
/// that origin. The password may be used while every current address is among
/// the saved ones, so removing an address or switching between them is fine
/// but any new or different address needs a new login.
String credentialAuthorityOf(Iterable<String> origins) {
  final unique = {
    for (final origin in origins)
      if (origin.trim().isNotEmpty) origin.trim()
  }.toList()
    ..sort();
  return unique.join(' ');
}

bool credentialAuthorityCovers(String? saved, String current) {
  if (saved == null) return true;
  final allowed = saved.split(' ').where((o) => o.isNotEmpty).toSet();
  final now = current.split(' ').where((o) => o.isNotEmpty);
  return now.isNotEmpty && now.every(allowed.contains);
}

String originOf(String address) {
  final text = address.trim();
  try {
    return Uri.parse(text).origin;
  } on Object {
    return text.toLowerCase();
  }
}
