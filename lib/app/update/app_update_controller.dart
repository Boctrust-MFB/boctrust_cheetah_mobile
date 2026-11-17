import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../helper/local_notification_service.dart';
import '../../helper/notification_once.dart';
import 'update_policy.dart';
import 'update_policy_service.dart';
import 'update_store_service.dart';

class AppUpdateState {
  const AppUpdateState({
    this.decision = const UpdateDecision.none(),
    this.checking = false,
    this.lastCheckInconclusive = false,
  });

  final UpdateDecision decision;
  final bool checking;

  /// The last finished check could not reach a verdict, so [decision] was
  /// kept from the check before it.
  final bool lastCheckInconclusive;

  AppUpdateState copyWith({
    UpdateDecision? decision,
    bool? checking,
    bool? lastCheckInconclusive,
  }) {
    return AppUpdateState(
      decision: decision ?? this.decision,
      checking: checking ?? this.checking,
      lastCheckInconclusive:
          lastCheckInconclusive ?? this.lastCheckInconclusive,
    );
  }
}

final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
      AppUpdateController.new,
    );

class AppUpdateController extends Notifier<AppUpdateState> {
  static const String notificationAction = 'app_update.open_store';

  Future<void>? _inFlight;
  bool _rerun = false;

  @override
  AppUpdateState build() => const AppUpdateState();

  /// Coalesces calls: one run at a time, and calls made during a run cause
  /// exactly one more run after it. Never throws.
  Future<void> checkForUpdate() {
    final platform = currentUpdatePlatform();
    if (platform == null) return Future<void>.value();
    if (_inFlight != null) _rerun = true;
    return _inFlight ??= _runLoop(platform).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _runLoop(UpdatePlatform platform) async {
    do {
      _rerun = false;
      await _run(platform);
    } while (_rerun && ref.mounted);
  }

  Future<void> _run(UpdatePlatform platform) async {
    state = state.copyWith(checking: true);
    UpdateDecision? decision;
    int? targetBuild;
    try {
      final policyService = ref.read(updatePolicyServiceProvider);
      final policy = await policyService.loadPolicy(platform);
      final installed = policy == null
          ? null
          : await policyService.installedRelease();
      if (policy == null) {
        // Disabled, invalid or no Firebase: conclusive, clears any gate.
        decision = const UpdateDecision.none();
      } else if (installed != null) {
        final store = await ref
            .read(updateStoreServiceProvider)
            .check(policy, installed);
        if (store is! StoreUnknown) {
          decision = evaluateUpdate(
            policy: policy,
            installed: installed,
            store: store,
          );
        } else if (state.decision.kind == UpdateKind.required &&
            !wouldRequire(policy, installed)) {
          // Inconclusive store, but the policy alone no longer requires an
          // update (already up to date, or no longer forced): drop the gate.
          decision = const UpdateDecision.none();
        }
        targetBuild = policy.targetBuild;
      }
    } catch (_) {
      decision = null;
    }
    if (!ref.mounted) return;

    state = AppUpdateState(
      decision: decision ?? state.decision,
      lastCheckInconclusive: decision == null,
    );

    if (decision != null && decision.kind == UpdateKind.optional) {
      await _notifyOptional(platform, decision, targetBuild);
    }
  }

  Future<void> _notifyOptional(
    UpdatePlatform platform,
    UpdateDecision decision,
    int? targetBuild,
  ) async {
    final service = ref.read(localNotificationServiceProvider);
    if (service == null) return;
    try {
      await postOnce(
        service,
        ref.read(notificationOnceLedgerProvider),
        onceKey: platform == UpdatePlatform.android
            ? 'app_update:android:${decision.target}+$targetBuild'
            : 'app_update:ios:${decision.target}',
        key: 'app_update',
        title: 'Update available',
        body: 'A new version of Cheetah is ready to install.',
        action: notificationAction,
      );
    } catch (_) {
      // A missed notification is not worth failing the check over.
    }
  }

  /// Opens the store listing; checks first when no URL is known yet, as on
  /// a cold-start notification tap. Joins a check already in flight rather
  /// than queueing another.
  Future<void> openStore() async {
    if (state.decision.storeUrl == null) {
      final inFlight = _inFlight;
      if (inFlight != null) {
        await inFlight;
      } else {
        await checkForUpdate();
      }
    }
    if (!ref.mounted) return;
    final url = state.decision.storeUrl;
    if (url == null || !_isStoreUrl(url)) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No app can open the link; nothing more to do.
    }
  }

  static bool _isStoreUrl(Uri url) =>
      url.scheme == 'https' &&
      (url.host == 'play.google.com' || url.host == 'apps.apple.com');
}
