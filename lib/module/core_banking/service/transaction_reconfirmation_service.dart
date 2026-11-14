import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api_endpoints.dart';
import '../../../app/error_reporting.dart';
import '../../../app/interceptors.dart';
import '../../../app/network.dart';
import '../../../app/services.dart';
import '../model/transaction_reconfirmation.dart';

final transactionReconfirmationServiceProvider =
    Provider<TransactionReconfirmationService>(
      (ref) => TransactionReconfirmationService(ref.watch(apiServiceProvider)),
    );

class TransactionReconfirmationService {
  const TransactionReconfirmationService(this._api);
  final ApiService _api;

  static const _initiateLabel = ApiCallLabel(
    feature: 'kyc',
    action: 'reconfirm_identity',
    stage: 'initiate',
    endpoint: ApiEndpoints.initiateIdentityReconfirmation,
  );
  static const _statusLabel = ApiCallLabel(
    feature: 'kyc',
    action: 'reconfirm_identity',
    stage: 'check_status',
    endpoint: ApiEndpoints.identityReconfirmationTemplate,
  );

  /// Starts a selfie reconfirmation bound to one transfer [reference].
  ///
  /// The path carries no identifier, but the reply holds the capture nonce, so
  /// it is kept out of logs.
  Future<NotifierState<TransactionReconfirmation>> initiate(
    String reference, {
    required DateTime consentedAt,
  }) async => NotifierState.fromResponse(
    await _api.postData<TransactionReconfirmation>(
      ApiEndpoints.initiateIdentityReconfirmation,
      data: {
        'withdrawalReference': reference,
        'consent': {
          'granted': true,
          'grantedAt': consentedAt.toUtc().toIso8601String(),
          'noticeLanguage': 'EN',
          'privacyPolicyUrl': sitePageUri('privacy').toString(),
        },
      },
      parser: TransactionReconfirmation.fromJson,
      requestExtra: {
        LoggingInterceptor.privacySensitivePathKey:
            ApiEndpoints.initiateIdentityReconfirmation,
        apiCallLabelKey: _initiateLabel,
      },
    ),
  );

  /// The server's current verdict; the only thing that proves a transfer.
  Future<NotifierState<TransactionReconfirmation>> status(
    String verificationId,
  ) async => NotifierState.fromResponse(
    await _api.getData<TransactionReconfirmation>(
      ApiEndpoints.identityReconfirmation(verificationId),
      parser: TransactionReconfirmation.fromJson,
      requestExtra: {
        LoggingInterceptor.privacySensitivePathKey:
            ApiEndpoints.identityReconfirmationTemplate,
        apiCallLabelKey: _statusLabel,
      },
    ),
  );
}
