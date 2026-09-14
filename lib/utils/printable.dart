abstract interface class Printable {
  String toPrintString({
    String indent = '',
    bool enableColor = false,
  });
}
