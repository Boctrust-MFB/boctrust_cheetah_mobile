import 'package:boctrust_savings_loan/app/error_reporting.dart';
import 'package:boctrust_savings_loan/app/firebase_error_reporter.dart';
import 'package:flutter/foundation.dart';

class RecordingErrorReporter implements AppErrorReporter {
  final events = <ErrorEvent>[];
  final uncaught = <({Object error, StackTrace stack, ErrorOrigin origin})>[];
  final breadcrumbs = <String>[];
  bool throwOnReport = false;

  @override
  void report(ErrorEvent event) {
    if (throwOnReport) throw StateError('report failed');
    events.add(event);
  }

  @override
  void recordUncaught(
    Object error,
    StackTrace stack, {
    required ErrorOrigin origin,
    FlutterErrorDetails? details,
  }) => uncaught.add((error: error, stack: stack, origin: origin));

  @override
  void breadcrumb(String line) => breadcrumbs.add(line);
}

typedef RecordErrorCall = ({
  Object error,
  StackTrace? stack,
  String? reason,
  List<Object> information,
  bool fatal,
});

class FakeSink implements CrashlyticsSink {
  final recordErrorCalls = <RecordErrorCall>[];
  final logCalls = <String>[];
  final setCustomKeyCalls = <(String, Object)>[];
  bool throwSync = false;
  bool throwAsync = false;

  Future<void> _maybeThrow() {
    if (throwSync) throw StateError('sync failure');
    if (throwAsync) return Future.error(StateError('async failure'));
    return Future.value();
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    Iterable<Object> information = const [],
    bool fatal = false,
  }) {
    recordErrorCalls.add((
      error: error,
      stack: stack,
      reason: reason,
      information: information.toList(),
      fatal: fatal,
    ));
    return _maybeThrow();
  }

  @override
  Future<void> log(String message) {
    logCalls.add(message);
    return _maybeThrow();
  }

  @override
  Future<void> setCustomKey(String key, Object value) {
    setCustomKeyCalls.add((key, value));
    return _maybeThrow();
  }
}

ErrorEvent serverErrorEvent({String action = 'load_home'}) => ErrorEvent(
  kind: ErrorKind.nonfatal,
  origin: ErrorOrigin.api,
  reason: 'server_5xx',
  label: ApiCallLabel(
    feature: 'transfer',
    action: action,
    stage: 'submit',
    endpoint: 'transfers_authorize',
  ),
  backend: ApiBackend.core,
  method: 'POST',
  category: 'server_5xx',
  statusCode: 503,
);

ErrorEvent validationEvent() => ErrorEvent(
  kind: ErrorKind.breadcrumb,
  origin: ErrorOrigin.api,
  reason: 'validation',
  backend: ApiBackend.user,
  method: 'POST',
  category: 'validation',
  statusCode: 422,
  summary: ApiErrorSummary(message: 'x' * 500, fields: const ['a', 'b']),
);
