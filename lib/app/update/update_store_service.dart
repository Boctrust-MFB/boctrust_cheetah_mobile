import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_policy.dart';

const MethodChannel _channel = MethodChannel('boctrust/app_update');

final updateStoreServiceProvider = Provider<UpdateStoreService>((ref) {
  return UpdateStoreService();
});

class UpdateStoreService {
  /// Never throws; any failure is [StoreUnknown].
  Future<StoreCheck> check(
    UpdatePolicy policy,
    InstalledRelease installed,
  ) async {
    try {
      switch (policy.platform) {
        case UpdatePlatform.android:
          return await _checkPlay(installed);
        case UpdatePlatform.ios:
          return await _checkAppStore(policy, installed);
      }
    } catch (_) {
      return const StoreUnknown();
    }
  }

  Future<StoreCheck> _checkPlay(InstalledRelease installed) async {
    final reply = await _channel.invokeMapMethod<String, Object?>(
      'availableRelease',
    );
    switch (reply?['status']) {
      case 'available':
        final code = reply?['versionCode'];
        if (code is! int) return const StoreUnknown();
        return StoreAvailable(
          StoreRelease(
            build: code,
            storeUrl: Uri.parse(
              'https://play.google.com/store/apps/details?id=${installed.packageName}',
            ),
          ),
        );
      case 'not_available':
        return const StoreNotAvailable();
      default:
        return const StoreUnknown();
    }
  }

  Future<StoreCheck> _checkAppStore(
    UpdatePolicy policy,
    InstalledRelease installed,
  ) async {
    final id = policy.appStoreId;
    final country = policy.country;
    if (id == null || country == null) return const StoreUnknown();

    // A fresh client: no app interceptors, so no auth headers or app logging.
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.plain,
      ),
    );
    final Response<String> response;
    try {
      response = await dio.get<String>(
        'https://itunes.apple.com/lookup',
        queryParameters: {'id': id, 'country': country},
      );
    } finally {
      dio.close();
    }

    // iTunes serves JSON as text/javascript, so decode it here.
    final body = response.data;
    final decoded = body == null ? null : jsonDecode(body);
    if (decoded is! Map) return const StoreUnknown();

    final count = decoded['resultCount'];
    if (count == 0) return const StoreNotAvailable();
    final results = decoded['results'];
    if (count != 1 || results is! List || results.length != 1) {
      return const StoreUnknown();
    }
    final item = results.first;
    if (item is! Map) return const StoreUnknown();

    if (item['trackId']?.toString() != id) return const StoreUnknown();
    if (item['bundleId'] != installed.packageName) return const StoreUnknown();
    final rawVersion = item['version'];
    final version = rawVersion is String
        ? AppVersion.tryParse(rawVersion)
        : null;
    if (version == null) return const StoreUnknown();
    // A lagging lookup edge can still serve the previous release; that is
    // not proof the target is missing, so it must not clear an active gate.
    if (version < policy.targetVersion) return const StoreUnknown();
    final rawUrl = item['trackViewUrl'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (url == null || url.scheme != 'https' || url.host != 'apps.apple.com') {
      return const StoreUnknown();
    }
    return StoreAvailable(StoreRelease(version: version, storeUrl: url));
  }
}
