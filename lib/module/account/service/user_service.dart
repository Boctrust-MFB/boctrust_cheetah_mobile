import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api_endpoints.dart';
import '../../../app/error_reporting.dart';
import '../../../app/network.dart';
import '../../../app/services.dart';
import '../model/profile_image_model.dart';
import '../model/user_profile_model.dart';
import '../model/user_tier_model.dart';

final userServiceProvider = Provider<UserService>(
  (ref) => UserService(ref.watch(apiServiceProvider)),
);

class UserService {
  const UserService(this._api);
  final ApiService _api;

  static const _ownProfileLabel = ApiCallLabel(
    feature: 'account',
    action: 'view_profile',
    stage: 'load',
    endpoint: ApiEndpoints.ownProfile,
  );
  static const _ownTierLabel = ApiCallLabel(
    feature: 'account',
    action: 'view_tier',
    stage: 'load',
    endpoint: ApiEndpoints.ownTier,
  );
  static const _profileImageSignedUrlLabel = ApiCallLabel(
    feature: 'account',
    action: 'update_profile_image',
    stage: 'get_upload_url',
    endpoint: ApiEndpoints.profileImageSignedUrl,
  );

  Future<NotifierState<UserOwnProfileData>> getOwnProfile() async =>
      NotifierState.fromResponse(
        await _api.getData<UserOwnProfileData>(
          ApiEndpoints.ownProfile,
          parser: UserOwnProfileData.fromJson,
          requestExtra: {apiCallLabelKey: _ownProfileLabel},
        ),
      );

  Future<NotifierState<UserTierInfoData>> getOwnTier() async =>
      NotifierState.fromResponse(
        await _api.getData<UserTierInfoData>(
          ApiEndpoints.ownTier,
          parser: UserTierInfoData.fromJson,
          requestExtra: {apiCallLabelKey: _ownTierLabel},
        ),
      );

  Future<NotifierState<ProfileImageSignedUrlData>>
  getProfileImageSignedUrl() async => NotifierState.fromResponse(
    await _api.getData<ProfileImageSignedUrlData>(
      ApiEndpoints.profileImageSignedUrl,
      parser: ProfileImageSignedUrlData.fromJson,
      requestExtra: {apiCallLabelKey: _profileImageSignedUrlLabel},
    ),
  );
}
