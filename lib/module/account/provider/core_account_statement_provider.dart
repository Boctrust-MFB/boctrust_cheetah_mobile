import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/services.dart';
import '../../core_banking/model/core_account_statement.dart';
import '../../core_banking/service/core_account_service.dart';

/// The statement the customer asked for. Idle until [request] is called; a
/// change of account or period never fetches.
final coreAccountStatementProvider =
    NotifierProvider.autoDispose<
      CoreAccountStatementNotifier,
      NotifierState<CoreAccountStatement>
    >(CoreAccountStatementNotifier.new);

class CoreAccountStatementNotifier
    extends Notifier<NotifierState<CoreAccountStatement>> {
  @override
  NotifierState<CoreAccountStatement> build() => const NotifierState.idle();

  Future<void> request(
    String accountNumber,
    DateTime fromDate,
    DateTime toDate,
  ) async {
    if (state.isLoading) return;
    state = const NotifierState.loading();
    final result = await ref
        .read(coreAccountServiceProvider)
        .getAccountStatement(accountNumber, fromDate: fromDate, toDate: toDate);
    if (!ref.mounted) return;
    state = result;
  }
}
