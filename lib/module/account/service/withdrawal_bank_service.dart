import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api_endpoints.dart';
import '../../../app/error_reporting.dart';
import '../../../app/network.dart';
import '../../../app/services.dart';
import '../model/withdrawal_bank_models.dart';

final withdrawalBankServiceProvider = Provider<WithdrawalBankService>(
  (ref) => WithdrawalBankService(ref.watch(apiServiceProvider)),
);

/// The six published bank and withdrawal-account operations.
///
/// Everything goes through the authenticated User Service client. Resolution is
/// a server concern: no Paystack key is held here and no request is made
/// directly to a provider.
class WithdrawalBankService {
  const WithdrawalBankService(this._api);
  final ApiService _api;

  static const _template =
      '${ApiEndpoints.withdrawalBankAccounts}/{bankAccountId}';
  static const _getBanksLabel = ApiCallLabel(
    feature: 'linked_banks',
    action: 'view_bank_list',
    stage: 'load',
    endpoint: ApiEndpoints.banks,
  );
  static const _listAccountsLabel = ApiCallLabel(
    feature: 'linked_banks',
    action: 'view_linked_banks',
    stage: 'load',
    endpoint: ApiEndpoints.withdrawalBankAccounts,
  );
  static const _getAccountLabel = ApiCallLabel(
    feature: 'linked_banks',
    action: 'view_linked_bank',
    stage: 'load',
    endpoint: _template,
  );
  static const _resolveAccountLabel = ApiCallLabel(
    feature: 'linked_banks',
    action: 'add_linked_bank',
    stage: 'resolve_account',
    endpoint: ApiEndpoints.resolveWithdrawalBankAccount,
  );
  static const _addAccountLabel = ApiCallLabel(
    feature: 'linked_banks',
    action: 'add_linked_bank',
    stage: 'submit',
    endpoint: ApiEndpoints.withdrawalBankAccounts,
  );
  static const _deleteAccountLabel = ApiCallLabel(
    feature: 'linked_banks',
    action: 'remove_linked_bank',
    stage: 'submit',
    endpoint: _template,
  );

  Future<NotifierState<BankCatalogueData>> getBanks() async =>
      NotifierState.fromResponse(
        await _api.getData<BankCatalogueData>(
          ApiEndpoints.banks,
          parser: BankCatalogueData.fromJson,
          requestExtra: {apiCallLabelKey: _getBanksLabel},
        ),
      );

  Future<NotifierState<WithdrawalBankAccountListData>> listAccounts() async =>
      NotifierState.fromResponse(
        await _api.getData<WithdrawalBankAccountListData>(
          ApiEndpoints.withdrawalBankAccounts,
          parser: WithdrawalBankAccountListData.fromJson,
          requestExtra: {apiCallLabelKey: _listAccountsLabel},
        ),
      );

  Future<NotifierState<WithdrawalBankAccount>> getAccount(
    String bankAccountId,
  ) async => NotifierState.fromResponse(
    await _api.getData<WithdrawalBankAccount>(
      ApiEndpoints.withdrawalBankAccount(bankAccountId),
      parser: WithdrawalBankAccount.fromJson,
      requestExtra: {apiCallLabelKey: _getAccountLabel},
    ),
  );

  /// Checks the account name against the profile before anything is saved.
  Future<NotifierState<ResolveWithdrawalBankAccountData>> resolveAccount(
    ResolveWithdrawalBankAccountRequest request,
  ) async => NotifierState.fromResponse(
    await _api.postData<ResolveWithdrawalBankAccountData>(
      ApiEndpoints.resolveWithdrawalBankAccount,
      data: request.toJson(),
      parser: ResolveWithdrawalBankAccountData.fromJson,
      requestExtra: {apiCallLabelKey: _resolveAccountLabel},
    ),
  );

  Future<NotifierState<AddWithdrawalBankAccountData>> addAccount(
    AddWithdrawalBankAccountRequest request,
  ) async => NotifierState.fromResponse(
    await _api.postData<AddWithdrawalBankAccountData>(
      ApiEndpoints.withdrawalBankAccounts,
      data: request.toJson(),
      parser: AddWithdrawalBankAccountData.fromJson,
      requestExtra: {apiCallLabelKey: _addAccountLabel},
    ),
  );

  Future<NotifierState<DeleteWithdrawalBankAccountData>> deleteAccount(
    String bankAccountId,
  ) async => NotifierState.fromResponse(
    await _api.deleteData<DeleteWithdrawalBankAccountData>(
      ApiEndpoints.withdrawalBankAccount(bankAccountId),
      parser: DeleteWithdrawalBankAccountData.fromJson,
      requestExtra: {apiCallLabelKey: _deleteAccountLabel},
    ),
  );
}
