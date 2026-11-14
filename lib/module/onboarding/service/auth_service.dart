import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api_endpoints.dart';
import '../../../app/error_reporting.dart';
import '../../../app/interceptors.dart';
import '../../../app/network.dart';
import '../../../app/services.dart';
import '../model/auth_requests.dart';
import '../model/auth_responses.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(apiServiceProvider)),
);

class AuthService {
  const AuthService(this._api);
  final ApiService _api;

  static const _signupLabel = ApiCallLabel(
    feature: 'auth',
    action: 'create_account',
    stage: 'submit',
    endpoint: ApiEndpoints.signup,
  );
  static const _requestOtpLabel = ApiCallLabel(
    feature: 'auth',
    action: 'create_account',
    stage: 'request_otp',
    endpoint: ApiEndpoints.requestOtp,
  );
  static const _verifyAccountLabel = ApiCallLabel(
    feature: 'auth',
    action: 'create_account',
    stage: 'verify_account',
    endpoint: ApiEndpoints.verifyAccount,
  );
  static const _createFirstPasswordLabel = ApiCallLabel(
    feature: 'auth',
    action: 'create_account',
    stage: 'create_password',
    endpoint: ApiEndpoints.createFirstPassword,
  );
  static const _forgotPasswordLabel = ApiCallLabel(
    feature: 'auth',
    action: 'reset_password',
    stage: 'request_otp',
    endpoint: ApiEndpoints.forgotPassword,
  );
  static const _verifyPasswordOtpLabel = ApiCallLabel(
    feature: 'auth',
    action: 'reset_password',
    stage: 'verify_otp',
    endpoint: ApiEndpoints.verifyPasswordOtp,
  );
  static const _resetPasswordLabel = ApiCallLabel(
    feature: 'auth',
    action: 'reset_password',
    stage: 'submit',
    endpoint: ApiEndpoints.resetPassword,
  );
  static const _changePasswordLabel = ApiCallLabel(
    feature: 'auth',
    action: 'change_password',
    stage: 'submit',
    endpoint: ApiEndpoints.changePassword,
  );
  static const _forgotPinLabel = ApiCallLabel(
    feature: 'auth',
    action: 'reset_pin',
    stage: 'request_otp',
    endpoint: ApiEndpoints.forgotPin,
  );
  static const _verifyPinOtpLabel = ApiCallLabel(
    feature: 'auth',
    action: 'reset_pin',
    stage: 'verify_otp',
    endpoint: ApiEndpoints.verifyPinOtp,
  );
  static const _resetPinLabel = ApiCallLabel(
    feature: 'auth',
    action: 'reset_pin',
    stage: 'submit',
    endpoint: ApiEndpoints.resetPin,
  );
  static const _createFirstPinLabel = ApiCallLabel(
    feature: 'auth',
    action: 'create_pin',
    stage: 'submit',
    endpoint: ApiEndpoints.createFirstPin,
  );
  static const _changePinLabel = ApiCallLabel(
    feature: 'auth',
    action: 'change_pin',
    stage: 'submit',
    endpoint: ApiEndpoints.changePin,
  );
  static const _loginLabel = ApiCallLabel(
    feature: 'auth',
    action: 'sign_in',
    stage: 'submit',
    endpoint: ApiEndpoints.login,
  );
  static const _verifyCurrentPasswordLabel = ApiCallLabel(
    feature: 'auth',
    action: 'change_password',
    stage: 'verify_current',
    endpoint: ApiEndpoints.verifyCurrentPassword,
  );
  static const _verifyCurrentPinLabel = ApiCallLabel(
    feature: 'auth',
    action: 'change_pin',
    stage: 'verify_current',
    endpoint: ApiEndpoints.verifyCurrentPin,
  );
  static const _verifyDeviceLabel = ApiCallLabel(
    feature: 'auth',
    action: 'sign_in',
    stage: 'verify_device',
    endpoint: ApiEndpoints.verifyDevice,
  );
  static const _fcmTokenLabel = ApiCallLabel(
    feature: 'auth',
    action: 'register_notifications',
    stage: 'submit',
    endpoint: ApiEndpoints.fcmToken,
  );
  static const _logoutLabel = ApiCallLabel(
    feature: 'auth',
    action: 'sign_out',
    stage: 'submit',
    endpoint: ApiEndpoints.logout,
  );
  static const _initiateIdentifierVerificationLabel = ApiCallLabel(
    feature: 'auth',
    action: 'verify_identifier',
    stage: 'initiate',
    endpoint: ApiEndpoints.initiateIdentifierVerification,
  );
  static const _verifyIdentifierLabel = ApiCallLabel(
    feature: 'auth',
    action: 'verify_identifier',
    stage: 'verify_otp',
    endpoint: ApiEndpoints.verifyIdentifier,
  );

  Future<NotifierState<SignupData>> signup(SignupRequest request) =>
      _post(ApiEndpoints.signup, _signupLabel, request, SignupData.fromJson);

  Future<NotifierState<RequestOtpData>> requestOtp(RequestOtpRequest request) =>
      _post(
        ApiEndpoints.requestOtp,
        _requestOtpLabel,
        request,
        RequestOtpData.fromJson,
      );

  Future<NotifierState<EmptyData>> verifyAccount(
    VerifyAccountRequest request,
  ) => _post(
    ApiEndpoints.verifyAccount,
    _verifyAccountLabel,
    request,
    EmptyData.fromJson,
  );

  Future<NotifierState<CreateFirstPasswordData>> createFirstPassword(
    CreateFirstPasswordRequest request,
  ) => _post(
    ApiEndpoints.createFirstPassword,
    _createFirstPasswordLabel,
    request,
    CreateFirstPasswordData.fromJson,
  );

  Future<NotifierState<OtpData>> forgotPassword(ForgotRequest request) => _post(
    ApiEndpoints.forgotPassword,
    _forgotPasswordLabel,
    request,
    OtpData.fromJson,
  );

  Future<NotifierState<ResetTokenData>> verifyPasswordOtp(
    VerifyOtpRequest request,
  ) => _post(
    ApiEndpoints.verifyPasswordOtp,
    _verifyPasswordOtpLabel,
    request,
    ResetTokenData.fromJson,
  );

  Future<NotifierState<EmptyData>> resetPassword(
    ResetPasswordRequest request,
  ) => _post(
    ApiEndpoints.resetPassword,
    _resetPasswordLabel,
    request,
    EmptyData.fromJson,
  );

  Future<NotifierState<EmptyData>> changePassword(
    ChangePasswordRequest request,
  ) => _post(
    ApiEndpoints.changePassword,
    _changePasswordLabel,
    request,
    EmptyData.fromJson,
  );

  Future<NotifierState<OtpData>> forgotPin(ForgotRequest request) =>
      _post(ApiEndpoints.forgotPin, _forgotPinLabel, request, OtpData.fromJson);

  Future<NotifierState<ResetTokenData>> verifyPinOtp(
    VerifyOtpRequest request,
  ) => _post(
    ApiEndpoints.verifyPinOtp,
    _verifyPinOtpLabel,
    request,
    ResetTokenData.fromJson,
  );

  Future<NotifierState<EmptyData>> resetPin(ResetPinRequest request) =>
      _post(ApiEndpoints.resetPin, _resetPinLabel, request, EmptyData.fromJson);

  Future<NotifierState<CreateFirstPinData>> createFirstPin(
    CreateFirstPinRequest request,
  ) => _post(
    ApiEndpoints.createFirstPin,
    _createFirstPinLabel,
    request,
    CreateFirstPinData.fromJson,
  );

  Future<NotifierState<EmptyData>> changePin(ChangePinRequest request) => _post(
    ApiEndpoints.changePin,
    _changePinLabel,
    request,
    EmptyData.fromJson,
  );

  Future<NotifierState<LoginData>> login(LoginRequest request) =>
      _post(ApiEndpoints.login, _loginLabel, request, LoginData.fromJson);

  Future<NotifierState<EmptyData>> verifyCurrentPassword(
    VerifyCurrentPasswordRequest request,
  ) => _post(
    ApiEndpoints.verifyCurrentPassword,
    _verifyCurrentPasswordLabel,
    request,
    EmptyData.fromJson,
  );

  Future<NotifierState<EmptyData>> verifyCurrentPin(
    VerifyCurrentPinRequest request,
  ) => _post(
    ApiEndpoints.verifyCurrentPin,
    _verifyCurrentPinLabel,
    request,
    EmptyData.fromJson,
  );

  Future<NotifierState<EmptyData>> verifyNewDevice(
    VerifyNewDeviceRequest request,
  ) => _post(
    ApiEndpoints.verifyDevice,
    _verifyDeviceLabel,
    request,
    EmptyData.fromJson,
  );

  Future<NotifierState<EmptyData>> updateFcmToken(
    UpdateFcmTokenRequest request,
  ) async => NotifierState.fromResponse(
    await _api.patchData<EmptyData>(
      ApiEndpoints.fcmToken,
      data: request.toJson(),
      parser: EmptyData.fromJson,
      requestExtra: {apiCallLabelKey: _fcmTokenLabel},
    ),
  );

  /// Revokes [accessToken] server-side. The token is passed in because the
  /// local session is already cleared by the time this request is sent.
  Future<NotifierState<EmptyData>> logout({
    required String accessToken,
  }) async => NotifierState.fromResponse(
    await _api.postData<EmptyData>(
      ApiEndpoints.logout,
      parser: EmptyData.fromJson,
      requestExtra: {
        'suppressSessionExpiry': true,
        AuthInterceptor.pinnedAccessTokenKey: accessToken,
        apiCallLabelKey: _logoutLabel,
      },
    ),
  );

  Future<NotifierState<IdentifierVerificationInitiateData>>
  initiateIdentifierVerification(
    InitiateIdentifierVerificationRequest request,
  ) => _post(
    ApiEndpoints.initiateIdentifierVerification,
    _initiateIdentifierVerificationLabel,
    request,
    IdentifierVerificationInitiateData.fromJson,
  );

  Future<NotifierState<IdentifierVerificationVerifyData>> verifyIdentifier(
    VerifyOtpRequest request,
  ) => _post(
    ApiEndpoints.verifyIdentifier,
    _verifyIdentifierLabel,
    request,
    IdentifierVerificationVerifyData.fromJson,
  );

  Future<NotifierState<T>> _post<T>(
    String endpoint,
    ApiCallLabel label,
    JsonRequest request,
    T Function(Object?) parser,
  ) async => NotifierState.fromResponse(
    await _api.postData<T>(
      endpoint,
      data: request.toJson(),
      parser: parser,
      requestExtra: {apiCallLabelKey: label},
    ),
  );
}
