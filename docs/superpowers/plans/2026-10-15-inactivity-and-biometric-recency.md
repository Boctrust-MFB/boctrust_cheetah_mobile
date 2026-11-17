# Inactivity Timeout and Biometric Recency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Warn a signed-in user after two minutes without interaction, log them out after three minutes, require login after every process restart, and require a password when the app has not been opened for more than six months.

**Architecture:** Put one inactivity controller above `MaterialApp` so all private routes share the same clock. Use the existing session expiry coordinator to clear the session and private data. At cold startup, discard the persisted authenticated session before routing. Store the previous app-open timestamp in secure storage and check it before updating it; if it is older than six calendar months, delete biometric enrollment before biometric UI can hydrate.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_secure_storage`, existing `local_auth` integration, `flutter_test`.

**Spec:** The user request in this chat, plus the existing biometric lifecycle contract in `docs/superpowers/specs/2026-10-03-biometric-login-design.md` (ordinary logout preserves enrollment). This plan's "Behavior decisions" section resolves details the request leaves open.

## Behavior decisions

- Inactivity runs only while an authenticated session exists. Its clock starts when login succeeds or the app enters the foreground with a live session.
- Any pointer or keyboard interaction on a private screen resets the clock. At 2:00 without activity, show one modal warning. While it is open, only its **Stay signed in** button counts as activity and dismisses it, starting a fresh three-minute period. Taps on the barrier and Back do not dismiss it or reset the clock. At 3:00 without activity, hide private content, close the warning, clear the session, and route to login with the message "You were signed out after 3 minutes of inactivity." (not the default session-expired text). Keyboard activity needs its own handler (`HardwareKeyboard` or a root `Focus`); a pointer `Listener` does not see key events. A timer callback must compare elapsed time with a clock; timer delivery alone is not proof that the deadline has passed.
- Background time counts toward inactivity. On foreground return, evaluate the original deadline before accepting the resume event as activity. If elapsed time is 2:00–2:59, show the warning; at 3:00 or later, log out before exposing private content. No grace period.
- A cold process launch always routes a returning user to login, even if the stored access token has not expired. Onboarding still appears for a first-time user. A private deep link cannot restore or reveal the previous session during that launch. Cold-launch login shows no message; a fresh launch is not a session expiry. Ordinary logout, including inactivity and cold-start cleanup, preserves valid biometric enrollment.
- An "app open" means a cold launch or return from `paused` or `hidden`, not a temporary `inactive` state caused by a system biometric prompt. Save the timestamp on every such event, but compare the **previous** valid timestamp with the current UTC time first. Use six calendar months, not 180 days; clamp a missing anniversary day to the last day of that month. At exactly the six-month anniversary, biometrics remain enabled; beyond it, clear enrollment and require a password. Missing, malformed, or future timestamps fail closed for biometric login. **Legacy users (deliberate product choice):** no install has a last-open timestamp before this release, so the first launch after upgrading clears every existing biometric enrollment and asks for a password once. No migration seeds the timestamp, because a seeded value cannot prove the app was opened recently. The login message must say why. After a stale-enrollment clear, a password login does not silently reenroll biometrics; the user must turn them on again in Security Center.
- Treat secure-storage write or delete failures as fail closed for this process: never expose private routes after failed cold-start session cleanup, and never offer biometric sign-in when recency cannot be established or enrollment cleanup fails. Do not log identifiers, passwords, tokens, or raw storage values.

## Global Constraints

- Preserve existing password login, new-device OTP, post-login bootstrap, and biometric enable/disable flows.
- Reuse `SessionExpiryCoordinator.expireOnce()` for inactivity expiry and existing biometric cleanup for stale enrollment. Do not add a new dependency or backend contract.
- Keep the two-minute warning, three-minute expiry, and six-calendar-month cutoff in one named policy location each so tests can use controlled clocks.
- Do not disable idle behavior in debug builds; tests use an injected clock/timer boundary instead.

## Review Focus

- App is backgrounded before the warning and resumed after expiry: Task 2 tests that login wins before private content is visible.
- User dismisses the warning just before expiry: Task 2 tests that acknowledgement resets the entire clock and an old timer cannot log out the new period.
- A valid persisted token and a private deep link exist on cold launch: Task 1 tests that neither can restore a private page, for Home and for routes behind `SavingsAccessGate`.
- Cold-start token deletion fails: Task 1 tests that no request carries the stale stored token.
- The previous open is exactly six calendar months old, or the device clock moves backward: Task 3 tests the boundary and fail-closed case.
- Biometric prompt or login races with recency invalidation: Task 3 tests that a late biometric result cannot establish a session.

## Review findings incorporated

1. `LoginScreen` watches `biometricLoginProvider`, whose `build()` immediately schedules hydration. Task 3 must make that hydration await the cold-launch recency result; a lifecycle hook that starts the check separately does not establish ordering. Recheck eligibility before credential release and cancel any biometric login invalidated on resume.
2. A root pointer listener may see taps on the warning barrier. Task 2 must ignore every pointer and key event while the warning is open except the explicit **Stay signed in** action, and obscure private content while a resume-time expiry is being processed.
3. `BiometricLoginStorage.clearEnrollment()` returns failed keys rather than throwing for every deletion failure. Task 3 must inspect `isComplete`; if cleanup fails, keep the old `lastOpen` value and block biometric use until cleanup succeeds, so a later open cannot make surviving enrollment eligible.
4. `_SessionGate` independently calls `AuthSessionNotifier.hydrate()`. Task 1 must remove that restoration path; a valid stored token or a private deep link must never bypass cold-launch login, including when secure-storage deletion fails.
5. The app may emit `inactive` and `resumed` around a biometric prompt. Count a new app open only after a real `paused` or `hidden` transition, and evaluate the old inactivity deadline before accepting resumed activity.
6. `SavingsAccessGate._prepare(restore: true)` also calls `AuthSessionNotifier.hydrate()`, and `PrivateRouteGate` sends every private route except Home through it. Task 1 must remove that restoration path too; removing only `_SessionGate`'s leaves non-Home deep links open.
7. `AuthInterceptor.onRequest` reads the bearer token from secure storage. If cold-start deletion fails, the in-memory session is null on both reads, so the session-changed check passes and the old token would be attached. Task 1 must attach a token only when `readCurrentSession()` is non-null and its `accessToken` equals the stored token.
8. About 20 existing tests seed a stored session and rely on restoration. Task 1 owns updating them (through one shared test helper that establishes an in-process login) and runs the full suite before committing, so no intermediate commit is red.
9. The last-open key uses the same `IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device)` as biometric enrollment, so it never syncs or migrates when enrollment cannot.
10. A separate persistent "password required" state is needed only when enrollment cleanup failed; after a successful clear there is no enrollment left to block. Task 3 keeps only the failed-cleanup block.

---

### Task 1: Require login on every cold launch

**Files:**
- Modify: `lib/app/bootstrap_provider.dart`
- Modify: `lib/module/onboarding/provider/auth_session_provider.dart`
- Modify: `lib/module/component/private_route_gate.dart`
- Modify: `lib/module/savings/screens/savings_access_gate.dart` (remove the `restore` path)
- Modify: `lib/app/interceptors.dart` (`AuthInterceptor.onRequest` attaches a token only for the current in-memory session)
- Create: a shared test helper that establishes an in-process login (place it beside existing test helpers)
- Modify: existing tests that seed a stored session and rely on restoration (find them with `grep -rln "auth_session\|access_token\|hydrate\|readSessionResult\|startupGate" test`)
- Test: `test/cold_launch_auth_test.dart`

**Interfaces:**
- Produce: `AuthSessionNotifier.clear()` remains the session-only cleanup operation; startup never hydrates a stored session, and a private route accepts only `authSessionProvider` state established by login in the current process. `AuthInterceptor` never sends a stored token that does not match the in-memory session.
- Consume: existing `StartupGateNotifier.start()`, `AuthNavigationProvider`, and private-route checks.

- [ ] **Step 1: Write failing tests.** A returning user's stored valid session routes to login with no message and removes token plus metadata; a first-time user routes to onboarding; a private deep link to Home and to a non-Home private route (through `SavingsAccessGate`) during bootstrap cannot build private content; a failed secure-storage clear still shows login and cannot hydrate the old session; with a stored token left by failed cleanup and no in-memory session, a private request carries no `Authorization` header. An in-process completed login can enter private routes.
- [ ] **Step 2: Run** `flutter test test/cold_launch_auth_test.dart` **and confirm the new cases fail.**
- [ ] **Step 3: Implement the startup gate.** Clear persisted auth session at process start rather than restoring it. Make private-route checks use only current-process `authSessionProvider` state; remove the independent `hydrate()` calls in both `_SessionGate` and `SavingsAccessGate`. In `AuthInterceptor.onRequest`, attach the stored token only when `readCurrentSession()` is non-null and its `accessToken` equals that token. Remove the now-unreachable expired-session message branch in `StartupGateNotifier.start()` and rename or remove `StartupGateStage.hydratingSession` (and `AuthSessionNotifier.hydrate()` if nothing else uses it). Preserve biometric keys. If storage deletion fails, keep in-memory auth empty, block private routes, and route returning users to login.
- [ ] **Step 4: Update existing tests.** Replace stored-session seeding that relied on restoration with the shared in-process login helper. Do not weaken assertions.
- [ ] **Step 5: Run** `flutter test` **(full suite) and confirm pass.**
- [ ] **Step 6: Commit** the cold-launch change and its tests.

### Task 2: Add one app-wide inactivity clock and warning dialog

**Files:**
- Create: `lib/app/inactivity_policy.dart` (deadline calculation and injectable clock)
- Create: `lib/app/inactivity_guard.dart` (interaction/lifecycle observer and warning UI)
- Modify: `lib/app.dart` (mount guard once around the routed app)
- Modify: `lib/app/session_expiry_coordinator.dart` only if needed to close the warning before navigation
- Test: `test/inactivity_policy_test.dart`
- Test: `test/inactivity_guard_test.dart`

**Interfaces:**
- Produce: `InactivityPolicy` with `warningAfter = Duration(minutes: 2)`, `expireAfter = Duration(minutes: 3)`, and an `evaluate(lastActivity, now)` result of `active`, `warning`, or `expired`.
- Consume: `authSessionProvider` to enable tracking; `sessionExpiryCoordinatorProvider.expireOnce(message: ...)` to end a session.

- [ ] **Step 1: Write failing policy tests.** Assert `1:59` is active, `2:00` warns, `2:59` still warns, and `3:00` expires; a new interaction moves both deadlines, while a delayed timer evaluates against the current clock.
- [ ] **Step 2: Run** `flutter test test/inactivity_policy_test.dart` **and confirm failure.**
- [ ] **Step 3: Implement `InactivityPolicy`** as a pure clock/deadline decision, with a clock injectable by the guard and tests.
- [ ] **Step 4: Write failing guard tests.** Exercise pointer and keyboard activity (keyboard through its own handler, not the pointer listener), the inactivity-specific logout message, one warning per idle period, **Stay signed in** reset, barrier and Back events leaving the deadline unchanged, old-timer cancellation, logout once at expiry, background/resume at both thresholds, private content obscured during resume-time expiry, and removal of a warning after other auth expiry or manual logout. Verify that login and onboarding screens never show the warning.
- [ ] **Step 5: Run** `flutter test test/inactivity_guard_test.dart` **and confirm failure.**
- [ ] **Step 6: Implement `InactivityGuard`** at the app root. Listen for global interaction, lifecycle transitions, and session changes; retain the last activity deadline across backgrounding; on resume evaluate it before counting any new activity. While the warning is open, ignore global input except the button's explicit acknowledgement. Show a dialog through the root navigator; obscure private content while expiry runs, close the dialog, and call `expireOnce(message: 'You were signed out after 3 minutes of inactivity.')`. Guard against duplicate timers and navigation races.
- [ ] **Step 7: Run** `flutter test test/inactivity_policy_test.dart test/inactivity_guard_test.dart` **and confirm pass.**
- [ ] **Step 8: Commit** the inactivity change and its tests.

### Task 3: Enforce six-month biometric recency before updating last-open time

**Files:**
- Modify: `lib/helper/secure_storage.dart` (separate versioned last-open key, written with the same `_biometricAppleOptions` as enrollment so it never syncs or migrates)
- Create: `lib/helper/app_open_recency.dart` (read, compare, invalidate, then write)
- Modify: `lib/app/auth_flow_listener.dart` (cold-launch and foreground-open hook)
- Modify: `lib/module/onboarding/provider/biometric_login_provider.dart` (recency gate before hydration and again before credential release)
- Modify: `lib/helper/biometric_login_storage.dart` only if cleanup needs a stricter result contract
- Test: `test/app_open_recency_test.dart`
- Test: `test/biometric_recency_integration_test.dart`

**Interfaces:**
- Produce: `AppOpenRecency.recordOpen(DateTime nowUtc) -> Future<AppOpenRecencyResult>` reporting `eligible` or `passwordRequired`; it serializes concurrent open events and checks complete enrollment deletion before advancing `lastOpen`. After a successful clear there is no enrollment, so no extra state is kept; only a failed cleanup keeps biometric use blocked (in this process and on later opens) until cleanup succeeds.
- Consume: `BiometricLoginStorage.clearEnrollment()` and `BiometricLoginNotifier.cancelActiveOperation()`; no access to the saved password is needed for the recency check.

- [ ] **Step 1: Write failing recency tests.** First open records a timestamp; legacy enrollment with no prior timestamp is cleared and requires a password (the upgrade case); subsequent foreground opens update it; `inactive`/`resumed` around a biometric prompt does not count as another open; five months and exactly six calendar months remain eligible, including a month-end anniversary; one instant beyond the six-month anniversary clears enrollment; missing, malformed, future, or unreadable timestamps prevent biometric use; failed deletion leaves the prior timestamp in place and biometric UI disabled on this and the next open.
- [ ] **Step 2: Run** `flutter test test/app_open_recency_test.dart` **and confirm failure.**
- [ ] **Step 3: Implement secure last-open storage and `AppOpenRecency`.** Read previous UTC timestamp, evaluate it, call `clearEnrollment()` for stale or invalid recency, and inspect `BiometricCleanupResult.isComplete`. If cleanup fails, retain the previous timestamp and block biometric use until cleanup succeeds; do not let a subsequent open bypass the failure. If it succeeds, record the new timestamp; with no enrollment left, the normal disabled state applies and only an explicit Security Center enable restores biometrics. Write the key with `_biometricAppleOptions`. Serialize launch/resume calls. Keep the timestamp across ordinary logout; delete it only with full account/device data removal if that flow already deletes biometric enrollment.
- [ ] **Step 4: Write failing integration tests.** Login cannot hydrate remembered enrollment before the cold-launch recency check completes; a stale app open hides biometric sign-in and allows password sign-in; prompt completion after invalidation cannot submit a saved credential or establish a session; a valid recent open retains biometric login; password success does not automatically reenable cleared enrollment.
- [ ] **Step 5: Run** `flutter test test/biometric_recency_integration_test.dart` **and confirm failure.**
- [ ] **Step 6: Hook recency to cold launch and each return from `paused` or `hidden`.** Make `BiometricLoginNotifier.hydrate()` await the recency check rather than racing a separate lifecycle hook. Recheck immediately before biometric credential release; cancel the pending biometric and login-flow attempts when the result is `passwordRequired`, so a late result cannot establish a session. Present password login with a short message explaining why biometrics must be enabled again; the same message covers the one-time legacy upgrade clear.
- [ ] **Step 7: Run** `flutter test test/app_open_recency_test.dart test/biometric_recency_integration_test.dart test/biometric_login_storage_test.dart` **and confirm pass.**
- [ ] **Step 8: Commit** the recency change and its tests.

### Task 4: Verify complete auth and lifecycle behavior

**Files:**
- Modify: affected tests only where the new cold-launch contract changes old expectations
- Record results in the delivery summary; no extra implementation file is required.

**Interfaces:**
- Consume: Tasks 1–3 as integrated.

- [ ] **Step 1: Run** `flutter analyze` **and resolve findings introduced by these changes.**
- [ ] **Step 2: Run** `flutter test` **and resolve regressions introduced by these changes.**
- [ ] **Step 3: On Android and iOS, manually verify:** 2:00 warning, **Stay signed in** reset, 3:00 logout, background expiry, force-kill/reopen to login, recent biometric login, stale biometric password fallback, upgrade from the previous build with biometrics enabled (one-time password prompt with explanation), and first-time onboarding. Use a controlled test clock/build hook for the six-month case rather than changing a real device clock.
- [ ] **Step 4: Record platform/build results and any remaining limitation before claiming completion.**
