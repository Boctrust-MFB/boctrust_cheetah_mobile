import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:boctrust_savings_loan/app/interceptors.dart';
import 'package:boctrust_savings_loan/app/network.dart';
import 'package:boctrust_savings_loan/module/savings/model/savings_plan_models.dart';
import 'package:boctrust_savings_loan/module/savings/service/core_savings_plan_service.dart';
import 'package:dio/dio.dart';
import 'package:boctrust_savings_loan/app/services.dart';
import 'package:boctrust_savings_loan/module/core_banking/model/customer_bank_account_models.dart';
import 'package:boctrust_savings_loan/module/core_banking/provider/core_account_providers.dart';
import 'package:boctrust_savings_loan/module/core_banking/provider/core_account_activity_providers.dart';
import 'package:boctrust_savings_loan/module/core_banking/provider/flex_source_check.dart';
import 'package:boctrust_savings_loan/module/savings/provider/savings_plan_action_provider.dart';
import 'package:boctrust_savings_loan/module/savings/provider/savings_plan_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with [data] in the Core envelope, recording it.
class _Core implements HttpClientAdapter {
  _Core([this.data]);
  final Object? data;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'message': 'ok', 'data': data, 'meta': {}}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

CoreSavingsPlanService _service(_Core core) => CoreSavingsPlanService(
  ApiService(
    Dio(BaseOptions(baseUrl: 'https://core.test/api/v1'))
      ..httpClientAdapter = core,
  ),
);

Map<String, Object?> _plan({String status = 'active'}) => {
  'planId': 'p1',
  'productCode': 'bocSmartSave',
  'planName': 'Rent',
  'targetAmount': '100000',
  'principalAmount': '5000.00',
  'interestEarned': '0',
  'tenorDays': 90,
  'maturityDate': '2027-01-08',
  'status': status,
  'currentInterestRatePercent': '8.5',
};

class _SlowFund extends CoreSavingsPlanService {
  _SlowFund(this.reply) : super(null);
  final Completer<NotifierState<SavingsPlanActionResult>> reply;
  var reads = 0;
  var liquidations = 0;
  var funds = 0;

  @override
  Future<NotifierState<SavingsPlanActionResult>> fundPlan(String _, String _) {
    funds++;
    return reply.future;
  }

  @override
  Future<NotifierState<SavingsPlanActionResult>> liquidatePlan(String _) async {
    liquidations++;
    return const NotifierState.blocked('x');
  }

  @override
  Future<NotifierState<SavingsPlanDetail>> getPlan(String planId) async {
    reads++;
    return const NotifierState.blocked('x');
  }
}

class _Accounts extends CustomerBankAccountsNotifier {
  _Accounts([this.status = CoreAccountStatus.active, this.savingsStatus]);
  final CoreAccountStatus status;
  final CoreAccountStatus? savingsStatus;
  static var loads = 0;
  @override
  NotifierState<CustomerBankAccountsData> build() => NotifierState.done(
    CustomerBankAccountsData(
      accounts: [
        CustomerBankAccount(
          productCode: kFlexProductCode,
          productName: 'Boc Flex',
          accountNumber: '1100012345',
          status: status,
        ),
        if (savingsStatus != null)
          CustomerBankAccount(
            productCode: 'SAVINGS',
            productName: 'SmartSave',
            accountNumber: '2200012345',
            status: savingsStatus!,
          ),
      ],
    ),
  );

  @override
  Future<bool> refreshAccount(String accountNumber) async => true;

  @override
  Future<NotifierState<CustomerBankAccountsData>> load() async {
    loads++;
    return state;
  }
}

SavingsPlanProduct _product(int minTenorDays) => SavingsPlanProduct(
  productCode: 'p',
  productName: 'Plan',
  planType: 'fixed_deposit',
  earlyWithdrawalFeePercent: '10',
  minTenorDays: minTenorDays,
  maxTenorDays: 365,
  tenors: const [],
);

SavingsPlanQuote _quote(
  SavingsProductType type,
  int tenorDays, {
  String minAmount = '5000.00',
  String? maxAmount,
}) => SavingsPlanQuote(
  productCode: type.coreCode!,
  productName: type.displayName,
  tenorDays: tenorDays,
  startDate: DateTime(2026, 10, 15),
  endDate: DateTime(2026, 10, 15 + tenorDays),
  interestRatePercent: '10',
  minAmount: minAmount,
  maxAmount: maxAmount,
  earlyWithdrawalFeePercent: '10',
);

void main() {
  test('custom dates enforce each product minimum in calendar days', () {
    final today = DateTime(2026, 10, 15);
    final goalProduct = _product(90);
    final depositProduct = _product(30);
    int? goal(int days, [DateTime? on]) => SavingsPlanDraft(
      type: SavingsProductType.smartSave,
      customMaturityDate: DateTime(2026, 10, 15 + days),
    ).tenorDaysOn(on ?? today, goalProduct);
    int? deposit(int days) => SavingsPlanDraft(
      type: SavingsProductType.fixed,
      customMaturityDate: DateTime(2026, 10, 15 + days),
    ).tenorDaysOn(today, depositProduct);

    expect(goal(89), isNull);
    expect(goal(90), 90);
    expect(goal(90, today.add(const Duration(days: 1))), isNull);
    expect(deposit(29), isNull);
    expect(deposit(30), 30);
    expect(goal(365), 365);
    expect(deposit(365), 365);
    expect(goal(366), isNull);
    expect(deposit(366), isNull);
    expect(deposit(45), 45);
  });

  test('choosing a preset after a custom date restores its fixed tenor', () {
    final selected = SavingsPlanDraft(
      type: SavingsProductType.fixed,
      customMaturityDate: DateTime(2027, 1, 15),
    ).copyWith(durationMonths: 3, clearCustomMaturityDate: true);

    expect(selected.customMaturityDate, isNull);
    expect(selected.tenorDaysOn(DateTime(2026, 10, 15), _product(30)), 90);
  });

  test('SmartSave target must exceed its opening minimum', () {
    final quote = _quote(SavingsProductType.smartSave, 180);
    for (final amount in ['abc', '0', '4,999.99', '5,000', '5,000.00']) {
      expect(quote.acceptsTarget(amount), isFalse, reason: amount);
      expect(
        SavingsPlanDraft(
          type: SavingsProductType.smartSave,
          name: 'Rent',
          amount: amount,
          durationMonths: 6,
        ).toCreateRequest(quote),
        isNull,
        reason: amount,
      );
    }
    expect(quote.acceptsTarget('₦5,000.01'), isTrue);
    expect(quote.acceptsTarget('6,000'), isTrue);
  });

  // Plan amounts arrive as Naira decimal strings.
  test('amounts read as Naira', () {
    final groups = SavingsProductGroup.listFromJson([
      {
        'accountNumber': '1100919408',
        'productCode': 'bocSmartSave',
        'productName': 'Boc SmartSave',
        'productInterestRatePercent': '8.5',
        'defaultTenorDays': 90,
        'accountBalance': '1250000',
        'plans': [
          _plan(),
          _plan(status: 'paused_by_bank'),
          {..._plan(), 'principalAmount': 'abc'},
        ],
      },
      {'productCode': 'bocPadi', 'productName': 'Padi', 'plans': []},
    ]);

    final group = groups.single;
    expect(group.type, SavingsProductType.smartSave);
    expect(group.accountNumber, '1100919408');
    expect(group.plans.first.principal, '5000.00');
    expect(group.plans.first.target, '100000');
    expect(group.plans.first.status, SavingsPlanStatus.active);
    expect(group.plans[1].status, SavingsPlanStatus.unknown);
    // A plan whose amount cannot be read is kept, not hidden.
    expect(group.plans, hasLength(3));
    expect(group.plans.last.principal, isNull);
  });

  test('reads accrued interest and the early-withdrawal fee', () {
    final plan = SavingsPlan.tryParse({
      ..._plan(),
      'accruedInterest': '120.40',
      'earlyWithdrawalFeePercent': '2.5',
    })!;

    expect(plan.accruedInterest, '120.40');
    expect(plan.earlyWithdrawalFeePercent, '2.5');
  });

  test('a plan reads its schedule and projected interest', () {
    final plan = SavingsPlan.tryParse({
      'planId': 'csp-3b7c7ffec81311f1b91ebf559b007420',
      'productCode': 'bocSmartSave',
      'productName': 'Boc SmartSave',
      'planName': 'Rent',
      'targetAmount': '4500.00',
      'principalAmount': '5000.00',
      'interestEarned': '0.00',
      'tenorDays': 90,
      'startDate': '2026-10-14',
      'maturityDate': '2027-01-12',
      'saveFrequency': 'daily',
      'recurringAmount': '550.00',
      'status': 'active',
      'currentInterestRatePercent': '10.000',
      'projectedInterestAtMaturity': '110.96',
      'accruedInterest': '0.00',
      'earlyWithdrawalFeePercent': '0',
      'createdAt': '2026-10-14T21:07:15.290Z',
      'accountNumber': '1200927899',
    })!;

    expect(plan.startDate, DateTime(2026, 10, 14));
    expect(plan.saveFrequency, SavingsFrequency.daily);
    expect(plan.recurringAmount, '550.00');
    expect(plan.projectedInterest, '110.96');
    expect(plan.target, '4500.00');
    expect(plan.principal, '5000.00');
  });

  test('plan detail keeps events without their references', () {
    final detail = SavingsPlanDetail.fromJson({
      ..._plan(),
      'accountNumber': '1100919408',
      'events': [
        {
          'eventType': 'top_up',
          'amount': '2500.00',
          'reference': 'REF-1',
          'createdAt': '2026-10-09T10:00:00Z',
        },
      ],
    });

    final event = detail.events.single;
    expect(event.type, SavingsPlanEventType.topUp);
    expect(event.amount, '2500.00');
    expect(event.props, isNot(contains('REF-1')));
  });

  test('plans are filtered by product and logged in full', () async {
    final core = _Core(<Object?>[]);
    final service = _service(core);

    await service.getPlans(SavingsProductType.fixed);
    await service.getPlan('p/1');

    final [list, detail] = core.requests;
    expect(list.path, '/me/savings-plans');
    expect(list.queryParameters, {'productCode': 'boctrustFixedDeposit'});
    expect(
      list.extra,
      isNot(contains(LoggingInterceptor.privacySensitivePathKey)),
    );
    expect(detail.path, '/me/savings-plans/p%2F1');
    expect(
      detail.extra,
      isNot(contains(LoggingInterceptor.privacySensitivePathKey)),
    );
  });

  test('funding sends Naira to the encoded plan', () async {
    final core = _Core({
      'planId': 'p/1',
      'status': 'active',
      'principalAmount': '7500.00',
    });

    final result = await _service(core).fundPlan('p/1', '2500.00');

    final request = core.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/me/savings-plans/p%2F1/fund');
    expect(request.data, {'amount': '2500.00'});
    expect(result.data!.principalAmount, '7500.00');
  });

  test("a SmartSave draft becomes Core's create request", () {
    const draft = SavingsPlanDraft(
      type: SavingsProductType.smartSave,
      name: 'Rent',
      amount: '200,000',
      durationMonths: 6,
      autoSave: true,
      frequency: SavingsFrequency.weekly,
      recurringAmount: '5,000',
    );

    expect(
      draft
          .toCreateRequest(_quote(SavingsProductType.smartSave, 180))!
          .toJson(),
      {
        'productCode': 'bocSmartSave',
        'tenorDays': 180,
        'amount': '5000.00',
        'planName': 'Rent',
        'targetAmount': '200000.00',
        'saveFrequency': 'weekly',
        'recurringAmount': '5000.00',
      },
    );
  });

  test('a Fixed Deposit draft sends its term and typed principal', () {
    const draft = SavingsPlanDraft(
      type: SavingsProductType.fixed,
      amount: '25,000',
      durationMonths: 3,
    );
    final quote = _quote(
      SavingsProductType.fixed,
      90,
      minAmount: '1000.00',
      maxAmount: '50000.00',
    );

    expect(draft.toCreateRequest(quote)!.toJson(), {
      'productCode': 'boctrustFixedDeposit',
      'tenorDays': 90,
      'amount': '25000.00',
    });
  });

  test('a Fixed Deposit draft sends its recurring schedule when enabled', () {
    const draft = SavingsPlanDraft(
      type: SavingsProductType.fixed,
      name: 'School fees',
      amount: '5,000',
      durationMonths: 12,
      autoSave: true,
      frequency: SavingsFrequency.weekly,
      recurringAmount: '1,500',
    );

    final quote = _quote(SavingsProductType.fixed, 365);
    expect(draft.toCreateRequest(quote)!.toJson(), {
      'productCode': 'boctrustFixedDeposit',
      'tenorDays': 365,
      'amount': '5000.00',
      'planName': 'School fees',
      'saveFrequency': 'weekly',
      'recurringAmount': '1500.00',
    });
    expect(draft.copyWith(recurringAmount: '').toCreateRequest(quote), isNull);
    expect(draft.copyWith(autoSave: false).toCreateRequest(quote)!.toJson(), {
      'productCode': 'boctrustFixedDeposit',
      'tenorDays': 365,
      'amount': '5000.00',
      'planName': 'School fees',
    });
  });

  test('goal and deposit names keep emoji in Core requests and replies', () {
    const goalName = 'New home 🏡';
    const depositName = 'Family trip 👨‍👩‍👧‍👦';
    const goal = SavingsPlanDraft(
      type: SavingsProductType.smartSave,
      name: goalName,
      amount: '200,000',
      durationMonths: 6,
    );
    const deposit = SavingsPlanDraft(
      type: SavingsProductType.fixed,
      name: depositName,
      amount: '5,000',
      durationMonths: 3,
    );

    expect(
      goal
          .toCreateRequest(_quote(SavingsProductType.smartSave, 180))!
          .toJson()['planName'],
      goalName,
    );
    expect(
      deposit
          .toCreateRequest(_quote(SavingsProductType.fixed, 90))!
          .toJson()['planName'],
      depositName,
    );
    expect(
      SavingsPlan.tryParse({..._plan(), 'planName': goalName})!.name,
      goalName,
    );
    expect(
      SavingsPlan.tryParse({
        ..._plan(),
        'productCode': 'boctrustFixedDeposit',
        'planName': depositName,
      })!.name,
      depositName,
    );
  });

  test('liquidation sends no body and reads the payout', () async {
    final core = _Core({
      'planId': 'p1',
      'status': 'liquidated',
      'amountPaidOut': '5117.40',
      'interestAccrued': '120.40',
      'earlyWithdrawalFee': '3.01',
      'interestPaid': '117.39',
      'interestPending': '0.00',
    });

    final result = await _service(core).liquidatePlan('p1');

    final request = core.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/me/savings-plans/p1/liquidate');
    expect(request.data, isNull);
    final data = result.data!;
    expect(data.status, SavingsPlanStatus.liquidated);
    expect(data.amountPaidOut, '5117.40');
    expect(data.interestAccrued, '120.40');
    expect(data.earlyWithdrawalFee, '3.01');
    expect(data.interestPaid, '117.39');
    expect(data.interestPending, '0.00');
  });

  test(
    'a top-up still refreshes when its listener leaves while sending',
    () async {
      final reply = Completer<NotifierState<SavingsPlanActionResult>>();
      final service = _SlowFund(reply);
      _Accounts.loads = 0;
      var historyRefreshes = 0;
      final container = ProviderContainer(
        overrides: [
          coreSavingsPlanServiceProvider.overrideWithValue(service),
          customerBankAccountsProvider.overrideWith(_Accounts.new),
          refreshFlexTransactionHistoryProvider.overrideWithValue(() async {
            historyRefreshes++;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(savingsPlanDetailProvider('p1'), (_, _) {});
      await container.read(savingsPlanDetailProvider('p1').future);
      final sub = container.listen(savingsPlanActionProvider, (_, _) {});
      final sending = container
          .read(savingsPlanActionProvider.notifier)
          .fund('p1', '5.00');
      sub.close();
      // Let the provider dispose, as it would once the sheet is gone.
      await Future<void>.delayed(Duration.zero);

      reply.complete(
        const NotifierState.done(
          SavingsPlanActionResult(
            planId: 'p1',
            status: SavingsPlanStatus.active,
          ),
        ),
      );
      await sending;
      await container.read(savingsPlanDetailProvider('p1').future);

      expect(service.reads, 2);
      expect(_Accounts.loads, 1);
      expect(historyRefreshes, 1);
    },
  );

  test('a top-up is not sent while Boc Flex is frozen', () async {
    final service = _SlowFund(Completer());
    final container = ProviderContainer(
      overrides: [
        coreSavingsPlanServiceProvider.overrideWithValue(service),
        customerBankAccountsProvider.overrideWith(
          () => _Accounts(CoreAccountStatus.frozen),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(savingsPlanActionProvider, (_, _) {});
    await container.read(savingsPlanActionProvider.notifier).fund('p1', '5.00');

    final state = container.read(savingsPlanActionProvider);
    expect(service.funds, 0);
    expect(state.phase, SavingsPlanActionPhase.failed);
    expect(state.message, kSavingsPausedMessage);
  });

  test(
    'a withdrawal is not sent while its savings account is frozen',
    () async {
      final service = _SlowFund(Completer());
      final container = ProviderContainer(
        overrides: [
          coreSavingsPlanServiceProvider.overrideWithValue(service),
          customerBankAccountsProvider.overrideWith(
            () => _Accounts(CoreAccountStatus.active, CoreAccountStatus.frozen),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(savingsPlanActionProvider, (_, _) {});
      await container
          .read(savingsPlanActionProvider.notifier)
          .liquidate('p1', accountNumber: '2200012345');

      final state = container.read(savingsPlanActionProvider);
      expect(service.liquidations, 0);
      expect(state.phase, SavingsPlanActionPhase.failed);
      expect(state.message, kSavingsAccountFrozenMessage);
    },
  );

  test('a withdrawal started while a top-up sends sends nothing', () async {
    final reply = Completer<NotifierState<SavingsPlanActionResult>>();
    final service = _SlowFund(reply);
    final container = ProviderContainer(
      overrides: [
        coreSavingsPlanServiceProvider.overrideWithValue(service),
        customerBankAccountsProvider.overrideWith(_Accounts.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(savingsPlanActionProvider, (_, _) {});
    final actions = container.read(savingsPlanActionProvider.notifier);
    final funding = actions.fund('p1', '5.00');
    await actions.liquidate('p1');
    reply.complete(
      const NotifierState.done(
        SavingsPlanActionResult(planId: 'p1', status: SavingsPlanStatus.active),
      ),
    );
    await funding;

    final state = container.read(savingsPlanActionProvider);
    expect(service.liquidations, 0);
    expect(state.phase, SavingsPlanActionPhase.done);
    expect(
      state.viewFor(SavingsPlanAction.liquidate, 'p1').phase,
      SavingsPlanActionPhase.idle,
    );
  });

  test('delete sends one DELETE and never liquidates', () async {
    final core = _Core({
      'planId': 'p/1',
      'status': 'cancelled',
      'deletedAt': '2026-10-24T10:00:00Z',
    });
    final container = ProviderContainer(
      overrides: [
        coreSavingsPlanServiceProvider.overrideWithValue(_service(core)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(savingsPlanActionProvider, (_, _) {});
    final actions = container.read(savingsPlanActionProvider.notifier);

    await actions.deletePlan('p/1');

    var state = container.read(savingsPlanActionProvider);
    expect(state.phase, SavingsPlanActionPhase.done);
    expect(state.deleteResult?.status, SavingsPlanStatus.cancelled);
    final request = core.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/me/savings-plans/p%2F1');
    expect(request.data, isNull);
    expect(core.requests.any((r) => r.path.contains('liquidate')), isFalse);

    // A reply that cannot be read is an unknown outcome and is not resent.
    final unreadable = _Core({'status': 'cancelled'});
    final other = ProviderContainer(
      overrides: [
        coreSavingsPlanServiceProvider.overrideWithValue(_service(unreadable)),
      ],
    );
    addTearDown(other.dispose);
    other.listen(savingsPlanActionProvider, (_, _) {});
    await other.read(savingsPlanActionProvider.notifier).deletePlan('p1');

    state = other.read(savingsPlanActionProvider);
    expect(state.phase, SavingsPlanActionPhase.unknown);
    expect(unreadable.requests, hasLength(1));
    expect(unreadable.requests.single.method, 'DELETE');
  });
}
