part of 'kernel.dart';

typedef JsonMap = Map<String, Object?>;

abstract interface class JsonEncodable {
  JsonMap toJson();
}

final class NoInput implements JsonEncodable {
  const NoInput();

  @override
  JsonMap toJson() => const {};
}
