import 'package:boctrust_savings_loan/module/savings/model/savings_plan_models.dart';
import 'package:boctrust_savings_loan/module/savings/model/savings_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a reminder tap from another user is dropped', () {
    final arg = SavingsReminderTap.encode(
      SavingsProductType.smartSave,
      'a1',
      'plan-1',
    );
    expect(SavingsReminderTap.parse(arg, currentOwnerTag: 'b2'), isNull);
    expect(SavingsReminderTap.parse(arg, currentOwnerTag: null), isNull);
    final tap = SavingsReminderTap.parse(arg, currentOwnerTag: 'a1')!;
    expect((tap.planId, tap.product), ('plan-1', SavingsProductType.smartSave));
  });
}
