import 'dart:async';

void reportNextError(Object error, StackTrace stack, String library) =>
    Zone.current.handleUncaughtError(error, stack);
