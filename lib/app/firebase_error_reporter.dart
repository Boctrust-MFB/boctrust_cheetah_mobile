import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'error_reporting.dart';

abstract interface class CrashlyticsSink {
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    Iterable<Object> information,
    bool fatal,
  });

  Future<void> log(String message);

  Future<void> setCustomKey(String key, Object value);
}

class FirebaseCrashlyticsSink implements CrashlyticsSink {
  FirebaseCrashlytics get _crashlytics => FirebaseCrashlytics.instance;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    Iterable<Object> information = const [],
    bool fatal = false,
  }) => _crashlytics.recordError(
    error,
    stack,
    reason: reason,
    information: information,
    fatal: fatal,
  );

  @override
  Future<void> log(String message) => _crashlytics.log(message);

  @override
  Future<void> setCustomKey(String key, Object value) =>
      _crashlytics.setCustomKey(key, value);
}

class FirebaseErrorReporter implements AppErrorReporter {
  FirebaseErrorReporter(
    this._sink, {
    ReportThrottle? throttle,
    ReportingContext? context,
  }) : _throttle = throttle ?? ReportThrottle(),
       _context = context ?? reportingContext;

  final CrashlyticsSink _sink;
  final ReportThrottle _throttle;
  final ReportingContext _context;

  @override
  void report(ErrorEvent event) {
    try {
      if (event.kind == ErrorKind.ignored) return;
      var e = event.copyWith(route: event.route ?? _context.lastRoute);
      var send = e.kind == ErrorKind.nonfatal;
      if (send &&
          (e.origin == ErrorOrigin.api ||
              e.origin == ErrorOrigin.upload ||
              e.origin == ErrorOrigin.parser) &&
          !_throttle.allow(e.groupKey)) {
        e = e.copyWith(throttled: true);
        send = false;
      }
      final line = e.breadcrumb;
      _safe(() => _sink.log(line));
      if (send) {
        final reason = '${e.origin.name} ${e.reason}';
        _safe(
          () => _sink.recordError(
            e.error ?? ApiFailure(reason),
            e.stack ?? StackTrace.current,
            reason: reason,
            information: e.information,
            fatal: false,
          ),
        );
      }
    } catch (_) {}
  }

  @override
  void recordUncaught(
    Object error,
    StackTrace stack, {
    required ErrorOrigin origin,
    FlutterErrorDetails? details,
  }) {
    try {
      final route = _context.lastRoute;
      final library = details?.library;
      final errorContext = details?.context?.toDescription();
      final information = <String>[
        'origin=${origin.name}',
        if (route != null) 'route=$route',
        if (library != null) 'library=$library',
        if (errorContext != null) 'context=$errorContext',
      ];
      // DioException.toString() carries the request URI.
      final safeError = error is DioException
          ? ApiFailure('uncaught dio ${error.type.name}')
          : error;
      _safe(
        () => _sink.recordError(
          safeError,
          stack,
          reason: 'uncaught ${origin.name}',
          information: information,
          fatal: false,
        ),
      );
    } catch (_) {}
  }

  @override
  void breadcrumb(String line) {
    try {
      final text = line.length <= 200 ? line : line.substring(0, 200);
      _safe(() => _sink.log(text));
    } catch (_) {}
  }

  void _safe(Future<void> Function() call) {
    try {
      unawaited(Future.sync(call).catchError((_) {}));
    } catch (_) {}
  }
}
