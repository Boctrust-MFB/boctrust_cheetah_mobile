import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core_api_endpoints.dart';
import '../../../app/core_network.dart';
import '../../../app/error_reporting.dart';
import '../../../app/network.dart';
import '../../../app/services.dart';
import '../model/flex_interest_models.dart';
import '../model/interest_accrual_models.dart';

final coreFlexInterestServiceProvider = Provider<CoreFlexInterestService>(
  (ref) => CoreFlexInterestService(ref.watch(coreApiServiceProvider)),
);

/// Reads the customer's BocFlex interest summary. A 404 means the customer
/// has no Flex account.
///
/// A null [_api] means `CORE_BASE_URL` is not configured; the read then
/// reports blocked.
class CoreFlexInterestService {
  const CoreFlexInterestService(this._api);
  final ApiService? _api;

  static const _getInterestLabel = ApiCallLabel(
    feature: 'savings',
    action: 'view_flex_interest',
    stage: 'load',
    endpoint: CoreApiEndpoints.flexInterest,
  );
  static const _getAccrualsLabel = ApiCallLabel(
    feature: 'savings',
    action: 'view_flex_interest',
    stage: 'load_accruals',
    endpoint: CoreApiEndpoints.flexInterestAccruals,
  );

  Future<NotifierState<FlexInterest>> getInterest() async {
    final api = _api;
    if (api == null) {
      return const NotifierState.blocked(
        'Flex interest is not available right now.',
      );
    }
    return NotifierState.fromResponse(
      await api.getData<FlexInterest>(
        CoreApiEndpoints.flexInterest,
        requestExtra: {apiCallLabelKey: _getInterestLabel},
        parser: FlexInterest.fromJson,
      ),
    );
  }

  /// One page of the Flex account's daily interest, newest first.
  Future<NotifierState<InterestAccrualPage>> getAccruals({
    int page = 1,
    int pageSize = 30,
  }) async {
    final api = _api;
    if (api == null) {
      return const NotifierState.blocked(
        'Flex interest is not available right now.',
      );
    }
    return NotifierState.fromResponse(
      await api.getData<InterestAccrualPage>(
        CoreApiEndpoints.flexInterestAccruals,
        requestExtra: {apiCallLabelKey: _getAccrualsLabel},
        queryParameters: {'page': page, 'pageSize': pageSize},
        parser: (json) =>
            InterestAccrualPage.fromJson(json, baseKey: 'balance'),
      ),
    );
  }
}
