import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core_api_endpoints.dart';
import '../../../app/core_network.dart';
import '../../../app/error_reporting.dart';
import '../../../app/interceptors.dart';
import '../../../app/network.dart';
import '../../../app/services.dart';
import '../model/account_freeze_models.dart';
import '../model/bank_product_models.dart';
import '../model/core_account_statement.dart';
import '../model/core_account_summary.dart';
import '../model/core_account_transactions.dart';
import '../model/core_json.dart';
import '../model/customer_bank_account_models.dart';

const _coreUnavailable = 'Account services are not available right now.';

/// The core banking system took 24 seconds for a three-week statement on
/// staging; a twelve-month one can run past the 30 second default.
const _statementTimeout = Duration(minutes: 2);

final coreAccountServiceProvider = Provider<CoreAccountService>(
  (ref) => CoreAccountService(ref.watch(coreApiServiceProvider)),
);

/// Reads the customer's Core accounts and the Core product catalogue.
///
/// A null [_api] means `CORE_BASE_URL` is not configured; every read then
/// reports blocked rather than throwing or inventing empty data.
class CoreAccountService {
  const CoreAccountService(this._api);
  final ApiService? _api;

  static const _bankAccountsLabel = ApiCallLabel(
    feature: 'accounts',
    action: 'view_accounts',
    stage: 'load',
    endpoint: CoreApiEndpoints.bankAccounts,
  );
  static const _bankAccountLabel = ApiCallLabel(
    feature: 'accounts',
    action: 'view_account',
    stage: 'load',
    endpoint: CoreApiEndpoints.bankAccountTemplate,
  );
  static const _accountSummaryLabel = ApiCallLabel(
    feature: 'accounts',
    action: 'view_account_summary',
    stage: 'load',
    endpoint: CoreApiEndpoints.bankAccountSummaryTemplate,
  );
  static const _accountTransactionsLabel = ApiCallLabel(
    feature: 'accounts',
    action: 'view_transactions',
    stage: 'load',
    endpoint: CoreApiEndpoints.bankAccountTransactionsTemplate,
  );
  static const _accountStatementLabel = ApiCallLabel(
    feature: 'accounts',
    action: 'view_statement',
    stage: 'load',
    endpoint: CoreApiEndpoints.bankAccountStatementTemplate,
  );
  static const _bankProductsLabel = ApiCallLabel(
    feature: 'accounts',
    action: 'view_bank_products',
    stage: 'load',
    endpoint: CoreApiEndpoints.bankProducts,
  );
  static const _freezeLabel = ApiCallLabel(
    feature: 'accounts',
    action: 'freeze_account',
    stage: 'submit',
    endpoint: CoreApiEndpoints.bankAccountFreezeTemplate,
  );
  static const _unfreezeOtpLabel = ApiCallLabel(
    feature: 'accounts',
    action: 'unfreeze_account',
    stage: 'send_otp',
    endpoint: CoreApiEndpoints.bankAccountUnfreezeOtpTemplate,
  );
  static const _unfreezeLabel = ApiCallLabel(
    feature: 'accounts',
    action: 'unfreeze_account',
    stage: 'submit',
    endpoint: CoreApiEndpoints.bankAccountUnfreezeTemplate,
  );

  Future<NotifierState<CustomerBankAccountsData>> getBankAccounts() async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_coreUnavailable);
    return NotifierState.fromResponse(
      await api.getData<CustomerBankAccountsData>(
        CoreApiEndpoints.bankAccounts,
        parser: CustomerBankAccountsData.fromJson,
        requestExtra: {apiCallLabelKey: _bankAccountsLabel},
      ),
    );
  }

  /// One of the caller's accounts with a live balance. A number that is not
  /// ten digits is never sent.
  Future<NotifierState<CustomerBankAccount>> getBankAccount(
    String accountNumber,
  ) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_coreUnavailable);
    if (!isCoreAccountNumber(accountNumber)) {
      return const NotifierState.error('Account not found.');
    }
    return NotifierState.fromResponse(
      await api.getData<CustomerBankAccount>(
        CoreApiEndpoints.bankAccount(accountNumber),
        parser: (json) =>
            CustomerBankAccount.tryParse(json) ??
            (throw const FormatException('Invalid account.')),
        requestExtra: {
          LoggingInterceptor.privacySensitivePathKey:
              CoreApiEndpoints.bankAccountTemplate,
          apiCallLabelKey: _bankAccountLabel,
        },
      ),
    );
  }

  /// A live summary of one of the caller's accounts. A number that is not
  /// ten digits is never sent.
  Future<NotifierState<CoreAccountSummary>> getAccountSummary(
    String accountNumber,
  ) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_coreUnavailable);
    if (!isCoreAccountNumber(accountNumber)) {
      return const NotifierState.error('Account not found.');
    }
    return NotifierState.fromResponse(
      await api.getData<CoreAccountSummary>(
        CoreApiEndpoints.bankAccountSummary(accountNumber),
        parser: CoreAccountSummary.fromJson,
        requestExtra: {
          LoggingInterceptor.privacySensitivePathKey:
              CoreApiEndpoints.bankAccountSummaryTemplate,
          apiCallLabelKey: _accountSummaryLabel,
        },
      ),
    );
  }

  /// One page of live transaction rows for one of the caller's accounts over
  /// [range].
  Future<NotifierState<CoreTransactionPage>> getAccountTransactions(
    String accountNumber,
    CoreHistoryRange range, {
    int page = 1,
    int pageSize = 20,
    DateTime? today,
  }) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_coreUnavailable);
    if (!isCoreAccountNumber(accountNumber)) {
      return const NotifierState.error('Account not found.');
    }
    final (:fromDate, :toDate) = range.window(today ?? DateTime.now());
    return NotifierState.fromResponse(
      await api.getData<CoreTransactionPage>(
        CoreApiEndpoints.bankAccountTransactions(accountNumber),
        queryParameters: {
          'fromDate': fromDate,
          'toDate': toDate,
          'page': page,
          'pageSize': pageSize,
        },
        parser: CoreTransactionPage.fromJson,
        requestExtra: {apiCallLabelKey: _accountTransactionsLabel},
      ),
    );
  }

  /// A PDF statement of one of the caller's accounts over
  /// [fromDate]..[toDate]. A number that is not ten digits, or a range Core
  /// would reject, is never sent.
  Future<NotifierState<CoreAccountStatement>> getAccountStatement(
    String accountNumber, {
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_coreUnavailable);
    if (!isCoreAccountNumber(accountNumber)) {
      return const NotifierState.error('Account not found.');
    }
    final rangeError = coreStatementRangeError(
      fromDate,
      toDate,
      today: DateTime.now(),
    );
    if (rangeError != null) return NotifierState.error(rangeError);
    final reply = NotifierState.fromResponse(
      await api.getData<CoreAccountStatementReply>(
        CoreApiEndpoints.bankAccountStatement(accountNumber),
        queryParameters: {
          'fromDate': formatCoreDateOnly(fromDate),
          'toDate': formatCoreDateOnly(toDate),
        },
        parser: CoreAccountStatementReply.fromJson,
        requestExtra: {
          LoggingInterceptor.privacySensitivePathKey:
              CoreApiEndpoints.bankAccountStatementTemplate,
          apiCallLabelKey: _accountStatementLabel,
        },
        receiveTimeout: _statementTimeout,
      ),
    );
    final parsed = reply.data;
    if (!reply.isDone || parsed == null) {
      return NotifierState<CoreAccountStatement>(
        status: reply.status,
        message: reply.message,
        statusCode: reply.statusCode,
        errorCode: reply.errorCode,
        errors: reply.errors,
        meta: reply.meta,
        noAuth: reply.noAuth,
      );
    }
    // A statement can be megabytes of base64; decode it off the UI isolate.
    // Invalid base64, an empty PDF, or a decode that fails outright (isolate
    // spawn, memory) is an invalid reply, never a crash.
    try {
      final bytes = await compute(base64Decode, parsed.content);
      return NotifierState.done(
        parsed.withBytes(bytes),
        statusCode: reply.statusCode,
      );
    } on Object {
      return const NotifierState.error('The server response was invalid.');
    }
  }

  Future<NotifierState<List<CoreBankProduct>>> getBankProducts() async {
    final api = _api;
    if (api == null) return const NotifierState.blocked(_coreUnavailable);
    return NotifierState.fromResponse(
      await api.getData<List<CoreBankProduct>>(
        CoreApiEndpoints.bankProducts,
        parser: CoreBankProduct.listFromJson,
        requestExtra: {apiCallLabelKey: _bankProductsLabel},
      ),
    );
  }

  /// Freezes [accountNumber]. The PIN goes only in this request's body.
  Future<AccountFreezeOutcome<AccountFreezeResult>> freezeAccount(
    String accountNumber,
    String transactionPin,
  ) => _freezeWrite(
    accountNumber,
    CoreApiEndpoints.bankAccountFreeze,
    CoreApiEndpoints.bankAccountFreezeTemplate,
    _freezeLabel,
    {'transactionPin': transactionPin},
    AccountFreezeResult.fromJson,
  );

  /// Asks Core to send the code that confirms an unfreeze. Calling it again
  /// resends; there is no separate route.
  Future<AccountFreezeOutcome<UnfreezeOtpReply>> sendUnfreezeOtp(
    String accountNumber,
  ) => _freezeWrite(
    accountNumber,
    CoreApiEndpoints.bankAccountUnfreezeOtp,
    CoreApiEndpoints.bankAccountUnfreezeOtpTemplate,
    _unfreezeOtpLabel,
    null,
    UnfreezeOtpReply.fromJson,
  );

  /// Unfreezes [accountNumber]. The PIN and code go only in this request's
  /// body.
  Future<AccountFreezeOutcome<AccountFreezeResult>> unfreezeAccount(
    String accountNumber,
    String transactionPin,
    String otpCode,
  ) => _freezeWrite(
    accountNumber,
    CoreApiEndpoints.bankAccountUnfreeze,
    CoreApiEndpoints.bankAccountUnfreezeTemplate,
    _unfreezeLabel,
    {'transactionPin': transactionPin, 'otpCode': otpCode},
    AccountFreezeResult.fromJson,
  );

  /// Sends exactly one POST and never retries. The logger is given only the
  /// path template, so the PIN, the code and Core's staging-only `otpCode`
  /// never reach a log line.
  Future<AccountFreezeOutcome<T>> _freezeWrite<T>(
    String accountNumber,
    String Function(String accountNumber) path,
    String template,
    ApiCallLabel label,
    Map<String, Object?>? body,
    T Function(Object? json) parser,
  ) async {
    if (!isCoreAccountNumber(accountNumber)) {
      return FreezeNotFound<T>();
    }
    final api = _api;
    if (api == null) return FreezeUncertain<T>();
    final response = await api.postData<T>(
      path(accountNumber),
      data: body,
      parser: parser,
      requestExtra: {
        LoggingInterceptor.privacySensitivePathKey: template,
        apiCallLabelKey: label,
      },
    );
    if (response.status == ServiceStatus.success && response.data is T) {
      return FreezeSucceeded<T>(response.data as T);
    }
    // A 401 the client produced for an expired session was never sent.
    if (response.errorCode == kLocalSessionExpiredCode) {
      return FreezeUncertain<T>();
    }
    return switch (response.statusCode) {
      401 => FreezeWrongCredentials<T>(),
      403 => FreezeBankFrozen<T>(),
      404 => FreezeNotFound<T>(),
      409 => FreezeConflict<T>(),
      _ => FreezeUncertain<T>(),
    };
  }
}
