# Firebase Crashlytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture actionable, privacy-safe Flutter, API, navigation and upload failures in Crashlytics, recording where each originated, the operation it affected and safe server response details.

**Architecture:** An injectable `AppErrorReporter` owns every Crashlytics call and its volume policy. Startup buffers early errors, then installs global handlers once Firebase is ready. `ApiService` classifies each failed request with a pure classifier, builds a sanitized summary from the mapped `ServiceResponse`, and reports once. Each service call supplies a constant `ApiCallLabel`. The router reports unregistered names from its single placeholder branch.

**Tech Stack:** Flutter/Dart, Riverpod, Dio, `firebase_core: ^4.13.0`, `firebase_messaging: ^16.0.4`, `firebase_crashlytics`, optional `device_info_plus`.

**Spec:** [Crashlytics observability design](../specs/2026-11-14-crashlytics-observability-design.md)

## Global Constraints

- Preserve the two existing uncommitted user changes in `lib/app/network.dart` (the `receiveTimeout` parameter) and `lib/module/core_banking/service/core_account_service.dart`; run `git diff` on both before editing either.
- Never send to Crashlytics: request/response bodies, query strings, `RequestOptions.uri`, raw dynamic paths, signed upload URLs or headers, route arguments, credentials, account numbers, the persistent device identity token, `DioException.toString()`, or an unallowlisted server message.
- Literal markers: `[redacted]` (server message), `endpoint_unclassified`, `unknown_action`, `unknown_feature`, `unknown_stage`, `[unrecognized]` (route name), `signed_upload`.
- Patterns: server code `^[A-Za-z0-9_.-]{2,48}$`; request ID `^[A-Za-z0-9._:-]{1,64}$`; validation field name `^[a-zA-Z][a-zA-Z0-9_.]{0,40}$`, at most 5 per event; reportable route name `^/[a-z0-9-]{1,32}$`; server message at most 120 characters after allowlisting.
- Collection only when `bool.fromEnvironment('CRASHLYTICS_ENABLED')` is true and `kDebugMode` is false. Global custom keys only `env` (from `Env.environment`) and, if added, `device_type`.
- Severity: Dart errors (`FlutterError.onError`, `PlatformDispatcher.onError`) are non-fatal; fatal is native crashes only.
- Volume: at most 1 non-fatal per group key per 10 minutes; at most 4 API + upload non-fatals per session. Flutter, platform and routing events are not throttled.
- Per-event fields travel only inside one `recordError` call (`error.toString()`, `reason`, `information`). Never call `setCustomKey` for per-event fields.
- Never change a returned `ServiceResponse`, a returned `NotifierState`, or a route's page because of reporting. A throwing reporter is swallowed.
- `/` (`Navigator.defaultRouteName`) is never reported as an unknown route.
- Android and iOS only; other platforms keep the no-op reporter.

## Prerequisite (human, gates Task 4 step 6 and Task 9)

Ask the User and Core API owners, and record the answers in `docs/crashlytics-runbook.md`:

- Which error `code` values exist, and whether any `message` is guaranteed free of customer data. Those messages seed `kSafeServerMessages`; otherwise it ships empty.
- Whether `meta.requestId` / `meta.correlationId` are always present on errors, and whether a request-ID response header exists. Use the header only if they confirm it.
- Whether a Core 401 can occur in a normal flow (spec open decision).

Tasks 1–3 and most of Task 4 can proceed while this is pending.

## File map

| File | Responsibility |
| --- | --- |
| `pubspec.yaml`, `pubspec.lock`, `firebase.json`, `android/settings.gradle.kts`, `android/app/build.gradle.kts`, `ios/Runner.xcodeproj/project.pbxproj`, `.env.example`, `.env.stage`, `.env.prod` | Dependency, native wiring, symbol upload, collection flag |
| `lib/app/error_reporting.dart` (new) | Event model, `ApiCallLabel`, reporter interface, no-op reporter, throttle, reporting context |
| `lib/app/firebase_error_reporter.dart` (new) | `CrashlyticsSink` seam and the Crashlytics adapter |
| `lib/app/error_handlers.dart` (new) | Early error buffer, global handler install, collection decision, reporter factory |
| `lib/app/api_failure_classifier.dart` (new) | Pure classification of an API outcome |
| `lib/app/api_error_summary.dart` (new) | Sanitized code / message / field names / request ID |
| `lib/main.dart`, `lib/app.dart`, `lib/helper/notification_delivery.dart` | Startup wiring, provider override, background isolate |
| `lib/app/network.dart`, `lib/app/core_network.dart`, `lib/app/interceptors.dart` | Report once per failed request; backend labels; keep the label out of logs |
| 13 service files under `lib/module/**/service/` | One constant `ApiCallLabel` per call |
| `lib/helper/signed_upload_client.dart`, `lib/module/kyc/provider/kyc_providers.dart` | Upload failure reporting |
| `lib/app/app_router.dart` | Unknown-route report, `RouteTracker` observer |
| `test/support/recording_error_reporter.dart` (new) | Test double used by every task |
| `docs/crashlytics-runbook.md` (new) | Contract, policy, limits, symbol upload, troubleshooting |

## Review Focus

- A server `message` that echoes a phone number, account number, token or customer name must come out as `[redacted]`. Pinned in Task 4 (`redacts free-text and echoed messages`).
- A Core path built by `CoreApiEndpoints.bankAccount(accountNumber)` with no label must report `endpoint_unclassified`, and the account number must appear nowhere in the event. Pinned in Task 5 (`unlabeled dynamic path never leaks`).
- A session on a bad network (20 connection errors and 10 timeouts) must produce at most 4 non-fatals and 30 breadcrumbs. Pinned in Task 5 (`bad network session stays within budget`).
- A reporter that throws must leave every `ServiceResponse` identical. Pinned in Task 5 (`throwing reporter does not change the response`).
- A cold start on `/bootstrap` must report no unknown route, because Flutter also generates `/`. Pinned in Task 8 (`initial route setup generates root and never reports it`).

---

### Task 1: Install Crashlytics and native wiring

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`, `firebase.json`, `android/settings.gradle.kts`, `android/app/build.gradle.kts`, `ios/Runner.xcodeproj/project.pbxproj`, `.env.example`, `.env.stage`, `.env.prod`

**Interfaces:**
- Produces: `FirebaseCrashlytics.instance` usable after `initializeFirebase()`; build-time flag `CRASHLYTICS_ENABLED`.

- [ ] **Step 1:** Run `flutter pub add firebase_crashlytics` and accept the version that resolves with `firebase_core: ^4.13.0`.
- [ ] **Step 2:** Run `flutterfire configure` against the existing project and app IDs. Then run `git diff --exit-code lib/firebase_options.dart`. Expected: no diff; if there is one, revert it and wire Gradle and Xcode by hand instead.
- [ ] **Step 3:** Confirm `com.google.firebase.crashlytics` appears in both Gradle files and that a Crashlytics `upload-symbols` run-script phase exists in `project.pbxproj`.
- [ ] **Step 4:** Add `CRASHLYTICS_ENABLED=true` to `.env.stage`, and `CRASHLYTICS_ENABLED=false` to `.env.prod` and `.env.example`.
- [ ] **Step 5:** No `--obfuscate` or `--split-debug-info` flags exist in the repo (README, `.github/workflows/flutter-quality.yml`). Ask whoever produces release builds whether they pass these flags; record the answer and the matching symbol-upload command in the runbook draft.
- [ ] **Step 6:** Run `flutter pub get && flutter analyze`, then `flutter build apk --debug --dart-define-from-file=.env.stage` and `flutter build ios --debug --no-codesign --dart-define-from-file=.env.stage`. Expected: all succeed.
- [ ] **Step 7:** Commit: `git commit -m "chore(crashlytics): add plugin and native wiring"`.

### Task 2: Reporting boundary

**Files:**
- Create: `lib/app/error_reporting.dart`, `lib/app/firebase_error_reporter.dart`, `test/support/recording_error_reporter.dart`
- Test: `test/error_reporting_test.dart`

**Interfaces:**
- Produces (in `error_reporting.dart`):
  - `enum ErrorOrigin { flutter, platform, api, parser, routing, upload }`
  - `enum ErrorKind { nonfatal, breadcrumb, ignored }`
  - `enum ApiBackend { user, core, storage }`
  - `class ApiCallLabel { const ApiCallLabel({required String feature, required String action, required String stage, required String endpoint}); static const unlabeled; }`, where `unlabeled` uses `unknown_feature` / `unknown_action` / `unknown_stage` / `endpoint_unclassified`
  - `const apiCallLabelKey = 'telemetry.apiCallLabel';`
  - `class ApiFailure implements Exception { const ApiFailure(this.description); final String description; }`, whose `toString()` returns `description`
  - `class ErrorEvent { const ErrorEvent({required ErrorKind kind, required ErrorOrigin origin, required String reason, ApiCallLabel label = ApiCallLabel.unlabeled, ApiBackend? backend, String? method, String? category, int? statusCode, ApiErrorSummary? summary, String? route, Object? error, StackTrace? stack, bool throttled = false}); String get groupKey; String get breadcrumb; List<String> get information; }`
  - `abstract interface class AppErrorReporter { void report(ErrorEvent event); void recordUncaught(Object error, StackTrace stack, {required ErrorOrigin origin, FlutterErrorDetails? details}); void breadcrumb(String line); }`. Every method is fire-and-forget and never throws.
  - `class NoopErrorReporter implements AppErrorReporter { const NoopErrorReporter(); }`
  - `class ReportingContext { String? lastRoute; }` and the top-level `final reportingContext = ReportingContext();`
  - `class ReportThrottle { ReportThrottle({DateTime Function()? now, int perSessionLimit = 4, Duration window = const Duration(minutes: 10)}); bool allow(String groupKey); }`
  - `final errorReporterProvider = Provider<AppErrorReporter>((ref) => const NoopErrorReporter());`
- Produces (in `firebase_error_reporter.dart`):
  - `abstract interface class CrashlyticsSink { Future<void> recordError(Object error, StackTrace? stack, {String? reason, Iterable<Object> information, bool fatal}); Future<void> recordFlutterError(FlutterErrorDetails details); Future<void> log(String message); Future<void> setCustomKey(String key, Object value); }`
  - `class FirebaseCrashlyticsSink implements CrashlyticsSink`, a thin wrapper over `FirebaseCrashlytics.instance`
  - `class FirebaseErrorReporter implements AppErrorReporter { FirebaseErrorReporter(CrashlyticsSink sink, {ReportThrottle? throttle, ReportingContext? context}); }`
  - `class ApiErrorSummary { const ApiErrorSummary({String? code, required String message, List<String> fields = const [], String? requestId}); }`, a plain data class; Task 4 produces its values
- Test doubles, both in `test/support/recording_error_reporter.dart` and shared by later tasks:
  - `RecordingErrorReporter implements AppErrorReporter`, exposing `events`, `uncaught` and `breadcrumbs` lists, plus a `throwOnReport` flag
  - `FakeSink implements CrashlyticsSink`, exposing `recordErrorCalls`, `logCalls` and `setCustomKeyCalls`, plus `throwSync` / `throwAsync` flags

- [ ] **Step 1: Write the failing tests** in `test/error_reporting_test.dart`:

```dart
test('nonfatal event sends one recordError with stable reason and information', () async {
  final sink = FakeSink();
  FirebaseErrorReporter(sink).report(serverErrorEvent(action: 'authorize_transfer'));
  await pumpEventQueue();
  expect(sink.recordErrorCalls, hasLength(1));
  expect(sink.recordErrorCalls.single.reason, 'api server_5xx');
  expect(sink.recordErrorCalls.single.information, contains('action=authorize_transfer'));
  expect(sink.recordErrorCalls.single.fatal, isFalse);
  expect(sink.setCustomKeyCalls, isEmpty);
});

test('breadcrumb event only logs one bounded line', () async {
  final sink = FakeSink();
  FirebaseErrorReporter(sink).report(validationEvent());
  await pumpEventQueue();
  expect(sink.recordErrorCalls, isEmpty);
  expect(sink.logCalls.single.length, lessThanOrEqualTo(200));
});

test('throttle allows one per key per window and four per session', () {
  var now = DateTime(2026);
  final t = ReportThrottle(now: () => now);
  expect(t.allow('a'), isTrue);
  expect(t.allow('a'), isFalse);
  now = now.add(const Duration(minutes: 11));
  expect(t.allow('a'), isTrue);
  expect([t.allow('b'), t.allow('c'), t.allow('d')], [true, true, false]);
});

test('throttled nonfatal still writes a suppressed breadcrumb', ...); // logCalls.last contains 'suppressed'
test('sink that throws synchronously or asynchronously is swallowed', ...); // no exception escapes report()
test('uncaught flutter error is recorded non-fatal with route in information', ...); // fatal == false, 'route=/home'
```

- [ ] **Step 2:** Run `flutter test test/error_reporting_test.dart`. Expected: FAIL, because the symbols are not defined.
- [ ] **Step 3:** Implement both files. Specifically:
  - `groupKey` is `backend|method|endpoint|category|code|action`.
  - `breadcrumb` is one space-separated line truncated to 200 characters.
  - `information` is `key=value` lines covering origin, backend, method, endpoint, feature, action, stage, status, category, code, message, fields, request_id and route.
  - `FirebaseErrorReporter.report` applies the throttle to `api`/`upload` non-fatals only, and fills `route` from the context.
  - Wrap each sink call in `unawaited(Future.sync(...).catchError((_) {}))`, inside a synchronous `try`.
- [ ] **Step 4:** Run `flutter test test/error_reporting_test.dart && flutter analyze`. Expected: PASS, no issues.
- [ ] **Step 5:** Commit: `git commit -m "feat(crashlytics): add reporting boundary"`.

### Task 3: Startup, global handlers and background isolate

**Files:**
- Create: `lib/app/error_handlers.dart`
- Modify: `lib/main.dart`, `lib/app.dart` (a `CheetahApp.errorReporter` parameter that overrides `errorReporterProvider` next to `firebaseReadyProvider`), `lib/helper/notification_delivery.dart:28-33`
- Test: `test/error_handlers_test.dart`

**Interfaces:**
- Consumes: `AppErrorReporter`, `NoopErrorReporter`, `FirebaseErrorReporter`, `FirebaseCrashlyticsSink`, `ErrorOrigin` (Task 2).
- Produces:
  - `const kCrashlyticsEnabledFlag = bool.fromEnvironment('CRASHLYTICS_ENABLED');`
  - `bool crashlyticsCollectionAllowed({required bool flag, required bool debugMode})`
  - `class EarlyErrorBuffer { void install(); List<BufferedError> drain(); }`, which holds at most 10 entries. `BufferedError` is a record `({Object error, StackTrace stack, ErrorOrigin origin, FlutterErrorDetails? details})`.
  - `Future<AppErrorReporter> createErrorReporter({required bool firebaseReady})`. It sets `env`, calls `setCrashlyticsCollectionEnabled`, and returns the no-op reporter when not allowed.
  - `void installErrorHandlers(AppErrorReporter reporter)`, which is idempotent per isolate. With a no-op reporter it restores `FlutterError.presentError` and clears `PlatformDispatcher.instance.onError`.

- [ ] **Step 1: Write the failing tests:**

```dart
test('collection requires the flag and a non-debug build', () {
  expect(crashlyticsCollectionAllowed(flag: true, debugMode: false), isTrue);
  expect(crashlyticsCollectionAllowed(flag: true, debugMode: true), isFalse);
  expect(crashlyticsCollectionAllowed(flag: false, debugMode: false), isFalse);
});

test('firebase not ready yields the no-op reporter', () async {
  expect(await createErrorReporter(firebaseReady: false), isA<NoopErrorReporter>());
});

testWidgets('framework error is forwarded once as origin flutter', ...);   // RecordingErrorReporter.uncaught.single.origin == ErrorOrigin.flutter
test('platform error is forwarded once and handled', ...);                 // PlatformDispatcher.instance.onError!(e, s) == true; one record
test('errors buffered before firebase are replayed once after install', ...);
test('installing twice does not duplicate reports', ...);
```

Save and restore `FlutterError.onError` and `PlatformDispatcher.instance.onError` in `tearDown`.

- [ ] **Step 2:** Run `flutter test test/error_handlers_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement `error_handlers.dart`. The Flutter handler calls `FlutterError.presentError(details)`, then reports. The platform handler calls `debugPrint` in debug builds and returns `true`.
- [ ] **Step 4:** Wire up `main.dart`:
  - Create and install `EarlyErrorBuffer` as the first line after `ensureInitialized()`.
  - After the Firebase `try`/`catch`, call `createErrorReporter`, then `installErrorHandlers`, then replay `drain()`.
  - Pass the reporter to `CheetahApp`.
  - In `notification_delivery.dart`, wrap the `initializeFirebase` argument so that, after it resolves, it calls `installErrorHandlers(await createErrorReporter(firebaseReady: true))`.
- [ ] **Step 5:** Run `flutter test test/error_handlers_test.dart test/cold_launch_auth_test.dart && flutter analyze`. Expected: PASS.
- [ ] **Step 6:** Commit: `git commit -m "feat(crashlytics): install global handlers after Firebase"`.

### Task 4: API outcome classifier and safe summary

**Files:**
- Create: `lib/app/api_failure_classifier.dart`, `lib/app/api_error_summary.dart`
- Test: `test/api_failure_classifier_test.dart`, `test/api_error_summary_test.dart`

**Interfaces:**
- Consumes: `ApiBackend`, `ErrorKind`, `ErrorOrigin`, `ApiErrorSummary` (Task 2); `ServiceResponse`, `ApiMeta` (`lib/app/services.dart`).
- Produces:
  - `class ApiOutcome { const ApiOutcome({required ApiBackend backend, int? statusCode, DioExceptionType? dioType, bool hasEnvelope = false, bool? success, bool parserFailed = false, bool localSessionExpired = false, bool sessionExpiryHandled = false}); }`
  - `typedef ApiClassification = ({ErrorKind kind, ErrorOrigin origin, String category});`
  - `ApiClassification classifyApiOutcome(ApiOutcome outcome)`. Categories: `ok`, `cancel`, `session_expired`, `offline`, `timeout`, `transport`, `core_401`, `rate_429`, `server_5xx`, `client_4xx_malformed`, `client_4xx`, `success_false`, `malformed_envelope`, `parser`.
  - `ApiErrorSummary summarizeApiError(ServiceResponse<Object?> response, {String? headerRequestId})`. Its `message` is either an allowlisted string or `[redacted]`.
  - `const Map<String, String> kSafeServerMessages = {};`, keyed by server code and seeded only from the Prerequisite answers

- [ ] **Step 1: Write the failing classifier test**. It is table-driven, with one case per row of the spec's classification table, in order:

```dart
const cases = <(ApiOutcome, ErrorKind, String)>[
  (ApiOutcome(backend: ApiBackend.user, dioType: DioExceptionType.cancel), ErrorKind.ignored, 'cancel'),
  (ApiOutcome(backend: ApiBackend.user, statusCode: 401, localSessionExpired: true), ErrorKind.breadcrumb, 'session_expired'),
  (ApiOutcome(backend: ApiBackend.user, statusCode: 401, hasEnvelope: true, sessionExpiryHandled: true), ErrorKind.breadcrumb, 'session_expired'),
  (ApiOutcome(backend: ApiBackend.user, dioType: DioExceptionType.connectionError), ErrorKind.breadcrumb, 'offline'),
  (ApiOutcome(backend: ApiBackend.core, dioType: DioExceptionType.receiveTimeout), ErrorKind.nonfatal, 'timeout'),
  (ApiOutcome(backend: ApiBackend.user, dioType: DioExceptionType.badCertificate), ErrorKind.nonfatal, 'transport'),
  (ApiOutcome(backend: ApiBackend.core, statusCode: 401, hasEnvelope: true, success: false), ErrorKind.nonfatal, 'core_401'),
  (ApiOutcome(backend: ApiBackend.user, statusCode: 429, hasEnvelope: true, success: false), ErrorKind.nonfatal, 'rate_429'),
  (ApiOutcome(backend: ApiBackend.user, statusCode: 503, hasEnvelope: true, success: false), ErrorKind.nonfatal, 'server_5xx'),
  (ApiOutcome(backend: ApiBackend.user, statusCode: 404), ErrorKind.nonfatal, 'client_4xx_malformed'),
  for (final s in [400, 403, 404, 409, 422])
    (ApiOutcome(backend: ApiBackend.user, statusCode: s, hasEnvelope: true, success: false), ErrorKind.breadcrumb, 'client_4xx'),
  (ApiOutcome(backend: ApiBackend.user, statusCode: 200, hasEnvelope: true, success: false), ErrorKind.breadcrumb, 'success_false'),
  (ApiOutcome(backend: ApiBackend.user, statusCode: 200), ErrorKind.nonfatal, 'malformed_envelope'),
  (ApiOutcome(backend: ApiBackend.user, statusCode: 200, hasEnvelope: true, success: true, parserFailed: true), ErrorKind.nonfatal, 'parser'),
];
```

The `parser` row must also assert `origin == ErrorOrigin.parser`.

- [ ] **Step 2: Write the failing summary tests:**

```dart
test('keeps a valid code and redacts an unlisted message', ...);       // code 'TRANSFER_FAILED', message '[redacted]'
test('redacts free-text and echoed messages', ...);                    // messages containing '08012345678', '0123456789', 'Bearer abc', 'John Okafor' -> '[redacted]'
test('uses an allowlisted message for its code, truncated to 120', ...);
test('rejects codes outside the pattern', ...);                        // 'x', '<script>', 49 chars, '{"a":1}' -> null
test('keeps at most five valid field names and never values', ...);   // errors [{'field':'amount','message':'0801...'}, {'08012345678':'bad'}] -> ['amount']
test('reads request id from meta before header and validates it', ...); // meta.requestId wins; 'abc\nInjected' -> null
```

- [ ] **Step 3:** Run `flutter test test/api_failure_classifier_test.dart test/api_error_summary_test.dart`. Expected: FAIL.
- [ ] **Step 4:** Implement both files. Classification evaluates rules in the table's order. The summary reads field names from the `field`/`path`/`param` values of map entries and from map keys, keeping only names that pass the pattern.
- [ ] **Step 5:** Run the same command. Expected: PASS.
- [ ] **Step 6:** Seed `kSafeServerMessages` from the Prerequisite answers, if any. Commit: `git commit -m "feat(crashlytics): classify API outcomes and sanitize summaries"`.

### Task 5: Report from `ApiService`

**Files:**
- Modify: `lib/app/network.dart:48-261`, `lib/app/core_network.dart:36-39`, `lib/app/interceptors.dart` (`_requestExtra` removes `apiCallLabelKey`)
- Test: `test/network_reporting_test.dart`

**Interfaces:**
- Consumes: Tasks 2 and 4.
- Produces: `const ApiService(Dio dio, {ApiBackend backend = ApiBackend.user, AppErrorReporter reporter = const NoopErrorReporter()})`. The 39 existing test constructions keep compiling. `apiServiceProvider` passes `ref.watch(errorReporterProvider)`; `coreApiServiceProvider` also passes `backend: ApiBackend.core`.

- [ ] **Step 1: Write the failing tests.** Reuse the `_Adapter` pattern from `test/api_conflict_data_test.dart`, extended to throw a given `DioExceptionType`:

```dart
test('503 reports one nonfatal with label, code and request id', ...);
// events.single: kind nonfatal, category 'server_5xx', label.action 'authorize_transfer', summary.requestId 'req-1'
test('validation 422 reports a breadcrumb, not a nonfatal', ...);
test('cancel reports nothing', ...);
test('parser failure reports origin parser with the parser stack', ...);   // event.stack.toString() contains the parser closure frame
test('stack captured at call site names the calling function', ...);      // event.stack.toString() contains 'callingServiceMethod'
test('core service is labelled core backend', ...);
test('two interleaved failures keep their own labels and summaries', ...);
test('unlabeled dynamic path never leaks', ...);
// path CoreApiEndpoints.bankAccount('0123456789'), no label -> endpoint 'endpoint_unclassified';
// '0123456789' absent from error.toString(), reason, information and breadcrumb
test('throwing reporter does not change the response', ...);              // compare ServiceResponse with Noop vs throwOnReport
test('bad network session stays within budget', ...);
// FirebaseErrorReporter(FakeSink) + 20 connectionError + 10 receiveTimeout -> recordErrorCalls.length <= 4, logCalls.length == 30
test('label is not written to the staging request log', ...);             // LoggingInterceptor output lacks 'telemetry.apiCallLabel'
```

- [ ] **Step 2:** Run `flutter test test/network_reporting_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement:
  - Each public method passes `method:` and `callStack: StackTrace.current` to `_request`.
  - `_mapResponse` and `_mapDioException` return the existing `ServiceResponse` plus an `ApiOutcome`.
  - Change the parser `catch` to `catch (error, stack)` and keep the stack.
  - After mapping, build one `ErrorEvent`: label from `requestExtra[apiCallLabelKey]` (else `ApiCallLabel.unlabeled`), `ApiFailure('$backend $method ${label.endpoint} $category')`, reason `'api $category'`, and the summary from `summarizeApiError`.
  - Call `reporter.report` inside `try { } catch (_) {}`, then return the unchanged response.
- [ ] **Step 4:** Run `flutter test test/network_reporting_test.dart test/api_conflict_data_test.dart test/core_network_test.dart && flutter analyze`. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -m "feat(crashlytics): report API failures once from ApiService"`.

### Task 6: Label every service call

**Files:**
- Modify (call count in brackets):
  - `account/service/core_transaction_limit_service.dart` [4]
  - `account/service/user_service.dart` [3]
  - `account/service/withdrawal_bank_service.dart` [6]
  - `core_banking/service/core_account_service.dart` [6]
  - `core_banking/service/core_beneficiary_service.dart` [2]
  - `core_banking/service/core_bill_service.dart` [2]
  - `core_banking/service/core_transfer_service.dart` [6]
  - `core_banking/service/transaction_reconfirmation_service.dart` [2]
  - `home/service/home_service.dart` [1]
  - `kyc/service/kyc_service.dart` [7]
  - `onboarding/service/auth_service.dart` [3]
  - `savings/service/core_flex_interest_service.dart` [2]
  - `savings/service/core_savings_plan_service.dart` [7]

  All are under `lib/module/`, 51 calls in total.
- Test: `test/api_call_label_coverage_test.dart`

**Interfaces:**
- Consumes: `ApiCallLabel`, `apiCallLabelKey` (Task 2).
- Produces: a `static const` `ApiCallLabel` per call in each service, merged into `requestExtra` next to any existing `privacySensitivePathKey`. `endpoint` is the path constant for static paths, or the same template string `privacySensitivePathKey` uses for dynamic ones. Do not add `privacySensitivePathKey` where it is absent: it also redacts production log bodies.

- [ ] **Step 1: Write the failing coverage test.** It reads each `lib/module/**/service/*.dart` file and asserts that the number of `getData`/`postData`/`patchData`/`deleteData` calls equals the number of `apiCallLabelKey` usages in that file. On failure it names the file.
- [ ] **Step 2:** Run `flutter test test/api_call_label_coverage_test.dart`. Expected: FAIL, listing all 13 files.
- [ ] **Step 3:** Add labels file by file. Use the feature names from `lib/app/feature_capability.dart` where one fits. Make each action the customer's intent (for example `authorize_transfer`, not `post_transfer`), and give the stage within that action (for example `verify_pin`).
- [ ] **Step 4:** Run `flutter test && flutter analyze`. Expected: PASS, with the full suite green.
- [ ] **Step 5:** Commit: `git commit -m "feat(crashlytics): label service calls with feature, action and stage"`.

### Task 7: Signed upload reporting

**Files:**
- Modify: `lib/helper/signed_upload_client.dart`, `lib/module/kyc/provider/kyc_providers.dart`
- Test: `test/signed_upload_reporting_test.dart`

**Interfaces:**
- Consumes: `AppErrorReporter`, `ErrorEvent`, `ApiCallLabel`, `ApiBackend.storage`, `errorReporterProvider` (Task 2).
- Produces: a `SignedUploadClient` constructor parameter `AppErrorReporter reporter = const NoopErrorReporter()`, and the label `ApiCallLabel(feature: 'kyc', action: 'upload_kyc_document', stage: 'upload', endpoint: 'signed_upload')`.

- [ ] **Step 1: Write the failing tests:**
  - `upload 500 reports a nonfatal with endpoint signed_upload`
  - `expired link 403 reports a breadcrumb`
  - `offline upload reports a breadcrumb`
  - `upload event never contains the signed url, query or headers`, which asserts that `X-Amz-Signature` and the host are absent from every event string
- [ ] **Step 2:** Run `flutter test test/signed_upload_reporting_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement reporting next to the existing `NotifierState` returns, leaving those returns unchanged. Then pass `ref.watch(errorReporterProvider)` in `kyc_providers.dart`.
- [ ] **Step 4:** Run the same test plus `flutter analyze`. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -m "feat(crashlytics): report signed upload failures"`.

### Task 8: Unknown routes and route context

**Files:**
- Modify: `lib/app/app_router.dart:112-180`, `lib/app.dart:91` (`navigatorObservers: [RouteTracker()]`), `lib/main.dart` (set `AppRouter.reporter`)
- Test: `test/route_reporting_test.dart`

**Interfaces:**
- Consumes: `AppErrorReporter`, `reportingContext` (Task 2).
- Produces:
  - `static AppErrorReporter reporter = const NoopErrorReporter();` on `AppRouter`. Tests set and reset it.
  - `class RouteTracker extends NavigatorObserver`, which writes `reportingContext.lastRoute` only for names in `AppRoutes.allRoutes`.
  - `String safeRouteName(String? name)`, returning the name if it matches `^/[a-z0-9-]{1,32}$`, else `[unrecognized]`.

- [ ] **Step 1: Write the failing tests:**

```dart
test('unregistered name reports once and still shows the fallback page', ...);  // one routing event, reason 'routing unknown_route'
test('registered public and private routes report nothing', ...);
test('initial route setup generates root and never reports it', ...);
// pump MaterialApp(initialRoute: '/a', onGenerateRoute: recordingGenerator) -> generated ['/', '/a'];
// then AppRouter.onGenerateRoute(RouteSettings(name: '/')) -> no events
test('unsafe names are sent as unrecognized and arguments never', ...);  // '/x?id=0123456789' -> '[unrecognized]'
test('tracker keeps the last registered route only', ...);
```

- [ ] **Step 2:** Run `flutter test test/route_reporting_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Report from the `_pageFor` placeholder branch only, skipping `Navigator.defaultRouteName`. Leave `onUnknownRoute` and the placeholder page unchanged.
- [ ] **Step 4:** Run `flutter test test/route_reporting_test.dart test/back_stack_test.dart test/cold_launch_auth_test.dart test/private_route_gate_test.dart && flutter analyze`. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -m "feat(crashlytics): report unregistered routes and track route context"`.

### Task 9: Device context, device validation, runbook and rollout

**Files:**
- Modify: `lib/app/firebase_error_reporter.dart`; `pubspec.yaml` only if `device_info_plus` is needed
- Create: `docs/crashlytics-runbook.md`
- Test: `test/error_reporting_test.dart`

**Interfaces:**
- Produces, only if needed: `Future<String> coarseDeviceType()`, returning `phone`, `tablet` or `other`. It is computed once per launch, set as the global key `device_type`, and falls back to `other` if the plugin throws.

- [ ] **Step 1:** Install a staging build (`--dart-define-from-file=.env.stage`, release mode) on one Android and one iOS device, with a temporary trigger screen that is not committed. Trigger each of these: a framework error, an async error, a validation 4xx, a Core 401, a 5xx with a request ID, a 5xx with an echoed phone number in `message`, a malformed reply, and an unknown notification `route`. Relaunch the app.
- [ ] **Step 2:** In the Firebase console, confirm for each event the origin, `env=staging`, the endpoint template, action/stage, category, code, `[redacted]` for the echoed message, the request ID, the route, and the built-in device and OS fields. Confirm the 4xx appears only as a log line on a later report. Confirm that API failures from different service methods appear as separate issues.
- [ ] **Step 3:** If the built-in hardware fields are not enough, write the failing test `device type falls back to other when the plugin throws`. Then add `device_info_plus` and `coarseDeviceType`, and run `flutter test test/error_reporting_test.dart`. Otherwise skip this step and record why in the runbook.
- [ ] **Step 4:** Write `docs/crashlytics-runbook.md` covering:
  - the collection flag and rollout steps
  - the classification table and throttle values, as tuned
  - the API contract from the Prerequisite
  - which fields are visible per issue versus searchable
  - that the `flutter_error_*` keys on a native crash belong to the previous Dart event
  - device buffer and log limits
  - symbol upload
  - a troubleshooting path
- [ ] **Step 5:** Remove the trigger screen. Run `flutter test && flutter analyze` and both release builds. Then run `git diff main --stat` and check it for secrets and unrelated changes.
- [ ] **Step 6:** Commit: `git commit -m "docs(crashlytics): add runbook and validation results"`.
- [ ] **Step 7:** After a staging validation week, set `CRASHLYTICS_ENABLED=true` in `.env.prod` in a separate commit.

## Out of scope (separate changes)

- Phase 2 UI action context (see spec).
- Setting `onGenerateInitialRoutes` so the `/` placeholder is not built beneath `/bootstrap` (a navigation behavior change).
- `signed_upload_client.dart` logs the full signed URL and headers through `apiLogger`, whose `ProductionFilter` also prints in release builds. Fix this in its own change.

## Source notes

- [Firebase Flutter Crashlytics setup](https://firebase.google.com/docs/crashlytics/flutter/get-started): plugin, `flutterfire configure`, handlers, and symbol setup.
- [Customize Flutter Crashlytics reports](https://firebase.google.com/docs/crashlytics/flutter/customize-crash-reports): non-fatal limits, custom keys and log limits.
- `firebase_crashlytics` 5.0.3 native sources (`FlutterFirebaseCrashlyticsPlugin.java`, `FLTFirebaseCrashlyticsPlugin.m`): `information` goes to `log`, and `reason` and the exception text become global keys.
