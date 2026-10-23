import 'package:boctrust_savings_loan/app.dart';
import 'package:boctrust_savings_loan/app/app_router.dart';
import 'package:boctrust_savings_loan/app/inactivity_guard.dart';
import 'package:boctrust_savings_loan/app/theme_controller.dart';
import 'package:boctrust_savings_loan/module/app_flow/app_ui.dart';
import 'package:boctrust_savings_loan/module/component/text_fields.dart';
import 'package:boctrust_savings_loan/utils/input_formatters.dart';
import 'package:boctrust_savings_loan/utils/validators.dart' as validators;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/biometric_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app launches into the live prototype onboarding flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      CheetahTestApp(
        preferences: preferences,
        initialRoute: AppRoutes.onboarding,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Save without thinking about it'), findsOneWidget);
    expect(find.byType(InactivityGuard), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('login route shows the live prototype PIN login screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      CheetahTestApp(
        preferences: preferences,
        initialRoute: AppRoutes.login,
        overrides: biometricTestOverrides(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('theme mode restores saved dark value', (tester) async {
    SharedPreferences.setMockInitialValues({themePreferenceKey: 'dark'});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(CheetahTestApp(preferences: preferences));
    // Past the cold-launch splash hold.
    await tester.pump(const Duration(seconds: 3));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('theme mode invalid saved value falls back to system', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({themePreferenceKey: 'invalid'});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(CheetahTestApp(preferences: preferences));
    // Past the cold-launch splash hold.
    await tester.pump(const Duration(seconds: 3));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets('FormDropdown participates in validation', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: key,
            child: FormDropdown<String>(
              items: const [DropdownMenuItem(value: 'one', child: Text('One'))],
              onChanged: (_) {},
              validator: (value) => validators.requiredPicker(value),
            ),
          ),
        ),
      ),
    );

    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Please select an option'), findsOneWidget);
  });

  test('validators cover common Cheetah form rules', () {
    expect(validators.requiredText('   '), isNotNull);
    expect(validators.email('user@example.com'), isNull);
    expect(validators.isPasswordValid('Password1'), isNotNull);
    expect(validators.isPasswordValid('Password1!'), isNull);
    expect(validators.confirmPassword('Password1!', 'Password1!'), isNull);
    expect(validators.otp('123456'), isNull);
    expect(validators.transactionPin('1357'), isNull);
    expect(validators.strongTransactionPin('1234'), isNotNull);
    expect(validators.strongTransactionPin('1111'), isNotNull);
    expect(validators.strongTransactionPin('7890'), isNull);
    expect(validators.bvn('12345678901'), isNull);
    expect(validators.nin('12345678901'), isNull);
  });

  test('input formatters normalize constrained input', () {
    final phone = PhoneDashFormatter().formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(text: '08000000000'),
    );
    expect(phone.text, '0800-000-0000');
  });

  test('all registered routes include required UX parity routes', () {
    expect(AppRoutes.allRoutes, contains(AppRoutes.transactionAuthorization));
    expect(AppRoutes.allRoutes, contains(AppRoutes.notifications));
    expect(AppRoutes.allRoutes, contains(AppRoutes.loansNotifyMe));
    expect(AppRoutes.allRoutes, contains(AppRoutes.cardsNotifyMe));
  });

  test('linked banks resolves to the live screen, not a preview', () {
    expect(appRouteDefinitions[AppRoutes.linkedBanks]?.page, isNotNull);
    // Not an unavailable page, so no fabricated bank rows can be rendered.
    expect(appRouteDefinitions[AppRoutes.linkedBanks]?.unavailable, isNull);
  });
}
