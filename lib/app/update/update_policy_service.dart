import 'dart:async';
import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../helper/fcm_service.dart';
import 'update_policy.dart';

const String _policyKey = 'app_update_policy_v1';
const String _defaultPolicyJson =
    '{"android":{"enabled":false},"ios":{"enabled":false}}';

/// Null on web, desktop and debug builds, where update checks never run.
UpdatePlatform? currentUpdatePlatform() {
  if (kIsWeb || kDebugMode) return null;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return UpdatePlatform.android;
    case TargetPlatform.iOS:
      return UpdatePlatform.ios;
    default:
      return null;
  }
}

final updatePolicyServiceProvider = Provider<UpdatePolicyService>((ref) {
  return UpdatePolicyService(firebaseReady: ref.watch(firebaseReadyProvider));
});

class UpdatePolicyService {
  UpdatePolicyService({required this.firebaseReady});

  final bool firebaseReady;

  Future<FirebaseRemoteConfig>? _setup;

  Future<FirebaseRemoteConfig> _config() {
    return _setup ??= () async {
      final config = FirebaseRemoteConfig.instance;
      await config.setDefaults({_policyKey: _defaultPolicyJson});
      await config.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      return config;
    }();
  }

  Future<UpdatePolicy?> loadPolicy(UpdatePlatform platform) async {
    if (!firebaseReady) return null;
    try {
      final config = await _config();
      try {
        await config.fetchAndActivate();
      } catch (_) {
        // Fall back to already-active (cached or default) values.
      }
      final decoded = _decode(config.getString(_policyKey));
      return UpdatePolicy.fromJson(decoded, platform);
    } catch (_) {
      return null;
    }
  }

  /// Emits after a real-time config update has been activated.
  Stream<void> get updates {
    if (!firebaseReady) return const Stream<void>.empty();
    late StreamController<void> controller;
    StreamSubscription<RemoteConfigUpdate>? sub;
    controller = StreamController<void>(
      onListen: () async {
        try {
          final config = await _config();
          if (controller.isClosed) return;
          sub = config.onConfigUpdated.listen((_) async {
            try {
              await config.activate();
              if (!controller.isClosed) controller.add(null);
            } catch (_) {}
          }, onError: (_) {});
        } catch (_) {}
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<InstalledRelease?> installedRelease() async {
    final platform = currentUpdatePlatform();
    if (platform == null) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final version = AppVersion.tryParse(info.version);
      final build = int.tryParse(info.buildNumber);
      if (version == null || build == null) return null;
      return InstalledRelease(
        platform: platform,
        version: version,
        build: build,
        packageName: info.packageName,
      );
    } catch (_) {
      return null;
    }
  }
}

Object? _decode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}
