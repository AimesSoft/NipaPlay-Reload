import 'package:flutter/foundation.dart';

void reportNextError(Object error, StackTrace stack, String library) =>
    FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: library));
