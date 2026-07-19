// ignore_for_file: avoid_print, lines_longer_than_80_chars

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

export 'package:logging/logging.dart' show Level, Logger;

@internal
abstract class LgrLogNames {
  static const _root = 'lgr';

  static const render = '$_root.render';
  static const layer = '$_root.render.layer';
  static const geometry = '$_root.geometry';
}

/// Logging utilities for the Liquid Glass Renderer package.
abstract class LgrLogs {
  static final _root = Logger(LgrLogNames._root);

  static final _activeLoggers = <Logger>{};

  /// Initialize the given [loggers] using the minimum [level].
  ///
  /// To enable all the loggers, use [LgrLogs.initAllLogs].
  static void initLoggers(Set<Logger> loggers, [Level level = Level.ALL]) {
    hierarchicalLoggingEnabled = true;

    for (final logger in loggers) {
      if (!_activeLoggers.contains(logger)) {
        print('Initializing logger: ${logger.name}');
        logger
          ..level = level
          ..onRecord.listen(_printLog);

        _activeLoggers.add(logger);
      }
    }
  }

  /// Initializes all the available loggers.
  ///
  /// To control which loggers are initialized, use [LgrLogs.initLoggers].
  static void initAllLogs([Level level = Level.ALL]) {
    initLoggers({_root}, level);
  }

  /// Returns `true` if the given [logger] is currently logging, or
  /// `false` otherwise.
  ///
  /// Generally, developers should call loggers, regardless of whether
  /// a given logger is active. However, sometimes you may want to log
  /// information that's costly to compute. In such a case, you can
  /// choose to compute the expensive information only if the given
  /// logger will actually log the information.
  static bool isLogActive(Logger logger) {
    return _activeLoggers.contains(logger);
  }

  /// Deactivates the given [loggers].
  static void deactivateLoggers(Set<Logger> loggers) {
    for (final logger in loggers) {
      if (_activeLoggers.contains(logger)) {
        print('Deactivating logger: ${logger.name}');
        logger.clearListeners();

        _activeLoggers.remove(logger);
      }
    }
  }

  /// Logs a record using a print statement.
  static void _printLog(LogRecord record) {
    print(
      '${record.loggerName} > ${record.level.name}: ${record.message}',
    );
  }
}
