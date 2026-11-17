import 'package:boctrust_savings_loan/app/app_version_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formats installed version and build number for each environment', () {
    expect(formatAppVersion('2.4.1', '402', isStaging: false), 'v2.4.1 (402)');
    expect(
      formatAppVersion('2.4.1', '402', isStaging: true),
      'v2.4.1 (402) - Staging',
    );
  });

  testWidgets('shows version data from the installed package', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'BOCTRUST',
      packageName: 'com.boctrust.app',
      version: '2.4.1',
      buildNumber: '402',
      buildSignature: '',
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionLabel())),
    );
    await tester.pumpAndSettle();
    expect(find.text('v2.4.1 (402)'), findsOneWidget);
  });
}
