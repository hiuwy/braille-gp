import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Logging that shows up in the `flutter run` terminal (every line starts
/// with `BRAILLE`) and is also saved to a file on the phone.
///
/// Dart can catch Dart errors, but not a native crash (e.g. inside the
/// speech engine) or Android killing the app for using too much memory.
/// For those, the file is the clue: on the next launch the last lines of the
/// previous run are printed, so you can see what the app was doing right
/// before it died.
class CrashLog {
  static String? _path;

  /// The log file path, so background isolates can write to the same file.
  static String? get path => _path;

  /// Lets a background isolate write to the same log file.
  static void attach(String? path) => _path = path;

  static void log(String tag, String message) {
    final time = DateTime.now().toIso8601String().substring(11, 23);
    final line = '$time [$tag] $message';
    // Printed immediately (not throttled) so nothing is lost if the
    // process dies a moment later.
    debugPrintSynchronously('BRAILLE $line');
    final path = _path;
    if (path == null) return;
    try {
      File(path).writeAsStringSync(
        '$line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  static void error(String tag, Object error, [StackTrace? stack]) {
    log(tag, '!!! ERROR: $error');
    if (stack != null) log(tag, '$stack');
  }

  /// Current memory used by the app, for spotting out-of-memory kills.
  static String memory() {
    try {
      return '${(ProcessInfo.currentRss / (1024 * 1024)).round()} MB in use';
    } catch (_) {
      return 'memory unknown';
    }
  }

  static Future<void> _init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/braille_run.log');
      if (await file.exists()) {
        final lines = (await file.readAsLines());
        final tail = lines.length > 40 ? lines.sublist(lines.length - 40) : lines;
        debugPrintSynchronously(
          'BRAILLE ===== Last lines logged by the PREVIOUS run =====\n'
          'BRAILLE (if the app crashed, the cause is near the bottom)',
        );
        for (final line in tail) {
          debugPrintSynchronously('BRAILLE   | $line');
        }
        debugPrintSynchronously('BRAILLE ===== End of previous run =====');
        await file.delete();
      }
      _path = file.path;
    } catch (error) {
      debugPrintSynchronously('BRAILLE Could not open the log file: $error');
    }
  }
}

/// Starts the app with every kind of Dart error logged to the terminal.
Future<void> runAppWithCrashLogging(Widget app) async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrashLog._init();

  // Errors while building or drawing widgets.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    CrashLog.error('Flutter', details.exception, details.stack);
  };

  // Any other uncaught error (async code, callbacks, plugins).
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLog.error('Uncaught', error, stack);
    return true; // handled: keep the app running
  };

  CrashLog.log('App', 'Started (${CrashLog.memory()})');

  // Log every touch, so a crash right after a tap is easy to spot.
  runApp(
    Listener(
      onPointerDown: (event) => CrashLog.log(
        'Touch',
        'Tap at ${event.position.dx.round()},${event.position.dy.round()}',
      ),
      child: app,
    ),
  );
}
