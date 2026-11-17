# Store-gated App Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a dismissible local notification for optional releases and a persistent update gate for required releases, only after the relevant store confirms the target is available.

**Architecture:** Task 1 builds a feature-agnostic local-notification flow (tap actions, a once-per-key ledger, permission-aware posting) that any feature can use; app updates are its first client. Tasks 2–3 add a pure policy evaluator fed by Remote Config, the installed version, and per-platform store evidence. Task 4 adds a root-level controller that checks on launch, foreground return and Remote Config updates, posts the optional notification through Task 1, and renders the required gate above navigation.

**Tech Stack:** Flutter/Dart, Riverpod, `firebase_remote_config`, `package_info_plus`, SharedPreferences, `flutter_local_notifications`, `url_launcher`, `dio`, Play In-App Updates (`com.google.android.play:app-update`), Apple iTunes Lookup API.

**Spec:** `docs/superpowers/specs/2026-11-17-store-gated-app-updates-design.md`

## Global Constraints

- Android and iOS only. Web, desktop, `kDebugMode` builds, and Android installs not from Play (`com.android.vending`) never prompt.
- Firebase policy is platform-specific and defaults to disabled. When `firebaseReadyProvider` is false, Remote Config is never touched.
- A store-confirmed target release is required for both optional and required prompts.
- Store or Firebase uncertainty never *creates* a gate and never blocks startup.
- The required gate covers authenticated and unauthenticated routes.
- The local-notification flow (Task 1) must not import anything from the app-update feature except through the single action registry entry.
- Do not ask for notification permission for this feature.
- Do not add `firebase_analytics`.
- **Tests: none.** Per project rule, no new test files, fakes, or matrices. Existing tests must keep passing. Verification is `flutter analyze`, the existing suite, builds, and the device checks in each task.

## File Map

| File | Responsibility |
| --- | --- |
| `lib/helper/notification_payload.dart` | Local payload codec gains a bounded optional `action` field. |
| `lib/helper/local_notification_service.dart` | `showAppNotification` gains a stable `key` and optional `action`; returns true only when notifications are enabled and the plugin accepted the post. |
| `lib/helper/notification_once.dart` (new) | `NotificationOnceLedger`: SharedPreferences record of keys already posted. |
| `lib/helper/notification_actions.dart` (new) | Action registry: name → handler, with `requiresSession`. |
| `lib/app/auth_flow_listener.dart` | Dispatches action payloads through the registry before route/inbox handling. |
| `pubspec.yaml` | Add `firebase_remote_config`, `package_info_plus`. |
| `lib/app/update/update_policy.dart` (new) | Policy parsing, version comparison, `evaluateUpdate`. |
| `lib/app/update/update_policy_service.dart` (new) | Remote Config defaults, fetch/activate, real-time updates, installed release. |
| `lib/app/update/update_store_service.dart` (new) | Store check: Android channel, iOS lookup, verified store URL. |
| `android/app/build.gradle.kts`, `.../MainActivity.kt` | Play app-update dependency and `boctrust/app_update` channel. |
| `lib/app/update/app_update_controller.dart` (new) | Coalesced checks, gate state, optional notification, `openStore()`. |
| `lib/app/update/update_gate.dart` (new), `lib/app.dart` | `AppUpdateScope` (lifecycle + back blocking, above `MaterialApp`) and `UpdateGate` (visual, in `builder`). |
| `docs/app-update-release-runbook.md` (new) | Firebase schema, publish order, rollback, real-store validation. |

## Remote Config contract

One JSON string parameter, `app_update_policy_v1`. In-app default: `{"android":{"enabled":false},"ios":{"enabled":false}}`.

```json
{
  "android": { "enabled": true, "targetBuild": 120, "minSupportedBuild": 110 },
  "ios": { "enabled": true, "targetVersion": "1.2.0", "minSupportedVersion": "1.1.0", "appStoreId": "1234567890", "country": "ng" }
}
```

- `minSupported*` is the first installed release allowed to keep using the app. Installed below it means **required**. Installed from it up to (but excluding) the target means **optional**.
- The platform object is valid only when all of these hold:
  - Android codes are positive ints.
  - iOS versions are 1–4 dot-separated non-negative ints.
  - `minimum <= target`.
  - `appStoreId` is all digits.
  - `country` is two lowercase letters.
- Anything else, including a missing platform object, means disabled.
- No remote-supplied URLs. The Android URL is built from the installed package name. The iOS URL is the matching lookup result's `trackViewUrl`, accepted only for `https` on host `apps.apple.com`.
- Releases must bump `pubspec.yaml` `version` (currently `1.0.0+1`). iOS compares the marketing version, so every App Store release needs a new `x.y.z`.

## Review Focus

1. **Remote target ahead of a staged Play rollout for this device:** Play reports `UPDATE_NOT_AVAILABLE` or a lower code. No notification and no gate.
2. **iOS lookup returns another app, an empty `results`, a malformed version, or a version below target:** no prompt. Verify against a live lookup with a wrong `appStoreId` before enabling iOS.
3. **Notification permission denied:** no post, nothing recorded in the ledger, and a retry on the next check. The required gate is unaffected.
4. **Required gate is showing and the user goes offline, then taps Retry:** an inconclusive store result keeps the gate. Only a conclusive result clears it: the installed version at or above the target, an activated policy that no longer requires an update, or a store that answers "not available".
5. **Android back press while the gate shows:** nothing happens. No route pops underneath and the app does not exit.

---

### Task 1: Independent local-notification flow

**Files:**
- Modify: `lib/helper/notification_payload.dart` (`toLocalPayload`, `decodeLocalPayload`)
- Modify: `lib/helper/local_notification_service.dart` (`showAppNotification`, `_details`)
- Create: `lib/helper/notification_once.dart`, `lib/helper/notification_actions.dart`
- Modify: `lib/app/auth_flow_listener.dart:140-156` (`_dispatchNotification`, `_markAuthenticatedDestinationReady`)

**Interfaces:**
- Produces (any feature may use these):
  - `NotificationPayload` local payloads carry an optional `action` field. It obeys the same `_field` bounds as `route`/`id`: a trimmed non-empty string of at most 128 chars, with the whole payload at most 512 chars. `decodeLocalPayload` returns `{'route': ?, 'id': ?, 'action': ?}`.
  - `LocalNotificationService.showAppNotification({required String title, required String body, String? key, String? action, String? argument}) → Future<bool>`. With `key`, the notification id is `NotificationPayload.stableId(key)`, so a later post with the same key replaces the earlier one. Without `key`, the id stays time-based as it is today, so the existing "Statement saved" call is unchanged. `action`/`argument` are encoded as payload `action`/`id`. Returns true only when `notificationsEnabled()` is true and `_plugin.show` completed.
  - `LocalNotificationService.notificationsEnabled() → Future<bool>`:
    - Android: `AndroidFlutterLocalNotificationsPlugin.areNotificationsEnabled()`.
    - iOS: `IOSFlutterLocalNotificationsPlugin.checkPermissions()` → `isEnabled`.
    - Null or throwing: false.
    - It never requests permission.
  - `NotificationOnceLedger(SharedPreferences)` with `bool hasPosted(String key)` and `Future<void> markPosted(String key)`. Prefs key: `notification_once.$key`. `notificationOnceLedgerProvider` reads `sharedPreferencesProvider`.
  - `typedef NotificationActionRun = Future<void> Function(String? argument);`
  - `class NotificationActionHandler { const NotificationActionHandler({required this.run, this.requiresSession = true}); }`
  - `notificationActionHandlersProvider = Provider<Map<String, NotificationActionHandler>>`. This is the single registration point, like the route table. Task 4 adds the app-update entry.
  - Convenience for feature callers: `Future<bool> postOnce(LocalNotificationService, NotificationOnceLedger, {required String onceKey, ...showAppNotification args})`. It skips when `hasPosted(onceKey)`, otherwise posts and calls `markPosted` only on true.

- [ ] **Step 1:** Add the `action` field to the codec.
  - `toLocalPayload` returns null only when route, id and action are all null.
  - Remote FCM payloads ignore `action`: `fromRemoteMessage` does not read it. This keeps a pushed message from triggering local action handlers.
- [ ] **Step 2:** Implement `notificationsEnabled()` and the extended `showAppNotification` in `local_notification_service.dart`. Then create `notification_once.dart` with the ledger, its provider and `postOnce`.
- [ ] **Step 3:** Create `notification_actions.dart` with the typedef, handler class and an initially empty provider map. Change `_dispatchNotification` in `auth_flow_listener.dart` to look up `payload['action']` in the registry before anything else:
  - **Handler found, `requiresSession == false`:** run it immediately, unawaited, with `payload['id']` as the argument, and catch errors.
  - **Handler found, `requiresSession == true`:** use the existing pending-until-authenticated path. `_markAuthenticatedDestinationReady` re-enters the same dispatch, so the action runs instead of the navigator.
  - **Unknown action:** log via `apiLogger.w` and drop the payload. It must not fall back to the inbox.
  - **No action:** current behavior, unchanged.
- [ ] **Step 4:** Run `flutter analyze` and `flutter test test/notification_payload_test.dart test/local_notification_service_test.dart test/notification_tap_flow_test.dart`. Expected: no issues, all pass.
- [ ] **Step 5:** Commit `feat(notifications): add keyed, action-routed local notifications`.

### Task 2: Policy, Remote Config and installed release

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/app/update/update_policy.dart`, `lib/app/update/update_policy_service.dart`

**Interfaces:**
- Produces (`update_policy.dart`):
  - `enum UpdatePlatform { android, ios }`.
  - `UpdatePolicy.fromJson(Object? json, UpdatePlatform platform) → UpdatePolicy?`. Returns null for disabled or invalid input. Fields:
    - `target`, `minimum`: a `ReleaseId`.
    - `appStoreId`, `country`: iOS only.
  - `sealed class ReleaseId implements Comparable<ReleaseId>` with two variants:
    - `BuildCode(int)` for Android.
    - `MarketingVersion(List<int>)` for iOS. It parses dotted ints, compares component-wise with missing components treated as 0, and never compares strings. So `1.10.0 > 1.9.0` and `1.2 == 1.2.0`.
    - `toString()` gives the canonical form used in ledger keys.
  - `class InstalledRelease { UpdatePlatform platform; ReleaseId release; String packageName; }`
  - `class StoreRelease { ReleaseId release; Uri storeUrl; }`
  - `sealed class StoreCheck` with three variants: `StoreAvailable(StoreRelease)`, `StoreNotAvailable()` (conclusive), and `StoreUnknown()` (error, timeout, unsupported install).
  - `enum UpdateKind { none, optional, required }` and `class UpdateDecision { UpdateKind kind; ReleaseId? target; Uri? storeUrl; }`.
  - `UpdateDecision evaluateUpdate({required UpdatePolicy policy, required InstalledRelease installed, required StoreCheck store})` returns the first match:
    1. `installed >= policy.target` → none.
    2. `store` is not `StoreAvailable` → none.
    3. `store.release < policy.target` → none.
    4. `installed < policy.minimum` → required.
    5. Otherwise → optional.
    - `target` and `storeUrl` are set only for optional/required.
- Produces (`update_policy_service.dart`):
  - `updatePolicyServiceProvider` → `UpdatePolicyService` with:
    - `Future<UpdatePolicy?> loadPolicy(UpdatePlatform)`.
    - `Stream<void> get updates`.
    - `Future<InstalledRelease?> installedRelease()`.
  - `currentUpdatePlatform() → UpdatePlatform?`. Returns null on web, desktop and `kDebugMode`.

- [ ] **Step 1:** Add `firebase_remote_config` and `package_info_plus` to `pubspec.yaml`, using versions compatible with `firebase_core ^4.13.0`. Run `flutter pub get`. Expected: resolves.
- [ ] **Step 2:** Implement `update_policy.dart` as specified.
- [ ] **Step 3:** Implement `UpdatePolicyService`.
  - **Firebase not ready:** when `firebaseReadyProvider` is false, `loadPolicy` returns null and `updates` is empty.
  - **Setup, once:**
    - `setDefaults({'app_update_policy_v1': <default JSON>})`.
    - `setConfigSettings(RemoteConfigSettings(fetchTimeout: Duration(seconds: 10), minimumFetchInterval: Duration(hours: 1)))`.
  - **`loadPolicy`:** calls `fetchAndActivate()`. On any exception it falls back to the already-active values (cached or default), then decodes the parameter and calls `UpdatePolicy.fromJson`.
  - **`updates`:** listens to `onConfigUpdated`, calls `activate()`, then emits. This is how rollback reaches open apps without waiting out the fetch interval.
  - **`installedRelease`:** reads `PackageInfo.fromPlatform()`.
    - Android: `BuildCode(int.parse(buildNumber))`.
    - iOS: `MarketingVersion` of `version`.
    - Parse failure: null.
- [ ] **Step 4:** Run `flutter analyze`. Expected: no issues.
- [ ] **Step 5:** Commit `feat(update): add update policy and remote config source`.

### Task 3: Store verification

**Files:**
- Create: `lib/app/update/update_store_service.dart`
- Modify: `android/app/build.gradle.kts` (dependencies)
- Modify: `android/app/src/main/kotlin/com/boctrust/boctrust_savings_loan/MainActivity.kt` (second channel next to `boctrust/scan_text`)

**Interfaces:**
- Consumes: `UpdatePolicy`, `InstalledRelease`, `StoreCheck`, `StoreRelease`, `BuildCode`, `MarketingVersion` (Task 2).
- Produces: `updateStoreServiceProvider` → `UpdateStoreService` with `Future<StoreCheck> check(UpdatePolicy, InstalledRelease)`, which never throws.
- Android channel `boctrust/app_update`, method `availableRelease`, replies with a map:
  - `{"status": "available", "versionCode": <int>}`
  - `{"status": "not_available"}`
  - `{"status": "unsupported"}`
  - `{"status": "error"}`

- [ ] **Step 1:** Add `implementation("com.google.android.play:app-update:2.1.0")` to `build.gradle.kts`.
- [ ] **Step 2:** Add the channel handler to `MainActivity.kt`.
  - **Installer check:** read the installer with `packageManager.getInstallSourceInfo(packageName).installingPackageName` on API 30+, or `getInstallerPackageName` below that. Anything other than `com.android.vending` replies `unsupported`.
  - **Update query:** call `AppUpdateManagerFactory.create(applicationContext).appUpdateInfo`.
    - `updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE` → `available` with `availableVersionCode()`.
    - `UPDATE_NOT_AVAILABLE` → `not_available`.
    - Any other availability, or failure → `error`, with only the exception class name.
  - Never start an update flow.
- [ ] **Step 3:** Implement `check` for Android.
  - `available` → `StoreAvailable(StoreRelease(BuildCode(code), Uri.parse('https://play.google.com/store/apps/details?id=${installed.packageName}')))`.
  - `not_available` → `StoreNotAvailable`.
  - Everything else, including `PlatformException` → `StoreUnknown`.
- [ ] **Step 4:** Implement `check` for iOS. Use a dedicated `Dio` with no app interceptors and 5 s connect/receive timeouts. GET `https://itunes.apple.com/lookup` with `id=<appStoreId>` and `country=<country>`.
  - `StoreAvailable` requires all of the following:
    - `resultCount == 1`.
    - `trackId` equals `appStoreId`.
    - `bundleId` equals `installed.packageName`.
    - `version` parses as a `MarketingVersion`.
    - `trackViewUrl` is https on `apps.apple.com`.
  - `resultCount == 0` → `StoreNotAvailable`.
  - Any other mismatch or error → `StoreUnknown`.
- [ ] **Step 5:** Run `flutter analyze` and `flutter build apk --debug`. Expected: both succeed.
- [ ] **Step 6:** Commit `feat(update): verify release availability in Play and App Store`.

### Task 4: Update controller, gate and runbook

**Files:**
- Create: `lib/app/update/app_update_controller.dart`, `lib/app/update/update_gate.dart`, `docs/app-update-release-runbook.md`
- Modify: `lib/helper/notification_actions.dart` (register the action), `lib/app.dart` (`CheetahApp.build`, `MaterialApp.builder`)

**Interfaces:**
- Consumes:
  - Task 1: `postOnce`, `notificationOnceLedgerProvider`, `localNotificationServiceProvider`, `notificationActionHandlersProvider`.
  - Task 2: `UpdatePolicyService`, `evaluateUpdate`, `currentUpdatePlatform`.
  - Task 3: `UpdateStoreService`.
- Produces:
  - `appUpdateControllerProvider = NotifierProvider<AppUpdateController, AppUpdateState>`.
  - `AppUpdateState { UpdateDecision decision; bool checking; bool lastCheckInconclusive; }`.
  - `AppUpdateController.checkForUpdate() → Future<void>` and `openStore() → Future<void>`.
  - Action name: `AppUpdateController.notificationAction = 'app_update.open_store'`.

- [ ] **Step 1:** Implement `AppUpdateController`.
  - **Platform guard:** `checkForUpdate` returns immediately when `currentUpdatePlatform()` is null.
  - **Coalescing:** keep one in-flight future (`_inFlight ??= _run().whenComplete(() => _inFlight = null)`). A call made during a run sets a `_rerun` flag, which triggers exactly one more run.
  - **Each `_run`:** load the policy, read the installed release, then check the store (only when the policy is non-null), and evaluate.
    - **Inconclusive check** (`StoreUnknown`, or the installed release could not be read): keep the current decision and set `lastCheckInconclusive`.
    - **Conclusive check:** replace the decision. This also covers a null policy, which is conclusive and clears a gate after rollback.
  - **Optional decision:** call `postOnce` with these values:
    - `onceKey: 'app_update:${platform.name}:${target}'`
    - `key: 'app_update'`
    - `title: 'Update available'`
    - `body: 'A new version of Cheetah is ready to install.'`
    - `action: notificationAction`
  - **`openStore()`:**
    1. If the decision has no `storeUrl`, await `checkForUpdate()` first. This covers a cold-start tap.
    2. Launch `storeUrl` with `launchUrl(uri, mode: LaunchMode.externalApplication)` only if it is still `https` on `play.google.com` or `apps.apple.com`.
- [ ] **Step 2:** Register `AppUpdateController.notificationAction: NotificationActionHandler(requiresSession: false, run: (_) => ref.read(appUpdateControllerProvider.notifier).openStore())` in `notificationActionHandlersProvider`.
- [ ] **Step 3:** Implement `update_gate.dart` with two widgets.
  - **`AppUpdateScope({required Widget child})`** is a `ConsumerStatefulWidget` and `WidgetsBindingObserver`. It must sit above `MaterialApp`, because `WidgetsBinding.handlePopRoute` asks observers in registration order and this one has to answer before `WidgetsApp` pops the navigator.
    - Cold launch: run `checkForUpdate()` in a post-frame callback.
    - Foreground return: run `checkForUpdate()` on `resumed` after `paused`/`hidden`, using the `_backgrounded` pattern from `auth_flow_listener.dart:54-64`.
    - Remote Config: subscribe to `UpdatePolicyService.updates` and run `checkForUpdate()` on each event.
    - Back: `didPopRoute()` returns true while `decision.kind == required`. That swallows Android back.
  - **`UpdateGate({required Widget child})`** is used inside `MaterialApp.builder`.
    - When not required: return `child`.
    - When required: return `Stack(children: [ExcludeSemantics(child: ExcludeFocus(child: AbsorbPointer(child: child))), _UpdateGateScreen()])`. The routes stay alive underneath.
  - **`_UpdateGateScreen`** is an opaque `Material` page using theme colors.
    - Copy: title "Update required", body "This version of Cheetah is no longer supported. Update to continue."
    - **Update** calls `openStore()`.
    - **Retry** calls `checkForUpdate()` and shows a progress indicator while `checking`.
    - After a run with `lastCheckInconclusive`, show "Couldn't reach the store. Check your connection and try again."
- [ ] **Step 4:** Wire the widgets into `app.dart`.
  - In `CheetahApp.build`, wrap `_CheetahMaterialApp` as `AuthFlowListener(child: AppUpdateScope(child: _CheetahMaterialApp(...)))`.
  - In `builder`, wrap the existing guard: `child: UpdateGate(child: kDebugMode ? child! : InactivityGuard(child: child!))`.
  - The inactivity guard keeps running under the gate. A sign-out underneath it is harmless.
- [ ] **Step 5:** Write `docs/app-update-release-runbook.md`. It must cover all of the following:
  - **Parameter:** the exact JSON contract above and how to create the `app_update_policy_v1` parameter. Keep it a JSON string, with no conditions.
  - **Publish order:** binary on the intended track or territories → verify on a real device → publish an optional policy → raise the minimum only once the required update is approved.
  - **Android check:** with a Play-installed build on an eligible device, confirm Play reports the target code.
  - **iOS check:** `curl 'https://itunes.apple.com/lookup?id=<id>&country=ng'` shows the target `version`. The lookup is CDN-cached and can lag a release by hours. Capture the real App Store ID before enabling iOS.
  - **Rollback:** `enabled: false` or a lower minimum reaches open apps through real-time Remote Config. Apps not running pick it up on their next launch.
  - **iOS phased release:** avoid a required gate on iOS during phased availability.
- [ ] **Step 6:** Verify.
  - Run `flutter analyze`, `flutter test`, `flutter build apk --debug` and `flutter build ios --release --no-codesign`. Expected: no issues, all pass, both builds succeed.
  - Hand this device check to Kenechukwu: a Play internal-track build on the Pixel 7 Pro, run against a disabled policy, then optional, then required, then rolled back. Covers Review Focus 1, 3, 4 and 5.
  - iOS is verified against the live lookup on a physical device after publication. There is no test override in release builds.
- [ ] **Step 7:** Commit `feat(update): gate required updates and notify optional ones`.

## Release gate

- Do not publish an enabled policy until both are true:
  - A store release with a higher version is live on the intended track or territories.
  - The installed base runs a binary containing this feature.
- Confirm on an eligible Android device that Play reports the target build.
- Confirm the iOS lookup returns the matching app and target version in the configured country.
- Publish the optional policy first. Raise the minimum only once the required update is approved.
- Keep a Remote Config rollback ready.
