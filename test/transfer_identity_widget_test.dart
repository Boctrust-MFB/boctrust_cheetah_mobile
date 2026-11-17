import 'package:boctrust_savings_loan/module/core_banking/model/intrabank_models.dart';
import 'package:boctrust_savings_loan/module/core_banking/model/transaction_reconfirmation.dart';
import 'package:boctrust_savings_loan/module/core_banking/provider/core_transfer_attempt_provider.dart';
import 'package:boctrust_savings_loan/module/core_banking/screens/transfer_identity_panel.dart';
import 'package:boctrust_savings_loan/module/kyc/screens/dojah_capture_screen.dart';
import 'package:boctrust_savings_loan/module/kyc/service/dojah_config.dart';
import 'package:boctrust_savings_loan/module/kyc/service/dojah_platform_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdentityAttempt extends CoreTransferAttemptNotifier {
  @override
  CoreTransferAttemptState build() => const CoreTransferAttemptState();

  @override
  Future<TransactionReconfirmation?> startIdentity(
    int id, {
    required DateTime consentedAt,
  }) async => TransactionReconfirmation(
    verificationId: 'verification-1',
    status: ReconfirmationStatus.pending,
    provider: ReconfirmationProvider.dojah,
    withdrawalReference: 'transfer-1',
    expiresAt: DateTime.utc(2030),
    dojahReference: 'dojah-reference-1',
    bvn: '00000000006',
  );
}

void main() {
  testWidgets('transfer liveness opens its dedicated widget', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreTransferAttemptProvider.overrideWith(_IdentityAttempt.new),
          dojahConfigProvider.overrideWithValue(
            const DojahConfig(
              selfieWidgetId: 'bvn-selfie-widget',
              governmentWidgetId: 'government-widget',
              transferWidgetId: 'large-withdrawal-widget',
            ),
          ),
          dojahPlatformRouteProvider.overrideWithValue(
            DojahPlatformRoute.unsupported,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TransferIdentityPanel(
              attempt: const CoreTransferAttempt(
                id: 1,
                draft: BoctrustTransferDraft(
                  toAccountNumber: '1100037777',
                  amountKobo: '1000',
                ),
                phase: CoreTransferPhase.awaitingIdentity,
              ),
              onExit: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final capture = tester.widget<DojahCaptureScreen>(
      find.byType(DojahCaptureScreen),
    );
    expect(capture.widgetId, 'large-withdrawal-widget');
    expect(capture.bvn, '00000000006');
  });
}
