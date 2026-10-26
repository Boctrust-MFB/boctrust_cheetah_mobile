import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/services.dart';
import '../../core_banking/model/core_account_statement.dart';
import '../../core_banking/service/core_account_service.dart';

/// Shown when a statement is requested while another is still loading.
const coreStatementBusyMessage =
    'Your statement is still being prepared. Try again in a moment.';

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

  /// Fetches the statement and returns what this call produced. While another
  /// request is loading nothing is sent and a busy error is returned.
  Future<NotifierState<CoreAccountStatement>> request(
    String accountNumber,
    DateTime fromDate,
    DateTime toDate,
  ) async {
    if (state.isLoading) {
      return const NotifierState.error(coreStatementBusyMessage);
    }
    state = const NotifierState.loading();
    final result = await ref
        .read(coreAccountServiceProvider)
        .getAccountStatement(accountNumber, fromDate: fromDate, toDate: toDate);
    if (ref.mounted) state = result;
    return result;
  }
}
