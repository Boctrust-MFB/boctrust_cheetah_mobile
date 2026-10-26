import 'package:equatable/equatable.dart';

import '../../../app/feature_capability.dart';
import '../../core_banking/model/core_json.dart';
import '../../core_banking/model/core_money.dart';

/// The four Boc savings products. Route paths keep their legacy names
/// (target, lock, group); these are the customer-facing names.
enum SavingsProductType {
  flex('Boc Flex Savings', null, null),
  smartSave('Boc SmartSave', FeatureCapability.smartSaveCreate, 'bocSmartSave'),
  fixed(
    'Boc Fixed Deposit',
    FeatureCapability.fixedDepositCreate,
    'boctrustFixedDeposit',
  ),
  padi('Boc Padi', FeatureCapability.padiCreate, null);

  const SavingsProductType(
    this.displayName,
    this.createCapability,
    this.coreCode,
  );

  final String displayName;

  /// Gates creating a new plan of this type; Flex has no create step.
  final FeatureCapability? createCapability;

  /// The Core `productCode` of a product with savings plans; Flex has no
  /// plans and Padi has no plan routes.
  final String? coreCode;

  static SavingsProductType? fromCoreCode(Object? code) {
    for (final type in values) {
      if (type.coreCode != null && type.coreCode == code) return type;
    }
    return null;
  }
}

enum SavingsFrequency {
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly');

  const SavingsFrequency(this.label);
  final String label;
}

enum SavingsPlanStatus {
  pendingFunding('pending_funding', 'Awaiting funding'),
  active('active', 'Active'),
  matured('matured', 'Matured'),
  liquidated('liquidated', 'Withdrawn'),
  cancelled('cancelled', 'Cancelled'),

  /// A status this build does not know. Shown as unavailable.
  unknown('unknown', 'Unavailable');

  const SavingsPlanStatus(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static SavingsPlanStatus parse(Object? value) {
    for (final status in values) {
      if (status != unknown && status.wireValue == value) return status;
    }
    return unknown;
  }
}

int? _days(Object? value) => value is int && value > 0 ? value : null;

/// A customer's savings plan as Core reports it. Amounts are Naira decimal
/// strings; the client never computes balances or
/// interest.
class SavingsPlan extends Equatable {
  const SavingsPlan({
    required this.id,
    required this.type,
    required this.name,
    required this.status,
    this.principal,
    this.target,
    this.interestEarned,
    this.accruedInterest,
    this.earlyWithdrawalFeePercent,
    this.rate,
    this.tenorDays,
    this.maturityDate,
    this.startDate,
    this.saveFrequency,
    this.recurringAmount,
    this.projectedInterest,
  });

  final String id;
  final SavingsProductType type;
  final String name;

  /// Null when Core's amount cannot be read; the plan is still shown.
  final String? principal;
  final SavingsPlanStatus status;
  final String? target;
  final String? interestEarned;

  /// Interest accrued so far (Naira), paid on early withdrawal less the fee.
  final String? accruedInterest;

  /// The early-withdrawal fee on that interest, a percent as published.
  final String? earlyWithdrawalFeePercent;

  /// Percent, as published.
  final String? rate;
  final int? tenorDays;
  final DateTime? maturityDate;
  final DateTime? startDate;

  /// How often the customer chose to save; null when Core has none.
  final SavingsFrequency? saveFrequency;
  final String? recurringAmount;

  /// Core's estimate of the interest at maturity (Naira).
  final String? projectedInterest;

  /// A plan of a product this app knows, else null.
  static SavingsPlan? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = coreText(json['planId']);
    final type = SavingsProductType.fromCoreCode(json['productCode']);
    if (id == null || type == null) return null;
    return SavingsPlan(
      id: id,
      type: type,
      name: coreText(json['planName']) ?? type.displayName,
      principal: coreNaira(json['principalAmount']),
      status: SavingsPlanStatus.parse(json['status']),
      target: coreNaira(json['targetAmount']),
      interestEarned: coreNaira(json['interestEarned']),
      accruedInterest: coreNaira(json['accruedInterest']),
      earlyWithdrawalFeePercent: coreText(json['earlyWithdrawalFeePercent']),
      rate: coreText(json['currentInterestRatePercent']),
      tenorDays: _days(json['tenorDays']),
      maturityDate: DateTime.tryParse(coreText(json['maturityDate']) ?? ''),
      startDate: DateTime.tryParse(coreText(json['startDate']) ?? ''),
      saveFrequency: SavingsFrequency.values
          .asNameMap()[coreText(json['saveFrequency'])],
      recurringAmount: coreNaira(json['recurringAmount']),
      projectedInterest: coreNaira(json['projectedInterestAtMaturity']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    type,
    name,
    principal,
    status,
    target,
    interestEarned,
    accruedInterest,
    earlyWithdrawalFeePercent,
    rate,
    tenorDays,
    maturityDate,
    startDate,
    saveFrequency,
    recurringAmount,
    projectedInterest,
  ];
}

/// One product's plans with the product's account balance, as grouped by
/// `GET /me/savings-plans`.
class SavingsProductGroup extends Equatable {
  const SavingsProductGroup({
    required this.type,
    required this.productName,
    required this.plans,
    this.accountNumber,
    this.rate,
    this.defaultTenorDays,
  });

  final SavingsProductType type;
  final String productName;
  final List<SavingsPlan> plans;

  /// The product's account. Its balance is read from the account list,
  /// whose unit is verified, not from this reply's `accountBalance`.
  final String? accountNumber;
  final String? rate;
  final int? defaultTenorDays;

  static SavingsProductGroup? tryParse(Object? json) {
    if (json is! Map) return null;
    final type = SavingsProductType.fromCoreCode(json['productCode']);
    if (type == null) return null;
    final plans = json['plans'];
    return SavingsProductGroup(
      type: type,
      productName: coreText(json['productName']) ?? type.displayName,
      plans: List.unmodifiable(
        (plans is List ? plans : const [])
            .map(SavingsPlan.tryParse)
            .whereType<SavingsPlan>(),
      ),
      accountNumber: coreText(json['accountNumber']),
      rate: coreText(json['productInterestRatePercent']),
      defaultTenorDays: _days(json['defaultTenorDays']),
    );
  }

  /// Groups of known products, in server order.
  static List<SavingsProductGroup> listFromJson(Object? json) {
    if (json is! List) throw const FormatException('Missing savings plans.');
    return List.unmodifiable(
      json.map(tryParse).whereType<SavingsProductGroup>(),
    );
  }

  @override
  List<Object?> get props => [
    type,
    productName,
    plans,
    accountNumber,
    rate,
    defaultTenorDays,
  ];
}

enum SavingsPlanEventType {
  created('created', 'Created'),
  topUp('top_up', 'Top-up'),
  interestCredit('interest_credit', 'Interest'),
  withdrawal('withdrawal', 'Withdrawal'),
  maturityPayout('maturity_payout', 'Maturity payout'),
  liquidation('liquidation', 'Early withdrawal'),
  unknown('unknown', 'Activity');

  const SavingsPlanEventType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static SavingsPlanEventType parse(Object? value) {
    for (final type in values) {
      if (type != unknown && type.wireValue == value) return type;
    }
    return unknown;
  }
}

/// One entry in a plan's history. Its server reference is not kept.
class SavingsPlanEvent extends Equatable {
  const SavingsPlanEvent({required this.type, this.amount, this.createdAt});

  final SavingsPlanEventType type;
  final String? amount;
  final DateTime? createdAt;

  static SavingsPlanEvent? tryParse(Object? json) {
    if (json is! Map) return null;
    return SavingsPlanEvent(
      type: SavingsPlanEventType.parse(json['eventType']),
      amount: coreNaira(json['amount']),
      createdAt: DateTime.tryParse(coreText(json['createdAt']) ?? ''),
    );
  }

  @override
  List<Object?> get props => [type, amount, createdAt];
}

/// A plan with its history, from `GET /me/savings-plans/{planId}`.
class SavingsPlanDetail extends Equatable {
  const SavingsPlanDetail({
    required this.plan,
    this.events = const [],
    this.accountNumber,
  });

  final SavingsPlan plan;
  final List<SavingsPlanEvent> events;

  /// The product account the plan belongs to, when Core states it.
  final String? accountNumber;

  factory SavingsPlanDetail.fromJson(Object? json) {
    final plan = SavingsPlan.tryParse(json);
    if (plan == null) throw const FormatException('Invalid savings plan.');
    final events = (json as Map)['events'];
    return SavingsPlanDetail(
      plan: plan,
      accountNumber: coreText(json['accountNumber']),
      events: List.unmodifiable(
        (events is List ? events : const [])
            .map(SavingsPlanEvent.tryParse)
            .whereType<SavingsPlanEvent>(),
      ),
    );
  }

  @override
  List<Object?> get props => [plan, events, accountNumber];
}

/// What Core reports after a soft delete. [status] and [deletedAt] are kept
/// for the record only; nothing is driven from them.
class SavingsPlanDeleteResult extends Equatable {
  const SavingsPlanDeleteResult({
    required this.planId,
    this.status,
    this.deletedAt,
  });

  final String planId;

  /// `matured`, `liquidated` or `cancelled`; null when absent or not one of
  /// those.
  final SavingsPlanStatus? status;
  final DateTime? deletedAt;

  /// Throws [FormatException] when [value] is not an object with a `planId`.
  factory SavingsPlanDeleteResult.fromJson(Object? value) {
    final planId = value is Map ? coreText(value['planId']) : null;
    if (value is! Map || planId == null) {
      throw const FormatException('Invalid delete result.');
    }
    final status = SavingsPlanStatus.parse(value['status']);
    final deletedAt = value['deletedAt'];
    return SavingsPlanDeleteResult(
      planId: planId,
      status: switch (status) {
        SavingsPlanStatus.matured ||
        SavingsPlanStatus.liquidated ||
        SavingsPlanStatus.cancelled => status,
        _ => null,
      },
      deletedAt: deletedAt is String ? DateTime.tryParse(deletedAt) : null,
    );
  }

  @override
  List<Object?> get props => [planId, status, deletedAt];
}

/// What Core reports after a plan action (top-up, early withdrawal,
/// creation). Amounts are Naira decimal strings; any may be absent.
class SavingsPlanActionResult extends Equatable {
  const SavingsPlanActionResult({
    required this.planId,
    required this.status,
    this.principalAmount,
    this.amountPaidOut,
    this.interestAccrued,
    this.earlyWithdrawalFee,
    this.interestPaid,
    this.interestPending,
  });

  final String planId;
  final SavingsPlanStatus status;
  final String? principalAmount;
  final String? amountPaidOut;
  final String? interestAccrued;
  final String? earlyWithdrawalFee;
  final String? interestPaid;
  final String? interestPending;

  /// Null when [json] is not an object or has no `planId`.
  static SavingsPlanActionResult? fromJson(Object? json) {
    if (json is! Map) return null;
    final planId = coreText(json['planId']);
    if (planId == null) return null;
    return SavingsPlanActionResult(
      planId: planId,
      status: SavingsPlanStatus.parse(json['status']),
      principalAmount: coreNaira(json['principalAmount']),
      amountPaidOut: coreNaira(json['amountPaidOut']),
      interestAccrued: coreNaira(json['interestAccrued']),
      earlyWithdrawalFee: coreNaira(json['earlyWithdrawalFee']),
      interestPaid: coreNaira(json['interestPaid']),
      interestPending: coreNaira(json['interestPending']),
    );
  }

  @override
  List<Object?> get props => [
    planId,
    status,
    principalAmount,
    amountPaidOut,
    interestAccrued,
    earlyWithdrawalFee,
    interestPaid,
    interestPending,
  ];
}

/// Where a deposit or plan funding comes from.
enum FundingSource {
  wallet('BOCTRUST wallet'),
  flexSavings('Boc Flex Savings'),
  bankTransfer('Bank transfer');

  const FundingSource(this.label);
  final String label;
}

/// Month labels the wizard offers, with the days each stands for. Labels
/// only: a preset is offered when its days fall within the product's bounds,
/// and the quote decides the rate and minimum.
const savingsMonthPresetDays = {3: 90, 6: 180, 9: 270, 12: 365};

/// Core never accepts a plan longer than a year.
const _longestSavingsTenorDays = 365;

/// One rate and first-deposit band of a product. Amounts and the rate are
/// Core decimal strings.
class SavingsPlanTenor extends Equatable {
  const SavingsPlanTenor({
    required this.tenorDays,
    required this.interestRatePercent,
    required this.minAmount,
    this.maxAmount,
  });

  final int tenorDays;
  final String interestRatePercent;

  /// The smallest first deposit for this duration, in Naira.
  final String minAmount;

  /// The largest first deposit, in Naira; null when there is no maximum.
  final String? maxAmount;

  static SavingsPlanTenor? tryParse(Object? json) {
    if (json is! Map) return null;
    final days = _days(json['tenorDays']);
    final rate = coreText(json['interestRatePercent']);
    final min = coreNaira(json['minAmount']);
    if (days == null || rate == null || min == null) return null;
    return SavingsPlanTenor(
      tenorDays: days,
      interestRatePercent: rate,
      minAmount: min,
      maxAmount: coreNaira(json['maxAmount']),
    );
  }

  @override
  List<Object?> get props => [
    tenorDays,
    interestRatePercent,
    minAmount,
    maxAmount,
  ];
}

/// A product a plan can be opened on, from `GET /me/savings-products`.
class SavingsPlanProduct extends Equatable {
  const SavingsPlanProduct({
    required this.productCode,
    required this.productName,
    required this.planType,
    required this.earlyWithdrawalFeePercent,
    required this.tenors,
    this.description,
    this.minTenorDays,
    this.maxTenorDays,
  });

  final String productCode;
  final String productName;
  final String? description;

  /// `fixed_deposit` or `target_savings`, as Core sends it.
  final String planType;
  final String earlyWithdrawalFeePercent;
  final int? minTenorDays;
  final int? maxTenorDays;

  /// Rate and minimum-deposit bands, in Core order. Any length between the
  /// bounds is valid, not only these.
  final List<SavingsPlanTenor> tenors;

  /// The shortest plan Core accepts, in days: its stated bound, else the
  /// shortest band. A product with no bands is never offered, so the
  /// fallback of one day is never shown.
  int get shortestTenorDays {
    final stated = minTenorDays;
    if (stated != null) return stated;
    final days = [for (final tenor in tenors) tenor.tenorDays];
    return days.isEmpty ? 1 : days.reduce((a, b) => a < b ? a : b);
  }

  /// The longest plan Core accepts, in days: its stated bound, else the
  /// longest band, never more than a year.
  int get longestTenorDays {
    final days = [for (final tenor in tenors) tenor.tenorDays];
    final stated =
        maxTenorDays ??
        (days.isEmpty
            ? _longestSavingsTenorDays
            : days.reduce((a, b) => a > b ? a : b));
    return stated > _longestSavingsTenorDays
        ? _longestSavingsTenorDays
        : stated;
  }

  bool allowsTenor(int days) =>
      days >= shortestTenorDays && days <= longestTenorDays;

  /// The month presets whose days fall within this product's bounds.
  List<int> get presetMonths => [
    for (final MapEntry(key: months, value: days)
        in savingsMonthPresetDays.entries)
      if (allowsTenor(days)) months,
  ];

  /// The smallest first deposit of any band, for copy shown before a
  /// duration is chosen; the quote has the exact one.
  String? get lowestMinAmount {
    String? lowest;
    BigInt? lowestKobo;
    for (final tenor in tenors) {
      final kobo = BigInt.parse(balanceToKobo(tenor.minAmount)!);
      if (lowestKobo == null || kobo < lowestKobo) {
        lowest = tenor.minAmount;
        lowestKobo = kobo;
      }
    }
    return lowest;
  }

  static SavingsPlanProduct? tryParse(Object? json) {
    if (json is! Map) return null;
    final code = coreText(json['productCode']);
    final name = coreText(json['productName']);
    final planType = coreText(json['planType']);
    final fee = coreText(json['earlyWithdrawalFeePercent']);
    final tenors = json['tenors'];
    if (code == null ||
        name == null ||
        planType == null ||
        fee == null ||
        tenors is! List) {
      return null;
    }
    return SavingsPlanProduct(
      productCode: code,
      productName: name,
      description: coreText(json['description']),
      planType: planType,
      earlyWithdrawalFeePercent: fee,
      minTenorDays: _days(json['minTenorDays']),
      maxTenorDays: _days(json['maxTenorDays']),
      tenors: List.unmodifiable(
        tenors.map(SavingsPlanTenor.tryParse).whereType<SavingsPlanTenor>(),
      ),
    );
  }

  /// Every readable product, in Core order; a malformed row is dropped.
  static List<SavingsPlanProduct> listFromJson(Object? json) {
    if (json is! List) {
      throw const FormatException('Missing savings products.');
    }
    return List.unmodifiable(
      json.map(tryParse).whereType<SavingsPlanProduct>(),
    );
  }

  @override
  List<Object?> get props => [
    productCode,
    productName,
    description,
    planType,
    earlyWithdrawalFeePercent,
    minTenorDays,
    maxTenorDays,
    tenors,
  ];
}

/// What Core would apply to a plan of one duration, from
/// `GET /me/savings-products/{productCode}/quote`. It uses the same rules as
/// creating a plan, so its rate and first-deposit limits are authoritative.
class SavingsPlanQuote extends Equatable {
  const SavingsPlanQuote({
    required this.productCode,
    required this.productName,
    required this.tenorDays,
    required this.startDate,
    required this.endDate,
    required this.interestRatePercent,
    required this.minAmount,
    required this.earlyWithdrawalFeePercent,
    this.maxAmount,
  });

  final String productCode;
  final String productName;
  final int tenorDays;
  final DateTime startDate;

  /// The maturity date.
  final DateTime endDate;
  final String interestRatePercent;

  /// The smallest first deposit, in Naira.
  final String minAmount;

  /// The largest first deposit, in Naira; null when there is no maximum.
  final String? maxAmount;
  final String earlyWithdrawalFeePercent;

  factory SavingsPlanQuote.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Invalid savings quote.');
    final code = coreText(json['productCode']);
    final name = coreText(json['productName']);
    final days = _days(json['tenorDays']);
    final start = DateTime.tryParse(coreText(json['startDate']) ?? '');
    final end = DateTime.tryParse(coreText(json['endDate']) ?? '');
    final rate = coreText(json['interestRatePercent']);
    final min = coreNaira(json['minAmount']);
    final fee = coreText(json['earlyWithdrawalFeePercent']);
    final rawMax = json['maxAmount'];
    final max = coreNaira(rawMax);
    if (code == null ||
        name == null ||
        days == null ||
        start == null ||
        end == null ||
        rate == null ||
        min == null ||
        fee == null ||
        (rawMax != null && max == null)) {
      throw const FormatException('Invalid savings quote.');
    }
    return SavingsPlanQuote(
      productCode: code,
      productName: name,
      tenorDays: days,
      startDate: start,
      endDate: end,
      interestRatePercent: rate,
      minAmount: min,
      maxAmount: max,
      earlyWithdrawalFeePercent: fee,
    );
  }

  BigInt get _minKobo => BigInt.parse(balanceToKobo(minAmount)!);

  BigInt? get _maxKobo {
    final max = maxAmount;
    return max == null ? null : BigInt.parse(balanceToKobo(max)!);
  }

  /// Whether typed [text] is a first deposit Core accepts: at least
  /// [minAmount] and at most [maxAmount] when set.
  bool acceptsDeposit(String text) {
    final kobo = _typedKobo(text);
    final max = _maxKobo;
    return kobo != null && kobo >= _minKobo && (max == null || kobo <= max);
  }

  /// Whether typed [text] is a SmartSave target Core accepts: above the
  /// opening deposit ([minAmount]) and at most [maxAmount] when set.
  bool acceptsTarget(String text) {
    final kobo = _typedKobo(text);
    final max = _maxKobo;
    return kobo != null && kobo > _minKobo && (max == null || kobo <= max);
  }

  /// Whether typed [text] is more than a set [maxAmount].
  bool exceedsMax(String text) {
    final kobo = _typedKobo(text);
    final max = _maxKobo;
    return kobo != null && max != null && kobo > max;
  }

  @override
  List<Object?> get props => [
    productCode,
    productName,
    tenorDays,
    startDate,
    endDate,
    interestRatePercent,
    minAmount,
    maxAmount,
    earlyWithdrawalFeePercent,
  ];
}

BigInt? _typedKobo(String text) =>
    switch (parseNairaToKobo(text, maxKobo: savingsPlanMaxKobo)) {
      ValidMoney(:final minorUnits) => BigInt.parse(minorUnits),
      InvalidMoney() => null,
    };

/// Calendar dates are compared in UTC to count whole dates consistently even
/// on devices whose local clock crosses a daylight-saving boundary.
int daysUntilSavingsDate(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// The largest amount a plan form accepts (in Kobo); Core enforces the real
/// limits.
const savingsPlanMaxKobo = '100000000000';
const minimumPeriodicSavingsNaira = 1000;
const _minimumPeriodicSavingsKobo = '100000';

/// A typed Naira amount as Core's two-decimal string, or null when invalid.
String? savingsPlanNaira(String text) =>
    switch (parseNairaAmount(text, maxKobo: savingsPlanMaxKobo)) {
      ValidMoney(:final minorUnits) => minorUnits,
      InvalidMoney() => null,
    };

/// A scheduled contribution must be at least ₦1,000 per save.
bool periodicSavingsAmountValid(String text) =>
    switch (parseNairaToKobo(text, maxKobo: savingsPlanMaxKobo)) {
      ValidMoney(:final minorUnits) =>
        BigInt.parse(minorUnits) >= BigInt.parse(_minimumPeriodicSavingsKobo),
      InvalidMoney() => false,
    };

/// The body of POST /me/savings-plans. Amounts are Naira strings; null
/// fields are left out. Exactly one of [tenorDays] and [endDate] is set.
class CreateSavingsPlanRequest extends Equatable {
  const CreateSavingsPlanRequest({
    required this.productCode,
    required this.amount,
    this.tenorDays,
    this.endDate,
    this.planName,
    this.targetAmount,
    this.saveFrequency,
    this.recurringAmount,
  });

  final String productCode;
  final int? tenorDays;

  /// The maturity date the customer chose, sent as `YYYY-MM-DD`.
  final DateTime? endDate;

  /// The first deposit Core moves from Boc Flex at creation, in Naira.
  final String amount;
  final String? planName;
  final String? targetAmount;
  final SavingsFrequency? saveFrequency;
  final String? recurringAmount;

  Map<String, Object> toJson() => {
    'productCode': productCode,
    'tenorDays': ?tenorDays,
    if (endDate case final date?) 'endDate': formatCoreDateOnly(date),
    'amount': amount,
    'planName': ?planName,
    'targetAmount': ?targetAmount,
    'saveFrequency': ?saveFrequency?.name,
    'recurringAmount': ?recurringAmount,
  };

  @override
  List<Object?> get props => [
    productCode,
    tenorDays,
    endDate,
    amount,
    planName,
    targetAmount,
    saveFrequency,
    recurringAmount,
  ];
}

/// A plan being created. Every field stays client-side until the product's
/// create capability exists and the server confirms the plan.
class SavingsPlanDraft extends Equatable {
  const SavingsPlanDraft({
    required this.type,
    this.name = '',
    this.amount = '',
    this.durationMonths,
    this.customMaturityDate,
    this.autoSave = false,
    this.frequency,
    this.contributionDays = const {},
    this.recurringAmount = '',
    this.fundingSource,
    this.memberCount,
    this.startDate,
  });

  final SavingsProductType type;
  final String name;

  /// Target (SmartSave), principal (Fixed) or per-member contribution (Padi),
  /// as typed, in naira.
  final String amount;
  final int? durationMonths;
  final DateTime? customMaturityDate;
  final bool autoSave;
  final SavingsFrequency? frequency;
  final Set<int> contributionDays;

  /// SmartSave auto-save amount per save, as typed, in naira.
  final String recurringAmount;
  final FundingSource? fundingSource;
  final int? memberCount;
  final DateTime? startDate;

  SavingsPlanDraft copyWith({
    String? name,
    String? amount,
    int? durationMonths,
    DateTime? customMaturityDate,
    bool clearDurationMonths = false,
    bool clearCustomMaturityDate = false,
    bool? autoSave,
    SavingsFrequency? frequency,
    Set<int>? contributionDays,
    String? recurringAmount,
    FundingSource? fundingSource,
    int? memberCount,
    DateTime? startDate,
  }) => SavingsPlanDraft(
    type: type,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    durationMonths: clearDurationMonths
        ? null
        : durationMonths ?? this.durationMonths,
    customMaturityDate: clearCustomMaturityDate
        ? null
        : customMaturityDate ?? this.customMaturityDate,
    autoSave: autoSave ?? this.autoSave,
    frequency: frequency ?? this.frequency,
    contributionDays: contributionDays ?? this.contributionDays,
    recurringAmount: recurringAmount ?? this.recurringAmount,
    fundingSource: fundingSource ?? this.fundingSource,
    memberCount: memberCount ?? this.memberCount,
    startDate: startDate ?? this.startDate,
  );

  @override
  List<Object?> get props => [
    type,
    name,
    amount,
    durationMonths,
    customMaturityDate,
    autoSave,
    frequency,
    contributionDays,
    recurringAmount,
    fundingSource,
    memberCount,
    startDate,
  ];

  /// The chosen length in days when it is within [product]'s bounds: the
  /// preset's days, or the days from [today] to the custom maturity date.
  int? tenorDaysOn(DateTime today, SavingsPlanProduct product) {
    final customDate = customMaturityDate;
    final days = customDate == null
        ? savingsMonthPresetDays[durationMonths]
        : daysUntilSavingsDate(today, customDate);
    return days != null && product.allowsTenor(days) ? days : null;
  }

  /// What Core needs to create this plan on the duration [quote] covers.
  /// Null for Flex and Padi, for another product's quote, or when an amount
  /// cannot be read or falls outside the quote's limits. Fixed sends the
  /// typed principal as `amount`; SmartSave sends the quote's minimum, the
  /// opening deposit it shows. A custom maturity date is sent as `endDate`,
  /// so the plan matures on the date chosen; a preset sends the quote's
  /// `tenorDays`. Auto-save fields are SmartSave's only, and go only when
  /// auto-save is on.
  CreateSavingsPlanRequest? toCreateRequest(SavingsPlanQuote quote) {
    final code = type.coreCode;
    if (code == null || quote.productCode != code) return null;
    final planName = name.trim().isEmpty ? null : name.trim();
    final custom = customMaturityDate;
    final endDate = custom == null
        ? null
        : DateTime(custom.year, custom.month, custom.day);
    final tenorDays = endDate == null ? quote.tenorDays : null;
    final typed = savingsPlanNaira(amount);
    switch (type) {
      case SavingsProductType.fixed:
        if (typed == null || !quote.acceptsDeposit(amount)) return null;
        return CreateSavingsPlanRequest(
          productCode: code,
          tenorDays: tenorDays,
          endDate: endDate,
          amount: typed,
          planName: planName,
        );
      case SavingsProductType.smartSave:
        final recurring = autoSave ? savingsPlanNaira(recurringAmount) : null;
        if (autoSave &&
            (frequency == null ||
                recurring == null ||
                !periodicSavingsAmountValid(recurringAmount))) {
          return null;
        }
        if (typed == null || !quote.acceptsTarget(amount)) return null;
        return CreateSavingsPlanRequest(
          productCode: code,
          tenorDays: tenorDays,
          endDate: endDate,
          amount: quote.minAmount,
          planName: planName,
          targetAmount: typed,
          saveFrequency: autoSave ? frequency : null,
          recurringAmount: recurring,
        );
      case SavingsProductType.flex || SavingsProductType.padi:
        return null;
    }
  }
}
