import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core_api_endpoints.dart';
import '../../../app/core_network.dart';
import '../../../app/error_reporting.dart';
import '../../../app/network.dart';
import '../../../app/services.dart';
import '../../core_banking/model/core_json.dart';
import '../model/interest_accrual_models.dart';
import '../model/savings_plan_models.dart';

const _plansUnavailable = 'Savings plans are not available right now.';

final coreSavingsPlanServiceProvider = Provider<CoreSavingsPlanService>(
  (ref) => CoreSavingsPlanService(ref.watch(coreApiServiceProvider)),
);

/// Reads the customer's Core savings plans. Requests and replies are logged in
/// full on staging; the logger's key rules still apply.
///
/// A null [_api] means `CORE_BASE_URL` is not configured; every read then
/// reports blocked.
class CoreSavingsPlanService {
  const CoreSavingsPlanService(this._api);
  final ApiService? _api;

  static const _getPlansLabel = ApiCallLabel(
    feature: 'savings',
    action: 'view_savings_plans',
    stage: 'load',
    endpoint: CoreApiEndpoints.savingsPlans,
  );
  static const _getPlanLabel = ApiCallLabel(
    feature: 'savings',
    action: 'view_savings_plan',
    stage: 'load',
    endpoint: CoreApiEndpoints.savingsPlanTemplate,
  );
  static const _getPlanAccrualsLabel = ApiCallLabel(
    feature: 'savings',
    action: 'view_plan_interest',
    stage: 'load',
    endpoint: CoreApiEndpoints.savingsPlanAccrualsTemplate,
  );
  static const _getSavingsProductsLabel = ApiCallLabel(
    feature: 'savings',
    action: 'create_savings_plan',
    stage: 'load_products',
    endpoint: CoreApiEndpoints.savingsProducts,
  );
  static const _quoteLabel = ApiCallLabel(
    feature: 'savings',
    action: 'create_savings_plan',
    stage: 'quote',
    endpoint: CoreApiEndpoints.savingsProductQuoteTemplate,
  );
  static const _createPlanLabel = ApiCallLabel(
    feature: 'savings',
    action: 'create_savings_plan',
    stage: 'submit',
    endpoint: CoreApiEndpoints.savingsPlans,
  );
  static const _fundPlanLabel = ApiCallLabel(
    feature: 'savings',
    action: 'fund_savings_plan',
    stage: 'submit',
    endpoint: CoreApiEndpoints.savingsPlanFundTemplate,
  );
  static const _liquidatePlanLabel = ApiCallLabel(
    feature: 'savings',
    action: 'withdraw_savings_plan',
    stage: 'submit',
    endpoint: CoreApiEndpoints.savingsPlanLiquidateTemplate,
  );
  static const _deletePlanLabel = ApiCallLabel(
    feature: 'savings',
    action: 'delete_savings_plan',
    stage: 'submit',
    endpoint: CoreApiEndpoints.savingsPlanDeleteTemplate,
  );

  /// The caller's plans of [product], with the product's balance.
  Future<NotifierState<List<SavingsProductGroup>>> getPlans(
    SavingsProductType product,
  ) async {
    final api = _api;
    final code = product.coreCode;
    if (api == null || code == null) {
      return const NotifierState.blocked(_plansUnavailable);
    }
    return NotifierState.fromResponse(
      await api.getData<List<SavingsProductGroup>>(
        CoreApiEndpoints.savingsPlans,
        requestExtra: {apiCallLabelKey: _getPlansLabel},
        queryParameters: {'productCode': code},
        parser: SavingsProductGroup.listFromJson,
      ),
    );
  }

  /// One of the caller's plans with its history; 404 when it is not theirs.
  Future<NotifierState<SavingsPlanDetail>> getPlan(String planId) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_plansUnavailable);
    return NotifierState.fromResponse(
      await api.getData<SavingsPlanDetail>(
        CoreApiEndpoints.savingsPlan(planId),
        requestExtra: {apiCallLabelKey: _getPlanLabel},
        parser: SavingsPlanDetail.fromJson,
      ),
    );
  }

  /// One page of a plan's daily interest, newest first; 404 when the plan is
  /// not the caller's.
  Future<NotifierState<InterestAccrualPage>> getPlanAccruals(
    String planId, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_plansUnavailable);
    return NotifierState.fromResponse(
      await api.getData<InterestAccrualPage>(
        CoreApiEndpoints.savingsPlanAccruals(planId),
        requestExtra: {apiCallLabelKey: _getPlanAccrualsLabel},
        queryParameters: {'page': page, 'pageSize': pageSize},
        parser: (json) =>
            InterestAccrualPage.fromJson(json, baseKey: 'principalAmount'),
      ),
    );
  }

  /// The SmartSave and Fixed Deposit products a plan can be opened on.
  Future<NotifierState<List<SavingsPlanProduct>>> getSavingsProducts() async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_plansUnavailable);
    return NotifierState.fromResponse(
      await api.getData<List<SavingsPlanProduct>>(
        CoreApiEndpoints.savingsProducts,
        requestExtra: {apiCallLabelKey: _getSavingsProductsLabel},
        parser: SavingsPlanProduct.listFromJson,
      ),
    );
  }

  /// What Core would apply to a plan of [productCode] lasting [tenorDays] or
  /// maturing on [endDate]; exactly one must be given. 400 when the duration
  /// is out of range, 404 when the product is unknown or inactive.
  Future<NotifierState<SavingsPlanQuote>> quoteSavingsProduct(
    String productCode, {
    int? tenorDays,
    DateTime? endDate,
  }) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_plansUnavailable);
    if ((tenorDays == null) == (endDate == null)) {
      return const NotifierState.error('Choose how long you will save.');
    }
    return NotifierState.fromResponse(
      await api.getData<SavingsPlanQuote>(
        CoreApiEndpoints.savingsProductQuote(productCode),
        requestExtra: {apiCallLabelKey: _quoteLabel},
        queryParameters: endDate == null
            ? {'tenorDays': tenorDays}
            : {'endDate': formatCoreDateOnly(endDate)},
        parser: SavingsPlanQuote.fromJson,
      ),
    );
  }

  /// Creates a plan that Core funds from Boc Flex with the request's
  /// `amount`, and returns its `planId`. Never retried.
  Future<NotifierState<String>> createPlan(
    CreateSavingsPlanRequest request,
  ) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_plansUnavailable);
    return NotifierState.fromResponse(
      await api.postData<String>(
        CoreApiEndpoints.savingsPlans,
        requestExtra: {apiCallLabelKey: _createPlanLabel},
        data: request.toJson(),
        parser: (json) {
          final planId = json is Map ? coreText(json['planId']) : null;
          if (planId == null) throw const FormatException('Invalid plan.');
          return planId;
        },
      ),
    );
  }

  /// Tops up a plan from Boc Flex with [amountNaira], a Naira string. Never
  /// retried: a POST whose outcome is unknown must not run twice.
  Future<NotifierState<SavingsPlanActionResult>> fundPlan(
    String planId,
    String amountNaira,
  ) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_plansUnavailable);
    return NotifierState.fromResponse(
      await api.postData<SavingsPlanActionResult>(
        CoreApiEndpoints.savingsPlanFund(planId),
        requestExtra: {apiCallLabelKey: _fundPlanLabel},
        data: {'amount': amountNaira},
        parser: (json) {
          final result = SavingsPlanActionResult.fromJson(json);
          if (result == null) throw const FormatException('Invalid result.');
          return result;
        },
      ),
    );
  }

  /// Withdraws a plan early into Boc Flex. Core takes no body. Never retried.
  Future<NotifierState<SavingsPlanActionResult>> liquidatePlan(
    String planId,
  ) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_plansUnavailable);
    return NotifierState.fromResponse(
      await api.postData<SavingsPlanActionResult>(
        CoreApiEndpoints.savingsPlanLiquidate(planId),
        requestExtra: {apiCallLabelKey: _liquidatePlanLabel},
        parser: (json) {
          final result = SavingsPlanActionResult.fromJson(json);
          if (result == null) throw const FormatException('Invalid result.');
          return result;
        },
      ),
    );
  }

  /// Soft-deletes a plan with no money in it. Core takes no body: 404 when it
  /// is not the caller's, 409 when money remains or interest is still being
  /// paid. Never retried: a delete whose outcome is unknown is reconciled by
  /// refreshing, not resending.
  Future<NotifierState<SavingsPlanDeleteResult>> deletePlan(
    String planId,
  ) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_plansUnavailable);
    return NotifierState.fromResponse(
      await api.deleteData<SavingsPlanDeleteResult>(
        CoreApiEndpoints.savingsPlanDelete(planId),
        requestExtra: {apiCallLabelKey: _deletePlanLabel},
        parser: SavingsPlanDeleteResult.fromJson,
      ),
    );
  }
}
