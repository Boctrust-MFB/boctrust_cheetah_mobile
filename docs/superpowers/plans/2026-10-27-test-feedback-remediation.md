# Test Feedback Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the seven tester reports with correct transaction and identity states, durable privacy settings, and immediate input feedback.

**Architecture:** Make separate changes in the existing Flutter feature slices. Diagnose the native Dojah failure before selecting a correction. Keep backend and SDK contracts authoritative; add client checks and targeted server contract follow-up where the client alone cannot enforce a rule.

**Tech Stack:** Flutter/Dart, Riverpod, SharedPreferences, Dio, Android/Kotlin Dojah wrapper, Flutter widget/unit tests, physical-device QA.

**Spec:** `docs/superpowers/specs/2026-10-27-test-feedback-remediation.md`

## Global constraints

- Preserve unrelated working-tree changes; this plan only adds documentation.
- Never log raw secrets, identity media, or provider result JSON.
- Do not classify a transfer or KYC attempt as successful from a local callback alone.
- Confirm Core/product contracts before changing SmartSave threshold or bill phone serialization.

## Review focus

- A late Dojah callback after cancellation must not pop another route or crash.
- A failed transfer with only `retrievalReference` must not label it as a receipt reference or omit all support context.
- A 401 from a wrong secret must not clear a valid signed-in session; a genuinely expired token must still clear it.
- A second account on the same device must not inherit the first account's balance visibility choice.
- Pasted airtime/data numbers containing punctuation or excess digits must not reach Review.

---

### Task 1: Diagnose and fix the Dojah Android liveness crash (P0)

**Files:** `lib/module/kyc/screens/dojah_capture_screen.dart`, `lib/module/kyc/service/dojah_platform_route.dart`, `packages/dojah_kyc_sdk_flutter/android/src/main/kotlin/com/dojah/dojah_kyc_sdk_flutter/DojahFlutterSdkPlugin.kt`, relevant KYC tests and `docs/verification/dojah-kyc.md`.

**Observed path:** Android identity uses the native SDK; the wrapper handles launch/result callbacks. SDK `v0.4.2` is pinned. The code does not establish where this process crash occurs.

- [ ] Capture exact app version/build, Android version, device model, Dojah widget/environment, and `adb logcat` crash from scan completion through Proceed. Symbolize the first `FATAL EXCEPTION`/native tombstone; record whether it is in Dojah, the wrapper, or Flutter.
- [ ] Reproduce on the original device and one second Android model; compare a sandbox attempt that crashes with one that completes or cancels. Check recent SDK change history only after the stack points to that boundary.
- [ ] Write a failing regression for any app-owned callback/routing defect. If the stack is inside the closed-source SDK, reproduce against a vendor-approved fixed version or safe route and document the vendor issue; do not guess at a wrapper catch for a process-killing exception.
- [ ] Apply the smallest evidence-backed correction and run KYC unit/widget tests. Complete one physical Android liveness success, cancellation, permission retry, and backend reconciliation check. Check iOS hosted flow for regression.

### Task 2: Preserve an actionable intrabank failure identifier (P1)

**Files:** `lib/module/core_banking/model/core_submission_models.dart`, `lib/module/core_banking/screens/core_transfer_attempt_view.dart`, `test/core_payments_models_test.dart`, `test/core_transfer_requery_ui_test.dart`.

**Observed path:** `CoreTransferAck.displayReference` uses only `reference` or `uniqueIdentifier`; intrabank status can be tracked by `retrievalReference`. The failure copy always says "reference below", but the row renders only when `displayReference != null`.

- [ ] Capture the redacted initiation, finalize, and re-query field names for the ₦1,000 attempt and confirm with support which identifier they can search.
- [ ] Add a failing widget test for failed intrabank acknowledgement with no receipt reference, both with and without a retrieval reference.
- [ ] Render the support-approved identifier under an accurate label (for example, "Tracking ID"), preserving `reference`/`uniqueIdentifier` as receipt references. When no support usable identifier exists, remove the "reference below" instruction and show a truthful support message. Do not derive a receipt reference from the re-query key.
- [ ] Run transfer model/UI tests and a sandbox failure/reversal/unknown-status pass; confirm no duplicate transfer is triggered by re-query.

### Task 3: Wrong secret during biometric setup must remain recoverable (P0)

**Files:** `lib/app/interceptors.dart`, `lib/module/onboarding/service/auth_service.dart`, `lib/module/core_banking/provider/biometric_transfer_provider.dart`, `lib/module/onboarding/provider/biometric_login_provider.dart`, `lib/module/account/screens/account_control_screens.dart`, corresponding interceptor and biometric tests.

**Observed path:** both enrollment flows handle verification failure and can show "incorrect". The User Service `AuthInterceptor` expires the whole session on any authenticated 401, so a verification endpoint returning 401 is a plausible cause of the immediate timeout. This requires a captured status and session event to confirm.

- [ ] Reproduce wrong PIN and wrong password with controlled responses; record HTTP status, whether the session expires, and what the dialog shows. Distinguish wrong-secret 401 from expired-token 401 using the backend contract.
- [ ] Add failing tests showing wrong-secret responses keep the session and dialog active, while an actually expired token still signs out. Cover both PIN and password enrollment.
- [ ] Implement endpoint-specific or response-code-specific handling at the auth boundary only if the backend contract supports it; if both conditions use indistinguishable 401s, coordinate a distinct backend error before bypassing expiry handling.
- [ ] Show inline errors on the entered field, permit retry, and verify that no biometric secret was saved after failure. Re-run biometric and session tests.

### Task 4: Persist per-user balance masking (P0)

**Files:** `lib/module/home/provider/home_provider.dart`, `lib/app/preferences.dart`, Home/balance visibility tests.

**Observed path:** `HomeBalanceHiddenNotifier.build()` returns `false` every new process; recent transactions and other financial views watch the same provider. Per-user preference storage already exists in `account_preferences_provider.dart`.

- [ ] Add tests for force close/restart, logout/login to the same account, different-account isolation, and first-use default.
- [ ] Hydrate/save `homeBalanceHiddenProvider` from a per-user preference key, applying hidden immediately during bootstrap so the balance does not flash visible before hydration. Use the privacy-safe first-use default in the spec unless product decides otherwise.
- [ ] Verify Home, recent transactions, savings, and account history stay masked after app restart and account switching on a device.

### Task 5: Align SmartSave wording and validation timing (P1)

**Files:** `lib/module/savings/screens/savings_plan_screens.dart`, `lib/module/savings/model/savings_plan_models.dart` only if the confirmed rule changes, `test/savings_plans_ui_test.dart`, `test/core_savings_plan_test.dart`.

**Observed path:** `SavingsPlanQuote.acceptsTarget` uses `>` against the quote minimum, with a test that rejects ₦5,000 and accepts ₦5,000.01. The goal-step target field validates syntax but not that rule; the duration step shows the error.

- [ ] Confirm with Core/product whether target must be strictly above the opening deposit for every duration. Record the answer and quote examples.
- [ ] Add failing widget tests for the target step copy, ₦5,000/₦5,000.01, and a duration whose minimum is higher than the catalogue's lowest minimum.
- [ ] If strict `>` is confirmed, state the minimum *target* clearly (for a ₦5,000 opening deposit, more than ₦5,000), prevent progression when the entered amount cannot satisfy the lowest quote, and surface duration-specific errors by the target value with an edit action. If Core confirms `>=`, change model validation, copy, and tests together.
- [ ] Run savings model/widget tests and one sandbox creation attempt at the boundary.

### Task 6: Validate airtime/data mobile numbers before Review (P1)

**Files:** `lib/module/core_banking/screens/bill_payment_screen.dart`, a focused bill number validator in `lib/module/core_banking/model/` or `lib/utils/`, `test/bill_payment_flow_test.dart`.

**Observed path:** the bill field uses a phone keyboard but no formatter; Review enables for any nonempty `customerId`.

- [ ] Confirm the bill payment API's accepted phone form and whether a biller may require a non-mobile customer identifier. Use the spec's 11-digit local format in the UI unless the contract requires another form.
- [ ] Add failing validator/widget tests for 11 valid digits, too short/long, invalid prefix, pasted `* # + / ( )`, and saved beneficiaries. Verify electricity/cable customer IDs remain unaffected.
- [ ] Apply a digits-only formatter and length cap to airtime/data; gate Review on the shared validator and show a field error. Normalize only at API submission if the contract requires it.
- [ ] Run bill tests and try keyboard entry, paste, and a valid sandbox airtime/data Review.

### Task 7: Reject unchanged password and PIN (P1)

**Files:** `lib/module/onboarding/provider/security_action_providers.dart`, `lib/module/account/screens/account_screens.dart`, security provider/dialog tests, User Service change-secret contract.

**Observed path:** the notifiers enforce format/strength but never compare current and new values; the forms validate confirmation only.

- [ ] Add failing tests that equal current/new password and PIN show field errors and make no API call; distinct strong values still submit. Cover whitespace/case behavior according to the existing server contract.
- [ ] Add the comparison in the form and notifier, with clear new-field wording. Preserve strength, confirmation, and biometric enrollment invalidation behavior.
- [ ] Ensure the User Service rejects unchanged secrets independently; if it does not, file/implement the backend change before treating the security rule as fully closed.
- [ ] Run security dialog/provider tests and verify both paths on a sandbox account.

## Final verification and delivery

- [ ] Run `flutter analyze`, `dart format --output=none --set-exit-if-changed lib test`, and the relevant focused `flutter test` suites after each independent change; run the full Flutter test suite before release.
- [ ] Execute the physical-device and sandbox checks named above, document build/device IDs and redacted evidence, and obtain product/Core decisions for SmartSave, phone serialization, and support identifier semantics.
- [ ] Review the seven changes independently; do not close the Dojah or biometric reports on code inspection alone.
