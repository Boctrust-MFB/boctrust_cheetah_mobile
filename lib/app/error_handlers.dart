import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'error_reporting.dart';
import 'firebase_error_reporter.dart';
import 'services.dart';

const kCrashlyticsEnabledFlag = bool.fromEnvironment('CRASHLYTICS_ENABLED');

bool crashlyticsCollectionAllowed({
  required bool flag,
  required bool debugMode,
}) => flag && !debugMode;

typedef BufferedError = ({
  Object error,
  StackTrace stack,
  ErrorOrigin origin,
  FlutterErrorDetails? details,
});

/// Holds errors raised before Firebase is ready. Keeps the first
/// [maxEntries]: the earliest errors are the most diagnostic.
class EarlyErrorBuffer {
  static const maxEntries = 10;

  final _entries = <BufferedError>[];

  void install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _add((
        error: details.exception,
        stack: details.stack ?? StackTrace.current,
        origin: ErrorOrigin.flutter,
        details: details,
      ));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) debugPrint('Uncaught platform error: $error');
      _add((
        error: error,
        stack: stack,
        origin: ErrorOrigin.platform,
        details: null,
      ));
      return true;
    };
  }

  void _add(BufferedError entry) {
    if (_entries.length < maxEntries) _entries.add(entry);
  }

  List<BufferedError> drain() {
    final out = List<BufferedError>.of(_entries);
    _entries.clear();
    return out;
  }
}

Future<AppErrorReporter> createErrorReporter({
  required bool firebaseReady,
}) async {
  if (!firebaseReady) return const NoopErrorReporter();
  try {
    final supported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!supported) return const NoopErrorReporter();
    final allowed = crashlyticsCollectionAllowed(
      flag: kCrashlyticsEnabledFlag,
      debugMode: kDebugMode,
    );
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(allowed);
    if (!allowed) return const NoopErrorReporter();
    await crashlytics.setCustomKey('env', Env.environment);
    return FirebaseErrorReporter(FirebaseCrashlyticsSink());
  } catch (_) {
    return const NoopErrorReporter();
  }
}

/// Replaces (never chains) the global handlers of the current isolate.
void installErrorHandlers(AppErrorReporter reporter) {
  if (reporter is NoopErrorReporter) {
    FlutterError.onError = FlutterError.presentError;
    PlatformDispatcher.instance.onError = null;
    return;
  }
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    reporter.recordUncaught(
      details.exception,
      details.stack ?? StackTrace.current,
      origin: ErrorOrigin.flutter,
      details: details,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) debugPrint('Uncaught platform error: $error');
    reporter.recordUncaught(error, stack, origin: ErrorOrigin.platform);
    return true;
  };
}
