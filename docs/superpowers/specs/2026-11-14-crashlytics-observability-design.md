# Crashlytics observability design

## Intent

Make failures in the Cheetah Flutter app diagnosable. A report should tell an engineer where the failure originated, what operation or screen it affected, what the customer was trying to do, what the server returned when safe to retain, and the device class/model when available.

## Current state

- `lib/main.dart` initializes Firebase but does not install Crashlytics handlers. Initialization failure is swallowed so the app can continue. `AppBootstrap.initialize()` and `BocBrandMark.precache()` run before Firebase is ready.
- The FCM background handler (`firebaseMessagingBackgroundHandler` in `lib/helper/notification_delivery.dart`) initializes Firebase itself. On Android it runs in a separate isolate, so handlers installed in `main` do not cover it.
- There is one Firebase project and one `firebase_options.dart`; there are no build flavors. Staging and production differ only by `--dart-define=ENV` (`Env.isStaging`), so both report into the same Crashlytics apps.
- User and Core requests share `buildApiDio` and `ApiService` in `lib/app/network.dart`; `lib/app/core_network.dart` uses the same builder. `LoggingInterceptor` logs transport results, while `ApiService` turns API envelopes and parser errors into `ServiceResponse` errors. Dio's default `validateStatus` makes every non-2xx reply throw a `DioException`.
- `ApiMeta` already parses `meta.requestId` and `meta.correlationId` from the response envelope into `ServiceResponse.meta`.
- Session expiry already has explicit markers: `LocalSessionExpired` / `kLocalSessionExpiredCode` for a request the client never sent, and `sessionExpiryHandled` in `RequestOptions.extra` once the User 401 path has run. Core uses `expireSessionOnRemote401: false`, so a Core 401 surfaces as a Core-scoped error while the User session stays valid.
- Signed binary uploads use `lib/helper/signed_upload_client.dart` separately, with `validateStatus: (_) => true`.
- `MaterialApp` uses named routes from `lib/app/app_router.dart` with `initialRoute: '/bootstrap'`. `AppRouter.onGenerateRoute` never returns null: `_pageFor` returns a placeholder page for any unregistered name, so `onUnknownRoute` never runs. Flutter's default initial-route handling also generates `/` (not registered) beneath `/bootstrap` on cold start. The existing route tests override `onGenerateInitialRoutes`, so this path is untested. In practice, the main source of unregistered names is the server-supplied `route` field in push notifications (`lib/helper/notification_payload.dart`).
- `privacySensitivePathKey` templates cover three sensitive dynamic API paths. Setting that key also replaces the request and response bodies with `[REDACTED]` in production logs, so it cannot simply be added to every request. Dynamic paths are built by functions in `ApiEndpoints` / `CoreApiEndpoints` (some embed account numbers). The capability registry in `lib/app/feature_capability.dart` maps product features to endpoint templates, but a single endpoint can support several user actions.

## How the Crashlytics plugin behaves

Verified against `firebase_crashlytics` 5.0.3 (Android and iOS native code). These facts shape the design:

- `recordError(error, stack, reason:, information:)` is one method-channel call. Natively it sets the global custom keys `flutter_error_exception` (from `error.toString()`) and `flutter_error_reason`, writes `information` to the shared log buffer with `crashlytics.log`, then records the exception. Each event is therefore self-consistent even when requests run concurrently. However, the keys and log lines persist and appear on later reports, including native crashes.
- Every Dart error is recorded under the exception name `FlutterError`, so issue grouping depends on the stack frames. A synthetic error reported from one shared function, after an `await`, has nearly the same stack every time and would merge all API failures into one issue.
- Separate `setCustomKey` calls are global and outlive the event. Per-event fields must travel inside the single `recordError` call (exception message, `reason`, `information`), never as separate keys.
- Crashlytics keeps only a small number of recent non-fatals per session on the device (eight, per Firebase documentation) and has a capped log buffer. Non-fatals are uploaded on a later launch.

## Proposed approach

Use one small, injectable reporting service backed by Crashlytics. Install global Flutter and asynchronous error handlers once Firebase is ready, replaying any errors buffered during earlier startup. Report unexpected recoverable failures at the API, routing, and upload boundaries.

Each customer-facing service call passes one constant `ApiCallLabel` (feature, action, stage, endpoint template) through `RequestOptions.extra`. For each event, capture:

- origin (`flutter`, `platform`, `api`, `parser`, `routing`, or `upload`)
- feature, action, stage and the last registered route
- backend, HTTP method and safe endpoint template
- status/error category, server error code and safe request/correlation ID
- environment and device context

Keep the original stack trace for Flutter and parser errors. For API failures, capture the stack where the service method calls `ApiService`, before any `await`, so each service operation groups as its own issue. A call without a label reports `unknown_action` / `endpoint_unclassified` and is counted during validation so the call site can be fixed.

Capture a bounded server error summary from the existing `{success, message, code, errors}` envelope. Keep `code` as a stable field. Include a server `message` only when it matches a code-to-message allowlist (empty at launch) after bounding its length; otherwise use `[redacted]`. Keep at most five validation field names that pass a strict identifier pattern, and never their rejected values. Never attach whole response/request bodies, full URLs, query strings, credentials, account numbers, signed upload URLs, or raw route arguments. A server message may echo personal or financial data even when its JSON key is named `message`; the existing staging logger's permissive behavior must not be reused for Crashlytics.

For maximum diagnosis, the API should return a stable error code alongside a request/correlation ID that links to protected server logs. The client reads the ID from `ServiceResponse.meta` first, and uses a response header only if the API owners confirm one exists. When neither is present, it falls back to status/category. Crashlytics log lines are for reading one issue; they are not a durable, searchable log of every API response.

Use Crashlytics' built-in device/OS breakdown first. Add a coarse device type and model/manufacturer through `device_info_plus` only if the built-in console fields do not meet the debugging need. Do not use the app's persistent device identity token as a Crashlytics identifier.

## Reporting policy

### Collection

- Collection is enabled only when the build sets `--dart-define=CRASHLYTICS_ENABLED=true` and `kDebugMode` is false. Staging builds turn it on first; production turns it on after staging validation. When it is off, the app uses the no-op reporter and calls `setCrashlyticsCollectionEnabled(false)`.
- A global `env` custom key (`Env.environment`) separates staging from production reports in the shared project. Global keys are used only for stable app-wide fields (`env`, device type).

### Severity

- Fatal: native crashes only. The native SDK captures these with no Dart code involved.
- Non-fatal, origin `flutter`: errors from `FlutterError.onError` (for example layout, build and image-load errors). These do not end the process, and recording them as fatal would distort the crash-free figures.
- Non-fatal, origin `platform`: uncaught asynchronous errors from `PlatformDispatcher.onError`, for the same reason.

### API outcome classification

`kind` is one of `nonfatal`, `breadcrumb` or `ignored`. Rows are evaluated in order.

| Outcome | Kind |
| --- | --- |
| `DioExceptionType.cancel` | ignored |
| `LocalSessionExpired`, or `sessionExpiryHandled` (User 401) | breadcrumb |
| `DioExceptionType.connectionError` (device offline) | breadcrumb |
| Connection, send or receive timeout | nonfatal (throttled) |
| Other `DioException` with no response (bad certificate, unknown) | nonfatal |
| Core 401 | nonfatal: the User session accepted the same token, so this is an anomaly |
| 429 | nonfatal (throttled) |
| Any 5xx | nonfatal |
| 4xx without a valid `{success:false}` envelope | nonfatal |
| 4xx with a valid `{success:false}` envelope (400, 403, 404, 409, 422 and others) | breadcrumb |
| 2xx with `success != true` and a valid envelope | breadcrumb |
| 2xx whose body is not a JSON object | nonfatal (`malformed_envelope`) |
| 2xx `success:true` whose `data` the parser rejects | nonfatal, origin `parser`, original stack |

Every classified outcome except `ignored` writes one bounded breadcrumb line. The breadcrumb is the only record of an expected outcome in a release build. It is visible only on a later report from the same session, so it is an investigation aid, not an audit trail. If every individual response must be retained and searchable, that needs an approved, dedicated structured telemetry sink; Crashlytics alone cannot guarantee it.

### Routing and upload

- Navigation to an unregistered name: one non-fatal from the `_pageFor` placeholder branch. `/` (`Navigator.defaultRouteName`) is excluded because Flutter generates it during initial-route setup. The event carries the last registered route and a safe shape of the requested name: the name when it matches `^/[a-z0-9-]{1,32}$`, otherwise `[unrecognized]`. Arguments are never sent.
- Signed upload: non-fatal on 5xx, a timeout or a non-HTTP failure; breadcrumb on 400/403 (an expired link) and on `connectionError`. The endpoint is always `signed_upload`; the URL and headers are never sent.

### Volume

- Throttle by backend + method + endpoint + status category + server code + action: at most one non-fatal per key per 10 minutes, and at most 4 API/upload non-fatals per session. This keeps room in the device buffer for Flutter, platform and routing events. Suppressed events still write their breadcrumb with a `suppressed` marker. Tune these numbers after staging validation and record the final values in the runbook.

### Behaviour and context

- Preserve the app's current user-facing error and fallback behavior. Firebase/Crashlytics unavailability or a throwing reporter must never prevent startup or change an API result.
- Per-event fields travel only inside one `recordError` call: a stable exception message, a stable `reason`, and an `information` block. The runbook notes that the `flutter_error_*` keys on a native crash belong to the previous Dart event.
- Phase 1 context for uncaught UI errors is the last registered route plus the breadcrumb trail, which includes the label of each recent API call. The last API call does not reliably show what the customer tapped. Explicit UI action context is phase 2.
- Clear any optional pseudonymous user ID on logout and account switch. By default the design sets no user ID.

## Alternatives considered

1. **Central boundary reporting (chosen):** captures Dio, envelope, and parse failures with one consistent policy; call sites add one constant label each.
2. **Dio interceptor only:** simpler for HTTP and transport failures, but misses `{success: false}` replies and parser errors, and cannot infer the customer's intended action reliably.
3. **Log in every screen/provider:** can describe actions precisely, but is easy to miss and produces duplicate reports and inconsistent privacy handling.

## Phase 2 (not in the first plan)

- Explicit UI action context: initiating handlers for sign-in, transfer, payment, savings and KYC set a stable feature/action/stage that uncaught UI errors carry, cleared on completion or navigation.
- A structured telemetry sink, if retaining every API failure becomes a requirement.

## Constraints and acceptance

- Android and iOS are the first rollout targets. Verify Firebase configuration, native plugin wiring, and readable symbols for release builds.
- Tests must cover:
  - each row of the classification table, with no duplicate events
  - endpoint/action/stage metadata and `unknown_action` fallback
  - the server code/message/validation summary and request ID from `meta`
  - per-operation stack frames and two interleaved requests
  - privacy redaction of messages, paths and IDs
  - throttling limits
  - the unknown-route report, including the real `/bootstrap` cold start (no report for `/`)
  - device metadata fallback
  - Firebase initialization failure and a throwing reporter
  - collection disabled in debug builds and when the flag is off
- On test Android and iOS builds, deliberately trigger:
  - one Flutter error and one async error
  - an expected 4xx, a Core 401, and a 5xx with a request ID
  - one malformed response and one unknown notification route

  Confirm each intended issue or breadcrumb after relaunch.
- Crashlytics has finite event, key, and log capacity; use stable labels rather than unique exception messages or verbose logs.

## Open decisions before implementation

- Severity of Flutter framework and uncaught async errors. Proposed default: non-fatal. Firebase's sample code records them as fatal, which counts them against crash-free users.
- Whether a Core 401 is expected in any normal flow, such as a token Core rejects before User does. Proposed default: report it as a non-fatal.
- Whether the Firebase project's existing analytics policy permits Analytics breadcrumbs. The core plan does not require Analytics.
- Whether product/legal policy allows sending a device model. Proposed default: built-in Crashlytics hardware fields plus a coarse phone/tablet type, adding an explicit model only if needed.
- Whether to stop Flutter generating the unregistered `/` placeholder beneath `/bootstrap` by setting `onGenerateInitialRoutes`. That changes navigation behavior, so it is a separate fix; this design only excludes `/` from reporting.
