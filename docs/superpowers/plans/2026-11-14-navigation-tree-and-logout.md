# Navigation Tree and Logout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Logout and session expiry reset to Login exactly once, and every tab switch from a page above the shell shows exactly one transition and never stacks a second shell.

**Architecture:** Keep the named-route `Navigator`, `SectionShell` and `FlowPageState` helpers. Make `AuthFlowListener` the only owner of session-ending resets: `PrivateRouteGate` redirects only a route opened while signed out. Route every tab destination through `selectOpenSection`, which selects the tab without a crossfade when a pop reveals the shell.

**Tech Stack:** Flutter, `Navigator` named routes, Riverpod, `flutter_test`.

**Spec:** No separate spec. The plan implements the 2026-11-14 review in chat, summarized under "Causes found" below: fix the repeated transitions on logout and on child → Account (including Account tier), and apply the fix everywhere the same cause appears.

## Global Constraints

- Keep every route name in `AppRoutes`.
- Tests: barest minimum. One new test (logout leaves only Login, pushed once) and two edits to existing tests. No new harness files, frame-timing assertions or test matrices.
- Do not touch files with unrelated uncommitted edits: `lib/app/services.dart`, `lib/module/core_banking/screens/transfer_identity_panel.dart`, `lib/module/kyc/service/dojah_config.dart`, `test/transfer_identity_widget_test.dart`, `README.md`, `.env.example`.
- Production always starts at `/bootstrap` (no platform deep links; the Android manifest has only `MAIN`/`LAUNCHER`). "Deep link" below means a notification route or a test's initial route.

## Causes found

1. **Logout pushes Login several times.** Every private route is wrapped in `PrivateRouteGate` → `SavingsAccessGate` ([private_route_gate.dart:20-27](../../../lib/module/component/private_route_gate.dart)). Routes below the top stay mounted, so each gate's `ref.listen(authSessionProvider)` ([savings_access_gate.dart:66-73](../../../lib/module/savings/screens/savings_access_gate.dart)) runs `_prepare` on the next frame, finds no session, and calls `pushNamedAndRemoveUntil(login)`. `AuthFlowListener._drain` then performs the published Login `clearStack` too. Home → Account tier → Limits gives four Login pushes. The gates run first, so their pushes carry no message. Session expiry (`SessionExpiryCoordinator.expireOnce`) hits the same race.
2. **Second-reset paths.**
   - `SavingsAccessGate._prepare` clears an expired session itself and calls `onSignedOut`, bypassing `expireOnce` (no `clearPrivateUserState`, no message).
   - Its "Back to login" button redirects while the session is still in memory.
   - `AuthInterceptor.onError` accepts a 401 when `readCurrentSession()` is already null ([interceptors.dart:442-448](../../../lib/app/interceptors.dart)), so a 401 in the window after logout clears memory can publish a second Login.
   - `AuthNavigationNotifier.publish` queues a second `clearStack` behind a first one, so logout and expiry in the same frame reset twice.
3. **Child → tab shows two transitions.** `selectOpenSection` ([route_definitions.dart:320-331](../../../lib/module/app_flow/route_definitions.dart)) pops to the shell and then `_select` crossfades for 200ms. When the child was opened from a different tab, the user sees the pop reveal that tab and then a fade to the new one. Account tier is pushed from Home ([home_screen.dart:167](../../../lib/module/home/screens/home_screen.dart), :261), so Tier → Account shows Home first. The same applies to every child page's tab bar (`goSection` → `replaceWithSection`), the KYC screens' `_goSection`, the Notifications screen's tab bar, and `go(<hub>)` (for example, savings plan deletion's `go(AppRoutes.home)`).
4. **A second shell is stacked.**
   - Account deletion's "Move money out" calls `Navigator.pushNamed(AppRoutes.sendHub)` ([account_control_screens.dart:479](../../../lib/module/account/screens/account_control_screens.dart)), which builds a new shell above the current one.
   - `NotificationNavigator.dispatch` uses `selectOpenSection(dropPages: false)`; with pages above the shell, it pushes a second shell ([notification_navigator.dart:33-43](../../../lib/helper/notification_navigator.dart)).
5. **Notification payloads may name auth routes.** `parse` accepts any registered route, including `/login` and `/bootstrap`, which would push an auth screen above a private stack.

## Decision taken (flip before execution if wrong)

A notification for a hub behaves like a tab tap: it pops to the shell and selects that tab, dropping pages above it. Exception: when a dialog or sheet is on top, it does nothing. Several sheets block Back while sending money (`savings_plan_top_up_sheet.dart:84`, `savings_plan_withdraw_sheet.dart:58`), and `popUntil` ignores `PopScope`. The alternative is keeping the interrupted flow beneath a second shell, which is the current behavior this plan removes.

## Checked and left unchanged

- **Child pushes stay as they are.** Home → Notifications, Home/Account → Account tier, Payments → Add money, Savings → Add money, Tier → Transaction limits → BVN, and Send/Savings child pushes: each is a child push and Back returns to the page beneath.
- **The KYC tier-list return is already correct.** `_returnToTierList` ([kyc_screens.dart:233-243](../../../lib/module/kyc/screens/kyc_screens.dart)) pops to an open tier list, otherwise replaces the step with one.
- **The no-shell fallbacks only run in tests.** `replaceWithSection`'s and `onNothingToPop`'s `pushReplacementNamed(<hub>)` only run when no shell exists. Production always has one after Home.
- **No caller passes arguments to a hub.** `FlowPageState.go(route, arguments: …)` would push a hub, but no call site passes arguments to a hub route.
- **Auth screens and capture flows are already correct.** Auth screens' `AuthBackScope` fallbacks, `confirmSignOut`, account deletion's final `logout()`, the inactivity warning dialog and the KYC/transfer capture `MaterialPageRoute`s already use one owner or are transient.
- **Logout and expiry publish once, as they should.** `LogoutNotifier.logout` and `SessionExpiryCoordinator` each publish exactly one Login intent.

## Review Focus

These are checked on device in Task 4 rather than by new tests, per the Global Constraints:

- Logout or session expiry while a dialog or sheet is open over a nested page: one Login transition, and no dialog left behind.
- Inactivity sign-out while "Are you still there?" is showing over a nested page: one reset, with the inactivity message on Login.
- Home → Account tier → Transaction limits → Account tab: one pop transition straight to Account, and Back then shows Home.
- A hub notification while a savings top-up sheet is sending: nothing happens; the sheet finishes.
- Sign in again right after logout: Home loads once, and no stale gate redirects.

---

### Task 1: One owner for session-ending resets

**Files:**
- Modify: `lib/module/savings/screens/savings_access_gate.dart` (state class, `_prepare`, `build`)
- Modify: `lib/module/component/private_route_gate.dart` (doc comment only)
- Modify: `lib/app/session_expiry_coordinator.dart` (`_expire`)
- Modify: `lib/app/auth_navigation_provider.dart` (`AuthNavigationNotifier.publish`)
- Test: `test/back_stack_test.dart`

**Interfaces:**
- Consumes: `sessionExpiryCoordinatorProvider.expireOnce()`, `logoutProvider.notifier.logout()`, `AuthNavigationMode.clearStack`.
- Produces: `SavingsAccessGate` calls `onSignedOut` only for a route that was never admitted. No public signature changes.

- [ ] **Step 1: Write the failing test** in `test/back_stack_test.dart`.

  Give `openAlone` an optional `bool withAuthListener = false`. When true:
  - wrap the `MaterialApp` in `AuthFlowListener`;
  - add `localNotificationServiceProvider.overrideWithValue(null)` to the overrides (`firebaseReadyProvider` already defaults to false);
  - pass `navigatorObservers: [pushes]`, where `pushes` is a file-private `_Pushes extends NavigatorObserver` that records `route.settings.name` in `didPush` (same shape as the one in `test/notification_tap_flow_test.dart`).

  `navigatorOf` is local to two groups, so this top-level test uses `rootNavigatorKey.currentState!`. `LoginScreen` is in `lib/module/onboarding/screens/login_screens.dart`.

```dart
testWidgets('logout from a nested page resets to Login once', (tester) async {
  await openAlone(tester, AppRoutes.home, withAuthListener: true);
  final navigator = rootNavigatorKey.currentState!;
  navigator.pushNamed(AppRoutes.tierOverview);
  await settle(tester);
  navigator.pushNamed(AppRoutes.transactionLimits);
  await settle(tester);
  pushes.names.clear();

  await container.read(logoutProvider.notifier).logout();
  await settle(tester);

  expect(pushes.names.where((name) => name == AppRoutes.login), hasLength(1));
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(rootNavigatorKey.currentState!.canPop(), isFalse);
});
```

- [ ] **Step 2: Run it and confirm it fails**

  Run: `flutter test test/back_stack_test.dart --plain-name "logout from a nested page"`
  Expected: FAIL. The `hasLength(1)` check finds 4 (three gates plus the listener).

- [ ] **Step 3: Gate redirects only an unadmitted route** in `_SavingsAccessGateState`:
  - Add `bool _admitted = false;` and set it to true where `_prepare` sets `_busy = false`.
  - In `_prepare`, for a non-null expired session: replace `authSessionProvider.notifier.clear()` + `onSignedOut()` with `await ref.read(sessionExpiryCoordinatorProvider).expireOnce();` and return. The coordinator clears private state and publishes Login once.
  - In `_prepare`, for a null session: call `widget.onSignedOut()` only when `!_admitted`. Otherwise return; the session owner's Login intent resets the stack.
  - In `build`: when `_admitted` and the session is null or expired, return a bare `const Scaffold()`. This stops the "Unable to load your account" panel flashing under the Login transition.
  - Change the "Back to login" button to `ref.read(logoutProvider.notifier).logout()`. It must never redirect while a session is in memory.
  - Update `PrivateRouteGate`'s doc comment: it redirects a route opened while signed out or without a PIN, and leaves later sign-outs to `AuthFlowListener`.

- [ ] **Step 4: Expiry is a no-op once signed out.** In `SessionExpiryCoordinator._expire`: if `authSessionProvider` is already null on entry, return without clearing or publishing. Logout or a previous expiry already owns the reset; this closes the late-401 path in `AuthInterceptor.onError`.

- [ ] **Step 5: A clear-stack intent supersedes the queue.** In `AuthNavigationNotifier.publish`: when `mode == AuthNavigationMode.clearStack`, set `state = [intent]` instead of appending. Every earlier queued intent would be wiped by the reset anyway.

- [ ] **Step 6: Run the affected tests**

  Run: `flutter test test/back_stack_test.dart test/private_route_gate_test.dart test/logout_private_state_test.dart test/savings_access_test.dart test/cold_launch_auth_test.dart test/notification_tap_flow_test.dart`
  Expected: all pass. `private_route_gate_test`'s signed-out link still lands on Login, because that route was never admitted.

- [ ] **Step 7: Commit**

```bash
git add lib/module/savings/screens/savings_access_gate.dart lib/module/component/private_route_gate.dart lib/app/session_expiry_coordinator.dart lib/app/auth_navigation_provider.dart test/back_stack_test.dart
git commit -m "fix(auth): reset to Login once on logout and session expiry"
```

### Task 2: One transition for every tab switch

**Files:**
- Modify: `lib/module/app_flow/section_shell.dart` (`_SectionShellState._select`, `build`)
- Modify: `lib/module/app_flow/route_definitions.dart` (`selectOpenSection`)
- Modify: `lib/module/account/screens/account_control_screens.dart:479`

**Interfaces:**
- Consumes: none from Task 1.
- Produces: `void _select(AppSection section, {bool animate = true})` on `_SectionShellState`. `selectOpenSection(AppSection section, {bool dropPages = true})` keeps its signature; Task 3 removes `dropPages`.

- [ ] **Step 1: Instant select in the shell.** Add `bool _instant = false;` to `_SectionShellState`.
  - `_select(section, {animate = true})` sets `_instant = !animate` inside its `setState`.
  - In `build`, the layer duration is `Duration.zero` when animations are disabled or `_instant` is true.
  - When `_instant` is true, add a post-frame callback that sets `_instant = false` without `setState`.

  `_SectionLayer.didUpdateWidget` already hides the outgoing hub immediately for a zero duration, and a later rebuild at 200ms changes no `active` flag, so nothing animates.

- [ ] **Step 2: Select without a fade when a pop reveals the shell.** In `selectOpenSection`, record `final covered = !route.isCurrent;` before `popUntil`, then call `shell._select(section, animate: !covered)`. Tab taps on a hub (`replaceWithSection` → `scope.select`) keep the crossfade.

  This one change covers every caller: child-page tab bars (`goSection`), KYC `_goSection`, the Notifications screen tab bar, `go(<hub>)` and `returnTo(<hub>)`.

- [ ] **Step 3: Account deletion's "Move money out" switches tabs.** At `account_control_screens.dart:479`, replace `Navigator.of(context).pushNamed(AppRoutes.sendHub)` with `goSection(AppSection.send)`.

- [ ] **Step 4: Run the shell tests**

  Run: `flutter test test/back_stack_test.dart test/kyc_tier_return_test.dart`
  Expected: all pass, including "a tab switch cross-fades the body" (an in-shell tab tap still fades) and "a tab from a child page drops the child pages".

- [ ] **Step 5: Commit**

```bash
git add lib/module/app_flow/section_shell.dart lib/module/app_flow/route_definitions.dart lib/module/account/screens/account_control_screens.dart
git commit -m "fix(navigation): switch tabs from child pages in one transition"
```

### Task 3: Notification destinations follow the tab rule

**Files:**
- Modify: `lib/app/app_router.dart` (`AppRoutes`)
- Modify: `lib/helper/notification_navigator.dart` (`parse`, `dispatch`; imports `rootNavigatorKey` from `lib/app/navigators.dart`, already imported)
- Modify: `lib/module/app_flow/route_definitions.dart` (`selectOpenSection`)
- Test: `test/back_stack_test.dart` (rewrite one existing test)
- Test: `test/notification_tap_flow_test.dart` (extend one existing test)

**Interfaces:**
- Consumes: `selectOpenSection` from Task 2.
- Produces: `static const authRoutes = <String>{…}` on `AppRoutes`; `bool selectOpenSection(AppSection section)` (no `dropPages`).

- [ ] **Step 1: Update the existing tests to the chosen behavior.**

  In `test/back_stack_test.dart`, rename "a hub notification keeps the pages open above the shell" to "a hub notification drops the pages above the shell". After the dispatch, assert:

```dart
expect(find.byType(SaveHubScreen), findsOneWidget);
expect(find.byType(NotificationsScreen), findsNothing);
expect(find.byKey(AppBottomNavigation.pillKey), findsOneWidget);
expect(navigatorOf(tester).canPop(), isFalse);
```

  In `test/notification_tap_flow_test.dart` "unknown routes fall back to Notifications", add a second tap `localTap(_tap(AppRoutes.login))`, pump twice, and expect `notificationPushes()` to equal `[AppRoutes.notifications, AppRoutes.notifications]`.

- [ ] **Step 2: Run them and confirm they fail**

  Run: `flutter test test/back_stack_test.dart test/notification_tap_flow_test.dart`
  Expected: the two edited tests FAIL (a second shell is pushed; `/login` is pushed).

- [ ] **Step 3: Add `AppRoutes.authRoutes`.** It holds exactly: `bootstrap`, `onboarding`, `verificationMethod`, `otp`, `createPassword`, `login`, `biometricLogin`, `passwordReset`, `newDeviceOtp` and `createFirstPin`. In `NotificationNavigator.parse`, a route that is unregistered or in `authRoutes` falls back to `AppRoutes.notifications`.

- [ ] **Step 4: A hub notification is a tab tap.** Remove `dropPages` from `selectOpenSection`; it always pops to the shell.

  In `dispatch`, for a hub:
  - find the root navigator's top route with `rootNavigatorKey.currentState?.popUntil((r) { top = r; return true; })` (returns without popping);
  - if `top` is a `PopupRoute`, return without navigating;
  - if `selectOpenSection(section)` returns true, return;
  - otherwise (no shell exists), push the hub as today.

  Update the comment there to match. Non-hub notification routes keep `pushTo`.

- [ ] **Step 5: Run the tests**

  Run: `flutter test test/back_stack_test.dart test/notification_tap_flow_test.dart test/private_route_gate_test.dart`
  Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/app/app_router.dart lib/helper/notification_navigator.dart lib/module/app_flow/route_definitions.dart test/back_stack_test.dart test/notification_tap_flow_test.dart
git commit -m "fix(notifications): open hubs as a tab switch and ignore auth routes"
```

### Task 4: Verify

- [ ] **Step 1:** Run `flutter analyze`. Expected: `No issues found!`
- [ ] **Step 2:** Run `flutter test`. Expected: all tests pass. Investigate any failure in navigation, auth or notification tests before continuing.
- [ ] **Step 3:** Hand Kenechukwu the device check (no device attached here). Run with `flutter run -d 2B161FDH30033N --dart-define-from-file=.env.stage`, and for each action note whether it pushes, pops or resets once:
  - Home → Account tier → Account tab
  - Home → Account tier → Transaction limits → Account tab, then Back
  - Account → Account tier → BVN → Back → Back
  - Account → Delete account → "Move money out"
  - Savings plan → Delete → Home
  - Payments → Add money → Back
  - Notifications page → Save tab
  - Sign out from Account → Security Center
  - Sign out with a sheet open
  - Inactivity sign-out with the warning showing
  - Sign in again after logout
  - A hub notification over a child page and over an open sheet
