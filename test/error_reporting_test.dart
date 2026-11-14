import 'package:boctrust_savings_loan/app/error_reporting.dart';
import 'package:boctrust_savings_loan/app/firebase_error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_error_reporter.dart';

void main() {
  test(
    'nonfatal event sends one recordError with stable reason and information',
    () async {
      final sink = FakeSink();
      FirebaseErrorReporter(
        sink,
      ).report(serverErrorEvent(action: 'authorize_transfer'));
      await pumpEventQueue();
      expect(sink.recordErrorCalls, hasLength(1));
      expect(sink.logCalls, hasLength(1));
      expect(sink.recordErrorCalls.single.reason, 'api server_5xx');
      expect(
        sink.recordErrorCalls.single.information,
        contains('action=authorize_transfer'),
      );
      expect(sink.recordErrorCalls.single.fatal, isFalse);
      expect(sink.setCustomKeyCalls, isEmpty);
    },
  );

  test('breadcrumb event only logs one bounded line', () async {
    final sink = FakeSink();
    FirebaseErrorReporter(sink).report(validationEvent());
    await pumpEventQueue();
    expect(sink.recordErrorCalls, isEmpty);
    expect(sink.logCalls, hasLength(1));
    expect(sink.logCalls.single.length, lessThanOrEqualTo(200));
  });

  test('ignored event writes nothing', () async {
    final sink = FakeSink();
    FirebaseErrorReporter(sink).report(
      const ErrorEvent(
        kind: ErrorKind.ignored,
        origin: ErrorOrigin.api,
        reason: 'cancelled',
      ),
    );
    await pumpEventQueue();
    expect(sink.logCalls, isEmpty);
    expect(sink.recordErrorCalls, isEmpty);
  });

  test('throttle allows one per key per window and four per session', () {
    var now = DateTime(2026);
    final t = ReportThrottle(now: () => now);
    expect(t.allow('a'), isTrue);
    expect(t.allow('a'), isFalse);
    now = now.add(const Duration(minutes: 11));
    expect(t.allow('a'), isTrue);
    expect([t.allow('b'), t.allow('c'), t.allow('d')], [true, true, false]);
  });

  test('throttled nonfatal still writes a suppressed breadcrumb', () async {
    final sink = FakeSink();
    final reporter = FirebaseErrorReporter(sink);
    reporter.report(serverErrorEvent());
    reporter.report(serverErrorEvent());
    await pumpEventQueue();
    expect(sink.recordErrorCalls, hasLength(1));
    expect(sink.logCalls, hasLength(2));
    expect(sink.logCalls.last, contains('suppressed'));
  });

  test(
    'sink that throws synchronously or asynchronously is swallowed',
    () async {
      for (final sink in [
        FakeSink()..throwSync = true,
        FakeSink()..throwAsync = true,
      ]) {
        final reporter = FirebaseErrorReporter(sink);
        reporter.report(serverErrorEvent());
        reporter.breadcrumb('hello');
        reporter.recordUncaught(
          StateError('x'),
          StackTrace.empty,
          origin: ErrorOrigin.platform,
        );
      }
      await pumpEventQueue();
    },
  );

  test(
    'uncaught flutter error is recorded non-fatal with route in information',
    () async {
      final sink = FakeSink();
      final context = ReportingContext()..lastRoute = '/home';
      FirebaseErrorReporter(sink, context: context).recordUncaught(
        StateError('boom'),
        StackTrace.empty,
        origin: ErrorOrigin.flutter,
        details: FlutterErrorDetails(
          exception: StateError('boom'),
          library: 'widgets',
        ),
      );
      await pumpEventQueue();
      final call = sink.recordErrorCalls.single;
      expect(call.fatal, isFalse);
      expect(
        call.information,
        containsAll(['route=/home', 'origin=flutter', 'library=widgets']),
      );
      expect(sink.logCalls, isEmpty);
    },
  );

  test(
    'event route falls back to the context and requested route is kept',
    () async {
      final sink = FakeSink();
      final context = ReportingContext()..lastRoute = '/last';
      FirebaseErrorReporter(sink, context: context).report(
        const ErrorEvent(
          kind: ErrorKind.nonfatal,
          origin: ErrorOrigin.routing,
          reason: 'unknown_route',
          requestedRoute: '/nope',
        ),
      );
      await pumpEventQueue();
      expect(
        sink.recordErrorCalls.single.information,
        containsAll(['route=/last', 'requested_route=/nope']),
      );
    },
  );

  test('groupKey keeps separators for missing parts; labels compare equal', () {
    const event = ErrorEvent(
      kind: ErrorKind.nonfatal,
      origin: ErrorOrigin.api,
      reason: 'r',
    );
    expect(event.groupKey, '||endpoint_unclassified|||unknown_action');
    expect(
      ApiCallLabel.unlabeled,
      const ApiCallLabel(
        feature: 'unknown_feature',
        action: 'unknown_action',
        stage: 'unknown_stage',
        endpoint: 'endpoint_unclassified',
      ),
    );
  });
}
