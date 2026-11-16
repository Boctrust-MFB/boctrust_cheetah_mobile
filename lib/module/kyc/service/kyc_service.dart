import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api_endpoints.dart';
import '../../../app/error_reporting.dart';
import '../../../app/network.dart';
import '../../../app/services.dart';
import '../model/kyc_configuration_models.dart';
import '../model/kyc_models.dart';
import '../model/kyc_status_models.dart';

final kycServiceProvider = Provider<KycService>(
  (ref) => KycService(ref.watch(apiServiceProvider)),
);

class KycService {
  const KycService(this._api);
  final ApiService _api;

  static const _statusLabel = ApiCallLabel(
    feature: 'kyc',
    action: 'view_kyc_status',
    stage: 'load',
    endpoint: ApiEndpoints.ownKycStatus,
  );
  static const _providerConfigLabel = ApiCallLabel(
    feature: 'kyc',
    action: 'verify_government_id',
    stage: 'load_provider_config',
    endpoint: ApiEndpoints.kycProviderConfig,
  );
  static const _documentTypesLabel = ApiCallLabel(
    feature: 'kyc',
    action: 'verify_government_id',
    stage: 'load_document_types',
    endpoint: ApiEndpoints.governmentIdDocumentTypes,
  );
  static const _initiateIdentityLabel = ApiCallLabel(
    feature: 'kyc',
    action: 'verify_identity',
    stage: 'initiate',
    endpoint: ApiEndpoints.initiateIdentityVerification,
  );
  static const _initiateGovernmentIdLabel = ApiCallLabel(
    feature: 'kyc',
    action: 'verify_government_id',
    stage: 'initiate',
    endpoint: ApiEndpoints.initiateGovernmentIdVerification,
  );
  static const _initiateUtilityBillLabel = ApiCallLabel(
    feature: 'kyc',
    action: 'submit_utility_bill',
    stage: 'initiate',
    endpoint: ApiEndpoints.initiateUtilityBillUpload,
  );
  static const _completeUtilityBillLabel = ApiCallLabel(
    feature: 'kyc',
    action: 'submit_utility_bill',
    stage: 'complete',
    endpoint: '/users/me/kyc/utility-bill/{verificationId}/complete',
  );

  /// The authoritative view of this user's verification state.
  ///
  /// Initiation and SDK submission never mean verified; this operation and the
  /// refreshed tier/profile/Home aggregates do.
  Future<NotifierState<KycStatusData>> getStatus() async =>
      NotifierState.fromResponse(
        await _api.getData<KycStatusData>(
          ApiEndpoints.ownKycStatus,
          parser: KycStatusData.fromJson,
          requestExtra: {apiCallLabelKey: _statusLabel},
        ),
      );

  /// The provider configuration used to pre-filter government documents.
  /// An initiation's own provider still decides each attempt.
  Future<NotifierState<KycProviderConfigData>> getProviderConfig() async =>
      NotifierState.fromResponse(
        await _api.getData<KycProviderConfigData>(
          ApiEndpoints.kycProviderConfig,
          parser: KycProviderConfigData.fromJson,
          requestExtra: {apiCallLabelKey: _providerConfigLabel},
        ),
      );

  /// The government documents the server currently accepts, in server order.
  Future<NotifierState<GovernmentIdDocumentCatalogue>>
  getGovernmentIdDocumentTypes() async => NotifierState.fromResponse(
    await _api.getData<GovernmentIdDocumentCatalogue>(
      ApiEndpoints.governmentIdDocumentTypes,
      parser: GovernmentIdDocumentCatalogue.fromJson,
      requestExtra: {apiCallLabelKey: _documentTypesLabel},
    ),
  );

  Future<NotifierState<KycInitiationData>> initiateIdentity(
    IdentityVerificationRequest request,
  ) async => NotifierState.fromResponse(
    await _api.postData<KycInitiationData>(
      ApiEndpoints.initiateIdentityVerification,
      data: request.toJson(),
      parser: KycInitiationData.fromJson,
      requestExtra: {apiCallLabelKey: _initiateIdentityLabel},
    ),
  );

  Future<NotifierState<KycInitiationData>> initiateGovernmentId(
    GovernmentIdVerificationRequest request,
  ) async => NotifierState.fromResponse(
    await _api.postData<KycInitiationData>(
      ApiEndpoints.initiateGovernmentIdVerification,
      data: request.toJson(),
      parser: KycInitiationData.fromJson,
      requestExtra: {apiCallLabelKey: _initiateGovernmentIdLabel},
    ),
  );

  Future<NotifierState<UtilityBillUploadTarget>> initiateUtilityBillUpload(
    UtilityBillInitiationRequest request,
  ) async => NotifierState.fromResponse(
    await _api.postData<UtilityBillUploadTarget>(
      ApiEndpoints.initiateUtilityBillUpload,
      data: request.toJson(),
      parser: UtilityBillUploadTarget.fromJson,
      requestExtra: {apiCallLabelKey: _initiateUtilityBillLabel},
    ),
  );

  /// Confirms the bytes were uploaded, moving the verification to review.
  Future<NotifierState<UtilityBillCompletionData>> completeUtilityBillUpload(
    String verificationId,
  ) async => NotifierState.fromResponse(
    await _api.postData<UtilityBillCompletionData>(
      ApiEndpoints.completeUtilityBillUpload(verificationId),
      parser: UtilityBillCompletionData.fromJson,
      requestExtra: {apiCallLabelKey: _completeUtilityBillLabel},
    ),
  );
}
