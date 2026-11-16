import 'package:boctrust_savings_loan/app/app_router.dart';
import 'package:boctrust_savings_loan/app/error_reporting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_error_reporter.dart';

void main() {
  late RecordingErrorReporter reporter;

  setUp(() {
    reporter = RecordingErrorReporter();
    AppRouter.reporter = reporter;
    reportingContext.lastRoute = null;
  });

  tearDown(() {
    AppRouter.reporter = const NoopErrorReporter();
    reportingContext.lastRoute = null;
  });

  test('unregistered name reports once and still shows the fallback page', () {
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(name: '/promo-offer'),
    );

    expect(route, isA<PageRoute<dynamic>>());
    expect(reporter.events, hasLength(1));
    final event = reporter.events.single;
    expect(event.kind, ErrorKind.nonfatal);
    expect(event.origin, ErrorOrigin.routing);
    expect(event.reason, 'unknown_route');
    expect(event.requestedRoute, '/promo-offer');
    expect(event.route, isNull);
    expect(event.error.toString(), 'routing unknown_route');
    expect(event.stack, isNotNull);
  });

  test('a throwing reporter never prevents the page', () {
    reporter.throwOnReport = true;
    final route = AppRouter.onGenerateRoute(const RouteSettings(name: '/nope'));
    expect(route, isA<PageRoute<dynamic>>());
  });

  test('registered public and private routes report nothing', () {
    for (final name in [AppRoutes.login, AppRoutes.home]) {
      AppRouter.onGenerateRoute(RouteSettings(name: name));
    }
    expect(reporter.events, isEmpty);
  });

  testWidgets('initial route setup generates root and never reports it', (
    tester,
  ) async {
    final generated = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/a',
        onGenerateRoute: (settings) {
          generated.add(settings.name);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const SizedBox(),
          );
        },
      ),
    );
    expect(generated, ['/', '/a']);

    AppRouter.onGenerateRoute(const RouteSettings(name: '/'));
    expect(reporter.events, isEmpty);
  });

  test('unsafe names are sent as unrecognized and arguments never', () {
    AppRouter.onGenerateRoute(
      const RouteSettings(name: '/x?id=0123456789', arguments: 'secret'),
    );
    AppRouter.onGenerateRoute(const RouteSettings());

    expect(reporter.events.map((e) => e.requestedRoute), [
      '[unrecognized]',
      '[unrecognized]',
    ]);
    expect(safeRouteName('/ok-name1'), '/ok-name1');
    expect(safeRouteName('/Upper'), '[unrecognized]');
    expect(safeRouteName('/${'a' * 33}'), '[unrecognized]');
    expect(safeRouteName(null), '[unrecognized]');
    expect('${reporter.events.first.error}', isNot(contains('secret')));
  });

  test('tracker keeps the last registered route only', () {
    final tracker = RouteTracker();
    Route<void> route(String? name) => MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => const SizedBox(),
    );
    final home = route(AppRoutes.home);
    final login = route(AppRoutes.login);
    final unknown = route('/mystery');

    tracker.didPush(home, null);
    expect(reportingContext.lastRoute, AppRoutes.home);
    tracker.didPush(unknown, home);
    expect(reportingContext.lastRoute, AppRoutes.home);
    tracker.didReplace(newRoute: login, oldRoute: home);
    expect(reportingContext.lastRoute, AppRoutes.login);
    tracker.didPop(login, home);
    expect(reportingContext.lastRoute, AppRoutes.home);
    tracker.didPop(home, unknown);
    expect(reportingContext.lastRoute, AppRoutes.home);
    tracker.didRemove(home, login);
    expect(reportingContext.lastRoute, AppRoutes.login);
  });
}
