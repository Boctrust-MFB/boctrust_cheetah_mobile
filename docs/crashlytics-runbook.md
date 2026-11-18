# Crashlytics runbook

Privacy-safe Firebase Crashlytics reporting for the Cheetah app. Spec: `docs/superpowers/specs/2026-11-14-crashlytics-observability-design.md`.

## 1. Collection flag and rollout

- Flag: `--dart-define=CRASHLYTICS_ENABLED=true` (via `--dart-define-from-file`).
  - `.env.stage`: `true`. `.env.prod`: `false`. `.env.example`: `false`.
  - `.env.stage` and `.env.prod` are git-ignored, so the flag is local only. Each builder must add `CRASHLYTICS_ENABLED=true` to their own `.env.stage`; only `.env.example` is committed.
- Collection also requires a non-debug build and Android or iOS. Otherwise the app uses the no-op reporter. On a supported platform with Firebase initialized, a disallowed build also calls `setCrashlyticsCollectionEnabled(false)`. That call is NOT made on unsupported platforms or when Firebase init fails; there the no-op reporter simply never sends anything.
- Staging and production share one Firebase project and one set of Crashlytics apps. The only global custom key is `env` (`Env.environment`), and it is the only filterable field. There is no `device_type` key.
- Rollout:
  1. Build staging with `.env.stage`, release mode, and run the staging validation (section 9).
  2. After a validation week with no privacy findings, set `CRASHLYTICS_ENABLED=true` in `.env.prod` in a separate commit. Status: Pending.

## 2. Severity

| Source | Kind |
| --- | --- |
| Native crash | Fatal (captured by the native SDK) |
| `FlutterError.onError` (origin `flutter`) | Non-fatal |
| `PlatformDispatcher.onError` (origin `platform`) | Non-fatal |
| API, parser, routing, upload | Per the tables below |

## 3. API classification (evaluated in order)

Source: `lib/app/api_failure_classifier.dart`. Kinds: `nonfatal`, `breadcrumb` (log line only), `ignored`.

| Outcome | Category | Kind |
| --- | --- | --- |
| `DioExceptionType.cancel` | `cancel` | ignored |
| `LocalSessionExpired` or `sessionExpiryHandled` (User 401) | `session_expired` | breadcrumb |
| `connectionError` | `offline` | breadcrumb |
| Connection, send or receive timeout | `timeout` | nonfatal |
| Other `DioException` with no response | `transport` | nonfatal |
| Core 401 | `core_401` | nonfatal |
| 429 | `rate_429` | nonfatal |
| Any 5xx | `server_5xx` | nonfatal |
| 4xx without a valid `{success:false}` envelope | `client_4xx_malformed` | nonfatal |
| 4xx with a valid `{success:false}` envelope | `client_4xx` | breadcrumb |
| 2xx, body not a JSON object | `malformed_envelope` | nonfatal |
| 2xx envelope with `success != true` | `success_false` | breadcrumb |
| 2xx `success:true`, parser rejects `data` | `parser` (origin `parser`, original stack) | nonfatal |
| Anything else | `ok` | breadcrumb |

Every classified outcome except `ignored` writes one bounded breadcrumb. Breadcrumbs only show up on a later report from the same session. They are not an audit trail.

### Upload (`lib/helper/signed_upload_client.dart`)

Endpoint is always `signed_upload` (feature `kyc`, action `upload_kyc_document`). The URL and headers are never sent.

| Outcome | Category | Kind |
| --- | --- | --- |
| 5xx | `server_5xx` | nonfatal |
| 400 or 403 | `expired_link` | breadcrumb |
| Other 4xx (not 400/403) | `client_4xx` | nonfatal |
| Any other non-2xx (missing/0, 1xx, 3xx) | `unexpected_status` | nonfatal |
| `connectionError` | `offline` | breadcrumb |
| Timeout (connect, send, receive) | `timeout` | nonfatal |
| Other transport failure | `transport` | nonfatal |
| `cancel` | none | ignored |

### Routing

One non-fatal for navigation to an unregistered name. `/` is excluded (Flutter generates it beneath `/bootstrap` on cold start). The name is shown only if it matches `^/[a-z0-9-]{1,32}$`, otherwise `[unrecognized]`. Route arguments are never sent. The main source is the server-supplied `route` in push notifications. Notification taps never reach the router with an unknown name: `NotificationNavigator.parse` (`lib/helper/notification_navigator.dart`) replaces a `route` not in `AppRoutes.allRoutes` with `/notifications` and, in that fallback, reports the same `routing unknown_route` non-fatal (once per parse, name sanitized, payload and `id` never sent). Navigation is unchanged. The router's own report covers every other unregistered name.

### Throttle (`lib/app/error_reporting.dart`, applied in `lib/app/firebase_error_reporter.dart`)

- Applies only to non-fatals with origin `api`, `upload` or `parser`, which covers every non-fatal row in the API and upload tables above.
- Not throttled: origins `flutter`, `platform` and `routing`. Breadcrumbs are never throttled.

- At most 1 non-fatal per group key per 10 minutes.
- At most 4 API and upload non-fatals per session, to leave device-buffer room for Flutter, platform and routing events.
- Group key: `backend|method|endpoint|category|code|action`.
- Suppressed events still write their breadcrumb, marked `suppressed` (placed right after the origin so the 200-character truncation never drops it).
- Routing events carry no endpoint/feature/action/stage lines; those appear only for origins `api`, `parser` and `upload`, so the `unknown_action` count measures unlabeled API calls only.
- These are the launch values. Tune them after staging validation and record the final numbers here.

## 4. What an event looks like

- Crashlytics sink reason format: `<origin> <category>`, for example `api server_5xx`, `upload expired_link`, `routing unknown_route`.
- Per-event fields (origin, feature, action, stage, last route, backend, method, endpoint template, category, status, code, request ID, bounded validation field names) travel inside one `recordError` call: the exception message, `reason`, and the `information` log lines. They are visible on the event in the console but are NOT indexed or searchable.
- Only the global key `env` is filterable.
- Never sent: response or request bodies, full URLs, query strings, credentials, account numbers, signed URLs, raw route arguments, rejected field values.
- Server `message` is sent only if allowlisted in `kSafeServerMessages`. That list is empty, so every server message shows as `[redacted]`.

## 5. Native crashes and `flutter_error_*` keys

The plugin sets the global keys `flutter_error_exception` and `flutter_error_reason` on every `recordError`, and they persist. On a native crash report, those keys belong to the previous Dart event, not the crash. Ignore them when triaging a native crash.

## 6. Device limits and device context

- Crashlytics keeps about eight recent non-fatals per session on the device, and a capped log buffer (old lines drop first).
- Non-fatals upload on the next launch, so an event is not visible until the app is relaunched.
- Device and OS context: use Crashlytics' built-in device/OS fields. `device_info_plus` and a coarse `device_type` key were deliberately not added. The spec says to use the built-in fields first, and whether they are enough is decided at staging validation. If they are not, add `coarseDeviceType()` (`phone`, `tablet`, `other`, falling back to `other` if the plugin throws) with a test for the fallback. Do not use the app's persistent device identity token as a Crashlytics identifier.

## 7. API contract (prerequisite)

Answers from the User and Core API owners are NOT yet available. Current client defaults:

- `kSafeServerMessages` is empty, so every server message is `[redacted]`.
- Request ID comes only from `meta.requestId` or `meta.correlationId`. No response header is read.
- A Core 401 is reported as a non-fatal.

Questions to ask the API owners:

1. Which error codes exist, and is any message guaranteed to be free of customer data (to allowlist it)?
2. Are `meta.requestId` / `meta.correlationId` always present on errors? Is there a request-ID response header?
3. Does a Core 401 occur in any normal flow (if so, downgrade it to a breadcrumb)?
4. Confirm error `code` values never embed customer data. A code like `ACC_0123456789` would pass the code pattern and be sent.

## 8. Symbol upload

- iOS: the Runner run-script phase "Upload Crashlytics Symbols" uploads dSYMs. It only does work with dSYMs (release or profile). It is untested until the first release archive.
- Android: the Crashlytics Gradle plugin uploads the mapping file for release builds.
- Decision: release builds use `--obfuscate --split-debug-info=build/symbols/<android|ios>`. Upload the matching symbols after every release build, from the same build output:
  - Android: `firebase crashlytics:symbols:upload --app=1:94126412804:android:ce857374353d9b82291151 build/symbols/android`
  - iOS: `firebase crashlytics:symbols:upload --app=1:94126412804:ios:a21014492da995dd291151 build/symbols/ios`
  - Keep `build/symbols/` for each shipped build number; stacks from that build cannot be read without it. The directory is git-ignored.
  - Exact build commands are in `docs/app-update-release-runbook.md`, "Production build and preflight".

## 9. Staging validation (Pending, not yet run)

Install a release staging build (`--dart-define-from-file=.env.stage`) on one Android and one iOS device, using a temporary uncommitted trigger screen. Relaunch after triggering.

Triggers:

- [ ] Pending, not yet run: Flutter framework error
- [ ] Pending, not yet run: async (uncaught) error
- [ ] Pending, not yet run: validation 4xx
- [ ] Pending, not yet run: Core 401
- [ ] Pending, not yet run: 5xx with a request ID
- [ ] Pending, not yet run: 5xx with an echoed phone number in `message`
- [ ] Pending, not yet run: malformed reply
- [ ] Pending, not yet run: unknown notification `route` (tap a push whose `route` is unregistered; expect one `routing unknown_route`, reported by `NotificationNavigator.parse`, and the app lands on Notifications)
- [ ] Pending, not yet run: background and terminated push receive-and-tap check (Task 1 bumped `firebase_core` 4.13 to 4.15.2 and `firebase_messaging` 16.5 to 16.7.1)
- [ ] Pending, not yet run: Dojah KYC smoke test (same dependency bump)

Console checks (for each event):

- [ ] Pending, not yet run: origin, `env=staging`, endpoint template, action/stage, category, code
- [ ] Pending, not yet run: echoed message shows `[redacted]`
- [ ] Pending, not yet run: request ID and route present
- [ ] Pending, not yet run: built-in device and OS fields (decides whether `device_info_plus` is needed)
- [ ] Pending, not yet run: the 4xx appears only as a log line on a later report
- [ ] Pending, not yet run: GATE, see "Grouping gate" below. API non-fatals from different service operations appear as separate Crashlytics issues
- [ ] Pending, not yet run: symbols upload and stacks are readable on a real release archive (Android and iOS)

Known gaps to verify:

- Grouping gate: this MUST pass before `.env.prod` is flipped to `true`. Every call-site stack's top frame is `ApiService.getData/postData/...`, so non-fatals from different service operations may merge into one issue. Trigger at least two different operations that fail the same way and confirm they land as separate issues. If they merge, the options are:
  1. Trim the top `ApiService.*` frame before reporting. Shared helpers (for example `CoreTransferService._check` and `_initiate`) then become the shared top frame, so verify those still separate by operation.
  2. Build the reported stack with a synthetic first frame derived from the label (for example `api.<action>.<stage>`), and check that it survives obfuscated traces.
- Symbol upload on a real release archive (section 8).

Prod rollout (section 1): Pending, after the staging week.

## 10. Troubleshooting

| Symptom | Check |
| --- | --- |
| No reports at all | `CRASHLYTICS_ENABLED=true` in the build; not a debug build; Android or iOS; `setCrashlyticsCollectionEnabled` not forced false; Firebase init failure (the app swallows it and falls back to the no-op reporter); relaunch the app, since non-fatals upload on the next launch |
| Missing a non-fatal | Throttled (same group key within 10 min, or 4 per session); device buffer holds about eight; look for the `suppressed` breadcrumb |
| Unreadable stacks | Symbols: iOS dSYM phase output, Android mapping, and the `--obfuscate` upload in section 8 |
| `endpoint_unclassified` / `unknown_action` | A service call is missing its `ApiCallLabel`. `test/api_call_label_coverage_test.dart` guards this |
| Everything shows `[redacted]` | Expected until `kSafeServerMessages` is populated (section 7) |

## 11. Out of scope and merge notes

Separate changes:

- Phase 2 UI action context.
- `onGenerateInitialRoutes` to stop the `/` placeholder under `/bootstrap`.
- Production release builds log signed uploads as event, method, full URL, status and duration only; headers, response bodies and exception text are dropped. The full signed URL is retained by decision: it is a bearer credential until it expires. It appears in the app logger only (device logcat/os_log, no remote log shipping) and never in Crashlytics fields, which omit URL, headers and exception text.

Merge note: this branch was cut from local main at 8a2de94, without the uncommitted `receiveTimeout` change in `lib/app/network.dart` and `core_account_service.dart` that exists in the main checkout.
