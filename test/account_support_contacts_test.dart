import 'package:boctrust_savings_loan/app/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/flow_harness.dart';

void main() {
  testWidgets('Account shows the current support phone and email', (
    tester,
  ) async {
    await pumpFlow(tester, route: AppRoutes.account);

    await tester.scrollUntilVisible(
      find.text('Call customer care'),
      300,
    );

    expect(find.text('09064641439'), findsOneWidget);
    expect(find.text('enquiries@boctrustmfb.com'), findsOneWidget);
    expect(find.text('+234 906 464 1439 · 0703 973 9086'), findsNothing);
    expect(find.text('info@boctrustmfb.com'), findsNothing);
  });
}
