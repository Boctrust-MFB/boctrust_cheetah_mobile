import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core_api_endpoints.dart';
import '../../../app/core_network.dart';
import '../../../app/error_reporting.dart';
import '../../../app/network.dart';
import '../../../app/services.dart';
import '../model/bill_models.dart';
import '../model/core_submission_models.dart';

const _billsUnavailable = 'Bill payments are not available right now.';

final coreBillServiceProvider = Provider<CoreBillService>(
  (ref) => CoreBillService(ref.watch(coreApiServiceProvider)),
);

/// Bill catalogues and payments from the caller's BocFlex account.
class CoreBillService {
  const CoreBillService(this._api);
  final ApiService? _api;

  static const _categoriesLabel = ApiCallLabel(
    feature: 'bills',
    action: 'view_biller_categories',
    stage: 'load',
    endpoint: CoreApiEndpoints.billerCategories,
  );
  static const _billersLabel = ApiCallLabel(
    feature: 'bills',
    action: 'view_billers',
    stage: 'load',
    endpoint: CoreApiEndpoints.billers,
  );
  static const _paymentItemsLabel = ApiCallLabel(
    feature: 'bills',
    action: 'view_payment_items',
    stage: 'load',
    endpoint: CoreApiEndpoints.paymentItems,
  );
  static const _payLabel = ApiCallLabel(
    feature: 'bills',
    action: 'pay_bill',
    stage: 'submit',
    endpoint: CoreApiEndpoints.billPayments,
  );

  Future<NotifierState<T>> _read<T>(
    String path,
    ApiCallLabel label,
    T Function(Object? json) parser,
  ) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_billsUnavailable);
    return NotifierState.fromResponse(
      await api.getData<T>(
        path,
        parser: parser,
        requestExtra: {apiCallLabelKey: label},
      ),
    );
  }

  Future<NotifierState<List<BillerCategory>>> getCategories() => _read(
    CoreApiEndpoints.billerCategories,
    _categoriesLabel,
    BillerCategory.listFromJson,
  );

  Future<NotifierState<List<Biller>>> getBillers() =>
      _read(CoreApiEndpoints.billers, _billersLabel, Biller.listFromJson);

  Future<NotifierState<List<PaymentItem>>> getPaymentItems() => _read(
    CoreApiEndpoints.paymentItems,
    _paymentItemsLabel,
    PaymentItem.listFromJson,
  );

  /// Sends exactly one POST and never retries.
  Future<ServiceResponse<CoreTransferAck>> pay(
    BillPaymentDraft draft, {
    required String transactionPin,
  }) async {
    if (!RegExp(r'^\d{4}$').hasMatch(transactionPin)) {
      return const ServiceResponse.error('Enter a valid transaction PIN.');
    }
    final api = _api;
    if (api == null) {
      return const ServiceResponse<CoreTransferAck>(
        status: ServiceStatus.blocked,
        message: _billsUnavailable,
      );
    }
    return api.postData<CoreTransferAck>(
      CoreApiEndpoints.billPayments,
      data: {...draft.toJson(), 'transactionPin': transactionPin},
      parser: CoreTransferAck.fromJson,
      requestExtra: {apiCallLabelKey: _payLabel},
    );
  }
}
