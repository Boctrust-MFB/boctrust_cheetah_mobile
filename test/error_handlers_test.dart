import 'dart:ui';

import 'package:boctrust_savings_loan/app/error_handlers.dart';
import 'package:boctrust_savings_loan/app/error_reporting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_error_reporter.dart';

void main() {
  late FlutterExceptionHandler? savedFlutter;
  late ErrorCallback? savedPlatform;

  setUp(() {
    savedFlutter = FlutterError.onError;
    savedPlatform = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = savedFlutter;
    PlatformDispatcher.instance.onError = savedPlatform;
  });

  test('collection requires the flag and a non-debug build', () {
    expect(crashlyticsCollectionAllowed(flag: true, debugMode: false), isTrue);
    expect(crashlyticsCollectionAllowed(flag: true, debugMode: true), isFalse);
    expect(
      crashlyticsCollectionAllowed(flag: false, debugMode: false),
      isFalse,
    );
  });

  test('firebase not ready yields the no-op reporter', () async {
    expect(
      await createErrorReporter(firebaseReady: false),
      isA<NoopErrorReporter>(),
    );
  });

  test('framework error is forwarded once as origin flutter', () {
    final reporter = RecordingErrorReporter();
    installErrorHandlers(reporter);
    final original = FlutterError.presentError;
    FlutterError.presentError = (_) {};
    addTearDown(() => FlutterError.presentError = original);

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('boom')));

    expect(reporter.uncaught.single.origin, ErrorOrigin.flutter);
  });

  test('platform error is forwarded once and handled', () {
    final reporter = RecordingErrorReporter();
    installErrorHandlers(reporter);

    final handled = PlatformDispatcher.instance.onError!(
      StateError('x'),
      StackTrace.empty,
    );

    expect(handled, isTrue);
    expect(reporter.uncaught.single.origin, ErrorOrigin.platform);
  });

  test('errors buffered before firebase are replayed once after install', () {
    final buffer = EarlyErrorBuffer()..install();
    final original = FlutterError.presentError;
    FlutterError.presentError = (_) {};
    addTearDown(() => FlutterError.presentError = original);

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('a')));
    PlatformDispatcher.instance.onError!(StateError('b'), StackTrace.empty);

    final drained = buffer.drain();
    expect(drained.map((e) => e.origin), [
      ErrorOrigin.flutter,
      ErrorOrigin.platform,
    ]);
    expect(buffer.drain(), isEmpty);
  });

  test('buffer keeps only the first ten errors', () {
    final buffer = EarlyErrorBuffer()..install();
    for (var i = 0; i < 15; i++) {
      PlatformDispatcher.instance.onError!(StateError('$i'), StackTrace.empty);
    }
    final drained = buffer.drain();
    expect(drained, hasLength(10));
    expect(drained.first.error.toString(), contains('0'));
  });

  test('installing twice does not duplicate reports', () {
    final reporter = RecordingErrorReporter();
    installErrorHandlers(reporter);
    installErrorHandlers(reporter);

    PlatformDispatcher.instance.onError!(StateError('x'), StackTrace.empty);

    expect(reporter.uncaught, hasLength(1));
  });

  test('a no-op reporter clears the platform handler', () {
    installErrorHandlers(RecordingErrorReporter());
    installErrorHandlers(const NoopErrorReporter());
    expect(PlatformDispatcher.instance.onError, isNull);
  });
}
