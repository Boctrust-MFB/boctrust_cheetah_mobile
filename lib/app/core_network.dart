import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../helper/secure_storage.dart';
import '../module/onboarding/provider/auth_session_provider.dart';
import 'interceptors.dart';
import 'network.dart';
import 'services.dart';
import 'session_expiry_coordinator.dart';

/// The Core Service transport, or null when `CORE_BASE_URL` is blank.
///
/// It has its own interceptor instances and shares only the signed-in bearer
/// token and the local expiry path with the User Service. A Core 401 never
/// expires the User session; it surfaces as a Core-scoped error.
final coreDioProvider = Provider<Dio?>((ref) {
  final base = coreApiBaseUrl(Env.coreBaseUrl);
  if (base == null) return null;
  final storage = ref.watch(secureStorageProvider);
  return buildApiDio(
    base,
    AuthInterceptor(
      readAccessToken: storage.readAccessToken,
      readCurrentSession: () => ref.read(authSessionProvider),
      expireSessionOnce: () =>
          ref.read(sessionExpiryCoordinatorProvider).expireOnce(),
      // Every requested Core mobile operation is authenticated.
      isPublicOperation: (_, _) => false,
      expireSessionOnRemote401: false,
    ),
  );
});

/// The shared envelope parser over [coreDioProvider], or null when Core is
/// not configured.
final coreApiServiceProvider = Provider<ApiService?>((ref) {
  final dio = ref.watch(coreDioProvider);
  return dio == null ? null : ApiService(dio);
});
