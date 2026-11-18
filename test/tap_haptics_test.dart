import 'package:boctrust_savings_loan/app/tap_haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final haptics = <String>[];
  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('enabled buttons and tappable rows give one light impact', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => TapHaptics(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextButton(onPressed: () => presses++, child: const Text('Save')),
              InkWell(onTap: () => presses++, child: const Text('Account row')),
              TextButton(onPressed: null, child: const Text('Disabled')),
              const Text('Plain text'),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.tap(find.text('Account row'));
    await tester.tap(find.text('Disabled'));
    await tester.tap(find.text('Plain text'));
    await tester.pump();

    expect(presses, 2);
    expect(haptics, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  testWidgets('dragging from a tappable row does not vibrate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => TapHaptics(child: child!),
        home: Scaffold(
          body: InkWell(onTap: () {}, child: const SizedBox(height: 120)),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(100, 50));
    await gesture.moveBy(const Offset(0, 50));
    await gesture.up();
    await tester.pump();

    expect(haptics, isEmpty);
  });
}
