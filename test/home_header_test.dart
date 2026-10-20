import 'package:boctrust_savings_loan/app/app_router.dart';
import 'package:boctrust_savings_loan/module/account/provider/user_providers.dart';
import 'package:boctrust_savings_loan/module/account/screens/account_screens.dart';
import 'package:boctrust_savings_loan/module/app_flow/app_ui.dart';
import 'package:boctrust_savings_loan/module/core_banking/provider/core_account_providers.dart';
import 'package:boctrust_savings_loan/module/home/provider/home_provider.dart';
import 'package:boctrust_savings_loan/module/onboarding/provider/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/flow_harness.dart';
import 'support/responsive_fixtures.dart';
import 'support/savings_fixtures.dart';

void main() {
  testWidgets('Home header keeps only the first name beside the avatar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpFlow(
      tester,
      route: AppRoutes.home,
      overrides: [
        authSessionProvider.overrideWith(SavingsSession.new),
        userProfileProvider.overrideWith(LayoutProfile.new),
        userTierProvider.overrideWith(LayoutTiers.new),
        userHomeProvider.overrideWith(LayoutHome.new),
        customerBankAccountsProvider.overrideWith(LayoutCoreAccounts.new),
      ],
    );

    final header = find.byType(AppBar);
    final avatarFinder = find.descendant(
      of: header,
      matching: find.byType(ProfileAvatar),
    );
    final nameFinder = find.descendant(
      of: header,
      matching: find.text('Alexandria'),
    );
    expect(avatarFinder, findsOneWidget);
    expect(nameFinder, findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.text('+2348012345678')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: header,
        matching: find.text('Tier 1 · Verification pending'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: header,
        matching: find.text('Alexandria Chinwendu Nwachukwu'),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(tester.widget<AppBar>(header).toolbarHeight, 72);
    expect(tester.takeException(), isNull);

    final avatar = tester.getTopLeft(avatarFinder);
    final name = tester.getTopLeft(nameFinder);
    expect(avatar.dx, lessThan(name.dx));

    await tester.tap(avatarFinder);
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
  });
}
