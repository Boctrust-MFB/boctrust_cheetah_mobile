import 'package:boctrust_savings_loan/app/app_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/flow_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <String>[];
  var launchSucceeds = true;

  setUp(() {
    launches.clear();
    launchSucceeds = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (call) async {
          if (call.method == 'launch') {
            launches.add((call.arguments as Map)['url'] as String);
            return launchSucceeds;
          }
          return false;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, null);
  });

  testWidgets('Account shows the current support phone and email', (
    tester,
  ) async {
    await pumpFlow(tester, route: AppRoutes.account);

    await tester.scrollUntilVisible(find.text('Call customer care'), 300);

    expect(find.text('09064641439'), findsOneWidget);
    expect(find.text('enquiries@boctrustmfb.com'), findsOneWidget);
    expect(find.text('+234 906 464 1439 · 0703 973 9086'), findsNothing);
    expect(find.text('info@boctrustmfb.com'), findsNothing);
  });

  testWidgets('Account call action opens the displayed number in the dialer', (
    tester,
  ) async {
    await pumpFlow(tester, route: AppRoutes.account);
    await tester.scrollUntilVisible(find.text('Call customer care'), 300);

    await tester.tap(find.text('Call customer care'));
    await tester.pump();

    expect(launches, ['tel:09064641439']);
  });

  testWidgets('Account email action opens a composer addressed to support', (
    tester,
  ) async {
    await pumpFlow(tester, route: AppRoutes.account);
    await tester.scrollUntilVisible(find.text('Email support'), 300);

    await tester.tap(find.text('Email support'));
    await tester.pump();

    expect(launches, ['mailto:enquiries@boctrustmfb.com']);
  });

  testWidgets('Account explains when no phone app can handle the call', (
    tester,
  ) async {
    launchSucceeds = false;
    await pumpFlow(tester, route: AppRoutes.account);
    await tester.scrollUntilVisible(find.text('Call customer care'), 300);

    await tester.tap(find.text('Call customer care'));
    await tester.pump();

    expect(find.text('Unable to open your phone app.'), findsOneWidget);
  });
}
