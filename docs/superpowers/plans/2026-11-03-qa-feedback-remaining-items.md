# Remaining QA feedback coding plan

**Goal:** Resolve QA items 2–7 without misreporting transfer outcomes, ending a valid session on a wrong credential, or exposing amounts after an app restart.

**Basis:** [Test feedback remediation design](../specs/2026-10-27-test-feedback-remediation.md) and the current Flutter `main` checkout on 3 November 2026. Item 1 (Dojah) is outside this plan.

**Scope:** Flutter app changes plus explicitly identified Core and User Service contract changes. The backend source and the reported transfer response are not in this checkout. No automated test tasks are included, per request. Each workstream ends with a manual acceptance check using non-sensitive diagnostic evidence.

## Findings and decisions

- **Transfer (#2) is not exclusively a backend defect.** `CoreTransferAck` parses `reference`, `uniqueIdentifier`, and `retrievalReference` separately. `displayReference` uses only the first two. The documented intrabank response permits `reference: null` and describes `retrievalReference` as the re-query key. Thus Core can return a valid tracking identifier without a receipt reference, while the app still promises a missing “reference below.” Core must confirm that the reported finalize response contained a valid `retrievalReference`; the app must correct its conditional copy regardless. Do not invent a receipt reference or substitute one for the re-query key.
- **Wrong credential timeout (#3):** both current-credential verification calls use the default authenticated transport. A User Service HTTP 401 expires the session in `AuthInterceptor.onError` before the enrollment notifier can show “incorrect.” Both notifiers already map `noAuth || statusCode == 401` to “That password/PIN is incorrect.”, so the client currently relies on the very status that ends the session. Confirm whether wrong PIN/password produces 401 or a distinct validation response. Reserve 401 for an invalid/expired bearer session; return a stable wrong-credential code with 400 or 422, or an equivalent contract that lets the client distinguish the two.
- **Balance visibility (#4):** `homeBalanceHiddenProvider` is memory-only and defaults to visible. Persist the choice per signed-in user, following the existing per-user preference notifiers in `account_preferences_provider.dart` (update state, then write). First use defaults to hidden, as proposed in the remediation design.
- **SmartSave target (#5):** `acceptsTarget` currently requires target strictly greater than the duration's opening deposit. The Core docs for `POST /me/savings-plans` only say `targetAmount` “can't be more than the maximum for the tenor”; they state no lower bound relative to the opening deposit. The strict rule is therefore app-imposed. Keep it and ship the field and copy changes now; change the boundary only if product later decides otherwise.
- **Airtime/data (#6):** the payment field has no formatter or validation, and it uses the phone keyboard only when the screen was opened from the Airtime or Data tile, not for an airtime/data biller reached through “More.” The Core docs describe `customerId` as a free-form string with no phone format, and the app sends the typed value today. Validate an eleven-digit local number beginning `0` and keep sending that value unchanged. Revisit the wire format only if Core rejects it. Avoid imposing phone rules on other bill categories.
- **Password/PIN reuse (#7):** the app checks strength but does not compare current and new values. Reject equality in the field and in the submission notifier. The User Service must enforce the same rule for other clients.

## Workstream A — Transfer failure and support identifier (#2)

**Files:** `lib/module/core_banking/screens/core_transfer_attempt_view.dart`, `lib/module/core_banking/screens/core_flow_widgets.dart`, `lib/module/core_banking/model/core_submission_models.dart` if the agreed support identifier requires an explicit accessor, and Core's intrabank finalize/re-query contract outside this repository.

- [ ] Obtain the reported attempt's timestamp, environment, initiation reference and Core correlation ID. Inspect the **redacted** `POST /me/intrabank/transfers/{reference}/finalize` response and any re-query result. Record HTTP status and presence/shape of `retrievalReference`, `reference`, `uniqueIdentifier`, `responseCode`, and `status`; omit account details and credentials.
- [ ] Decide from that evidence whether Core omitted only the optional receipt reference, omitted the required operational tracking identifier, or returned an error response that the app classified incorrectly. If `retrievalReference` is absent or malformed after an accepted finalize, Core must return a stable, support-usable tracking ID and expose a read-only lookup by the initiation reference for lost finalize replies. Keep the outcome unresolved when Core cannot prove failure.
- [ ] Agree with support whether `retrievalReference` may be shown to customers as **Tracking ID**, before coding Task 1; this decides whether the Tracking ID branch ships at all. If yes, expose it under that label when `displayReference` is absent; keep it distinct from **Reference** and retain `retrievalReference` exclusively for intrabank re-query. If support cannot use it, omit the row and provide a support route based on account, date, amount and recipient without suggesting an ID exists.
- [ ] In both result renderers, choose failure copy based on whether an actual support identifier is displayed. When none exists, say to contact support with the transfer details and never say “reference below.” Do not offer an automatic retry where a debit is uncertain.
- [ ] Manually replay a sanitized accepted failure with and without a receipt reference, and a definite rejected finalize. Confirm the displayed status, support wording, and identifier label match the actual response. For the original ₦1,000 case, confirm the backend ledger outcome before telling the customer to retry.

## Workstream B — Biometric enrollment wrong credential (#3)

**Files:** `lib/module/onboarding/service/auth_service.dart`, `lib/app/interceptors.dart` only if the agreed response contract requires a narrowly scoped exception, `lib/module/onboarding/provider/biometric_login_provider.dart`, `lib/module/core_banking/provider/biometric_transfer_provider.dart`, `lib/module/account/screens/account_control_screens.dart`, and User Service verification endpoints outside this repository.

- [ ] Capture the status and stable error code, without credential values, from wrong `POST /auth/password/verify-current` and `POST /auth/pin/verify-current` calls in staging; also check a genuinely expired token. Confirm whether the timeout is the global 401 session-expiry path.
- [ ] Make the backend distinguish wrong current credential from expired bearer token. Prefer 400/422 with a machine-readable `INVALID_CURRENT_PASSWORD` or `INVALID_CURRENT_PIN`; keep 401 for session expiry. If the backend cannot change status, agree a documented, endpoint-specific code before adding a narrowly scoped client exception. Never suppress all 401 responses for these endpoints.
- [ ] Remove the existing `noAuth || statusCode == 401` → “incorrect” mapping from both enrollment notifiers. Map the agreed wrong-credential response to an inline error on the current password/PIN field. Keep the enrollment dialog open, clear the entered secret, and allow another attempt. A real expired session still returns the customer to sign-in.
- [ ] Keep enrollment order: server verifies current credential, device biometric prompt succeeds, then `BiometricLoginStorage` or `BiometricTransferStorage` writes to secure storage. Review the PIN copy so “saved on this device” makes clear this happens **only after** both confirmations; do not claim the PIN is saved at the initial prompt.
- [ ] Manually enter a wrong password and PIN, then a correct one, and separately use an expired session. Confirm the first two show a retryable field error without logout, the last signs out, and no enrollment is enabled after a failed check.

## Workstream C — Persist hidden balances (#4)

**Files:** `lib/app/preferences.dart`, `lib/module/home/provider/home_provider.dart`, and existing Home, savings and transaction views that consume `homeBalanceHiddenProvider` if any bypass its value.

- [ ] Add `homeBalanceHiddenKey(String userId)` under the existing `boctrust.prefs.<userId>` namespace. Make `HomeBalanceHiddenNotifier.build()` watch the session user ID, load that user's stored boolean, and return hidden while signed out or when the key is absent/invalid.
- [ ] Make `toggle()` update state and persist the new value for the current user via `sharedPreferencesProvider`, as `AccessibilityPreferencesNotifier.update` does. Write under the user ID read at toggle time so a sign-out or switch cannot store the value under another user.
- [ ] Audit the Home balance, recent transaction rows and detail sheet, savings totals and history, and account history for use of the same preference. Mask money values before any private screen is shown on cold start; avoid a brief visible flash while the session hydrates.
- [ ] Manually hide, force close, reopen, logout/login as the same user, then switch to a different user. Confirm amounts stay masked for the first user and the second user's choice is independent. Confirm a new installation starts hidden.

## Workstream D — SmartSave target rule and error placement (#5)

**Files:** `lib/module/savings/screens/savings_plan_screens.dart`.

- [ ] Keep the strict `target > quote.minAmount` rule; Core's docs set no lower bound, so this is the app's rule. If product later chooses an inclusive boundary, change the comparison and all related copy together.
- [ ] On the goal step, replace “Minimum opening balance: from ₦5,000” with copy that explicitly says the target must **exceed** the opening deposit and that the exact deposit depends on duration.
- [ ] Validate the entered target against the lowest available opening deposit on the target field so ₦5,000 is rejected there when the minimum is ₦5,000. After duration selection, show the quote-specific error adjacent to an editable target amount on that step; updating it should refresh validity without a blind backtrack. Keep the Next action disabled until both quote and target are valid.
- [ ] Manually check ₦4,999.99, ₦5,000.00, ₦5,000.01 and a duration whose quote has a higher minimum. Confirm the error appears by the amount being edited and the review amount matches the accepted target.

## Workstream E — Airtime/data mobile number (#6)

**Files:** `lib/module/core_banking/screens/bill_payment_screen.dart` and a new `lib/module/core_banking/model/bill_phone_number.dart` validator.

- [ ] For airtime/data billers only (by the screen's existing `_groupOf(biller)`, so billers reached through “More” are included), apply digit-only input with an eleven-digit limit and show an inline “Enter an 11-digit Nigerian mobile number” error for incomplete or invalid numbers. Validate the entire value: eleven digits beginning `0`. Keep Review disabled until the number and amount are valid.
- [ ] Apply the same validation when a saved beneficiary fills the field and immediately before constructing `BillPaymentDraft`, so UI bypasses cannot send symbols or short numbers. A saved number that fails shows the field error; do not convert it between formats. Leave meter, smartcard and other customer IDs unchanged.
- [ ] Manually enter `* # + / ( )`, letters, ten and twelve digits, a valid mobile number, and a saved invalid number. Confirm only the valid number reaches Review and the request carries that same eleven-digit value. If Core rejects it, raise the wire format with Core then.

## Workstream F — Reject unchanged password and PIN (#7)

**Files:** `lib/module/account/screens/account_screens.dart`, `lib/module/onboarding/provider/security_action_providers.dart`, and User Service change endpoints outside this repository.

- [ ] Add a new-value field validator in each dialog that compares exactly with the entered current value and says “Choose a different password” or “Choose a different PIN.” Revalidate the new field when the current field changes; retain existing strength and confirmation rules.
- [ ] Add the same equality guard in `ChangePasswordNotifier.submit` and `ChangePinNotifier.submit` before setting loading or making an HTTP call. Do not log or retain either secret. A rejected unchanged value must leave biometric enrollment intact.
- [ ] Require User Service `change-password` and `change-pin` to reject equality after verifying the current secret, with a stable validation code. This closes the path for other clients and direct API callers.
- [ ] Manually try an unchanged, weak, mismatched-confirmation, and genuinely new secret in each dialog. Confirm only a genuinely new, valid secret is submitted and that the backend refuses an unchanged value sent outside the app.

## File-by-file coding tasks

The workstreams above state the acceptance behavior. The following tasks specify the code changes and their order. Each task can be reviewed and delivered separately. Do not modify the Dojah route. No automated tests are in scope for this plan.

### Task 1 — Transfer result copy and identifier selection

**App files:** `lib/module/core_banking/model/core_submission_models.dart`, `lib/module/core_banking/screens/core_transfer_attempt_view.dart`, `lib/module/core_banking/screens/core_flow_widgets.dart`.

- [ ] Add `({String label, String value})? supportIdentifier(CoreTransferKind kind)` to `CoreTransferAck`. Return `(label: 'Reference', value: displayReference)` if a receipt reference or unique identifier exists. Otherwise return `(label: 'Tracking ID', value: tracking.value)` only when `trackingReference(kind)?.isWellFormed == true`. Otherwise return `null`. The Tracking ID branch is a pre-coding decision, not a runtime check: include it only if support has already agreed (Workstream A); if not, omit it and return only the Reference or `null`. Keep the existing `displayReference` and `trackingReference` semantics unchanged.
- [ ] In `CoreTransferAttemptView`, compute that identifier once in the `AcceptedSubmission` branch. Add its label/value to `details` only when non-null. For `CoreLiveState.failed`, choose one of two exact messages: with an ID, “This transfer did not go through. If your balance changed, contact support with the identifier below.” Without one, “This transfer did not go through. If your balance changed, contact support with the amount, date and recipient.” Do not alter completed, pending, reversed or unknown states.
- [ ] In `CoreSubmissionResult`, retain `ack.displayReference` for bills and other generic submissions. Select its failed message according to whether `displayReference` is present; never promise a row that was not added. This widget has no transfer kind, so do not infer an intrabank re-query key here.
- [ ] Confirm the UI shows the exact identifier available to support and that `Check status` continues to use only `retrievalReference` for intrabank or `transactionReference` for interbank. Keep accepted-but-unconfirmed submissions open.

**Core handoff:** Inspect the reported finalize response. If an accepted intrabank reply lacks `retrievalReference`, amend Core's finalize response and add a lookup by the initiation reference for lost replies. If it contains a valid `retrievalReference` but no receipt reference, that absence is permitted by the current contract; support must confirm the tracking key is searchable. If the transfer actually failed, retrieve the ledger/re-query reason separately. The app cannot derive that reason from a missing receipt ID.

### Task 2 — Credential verification contract and enrollment dialogs

**App files:** `lib/module/onboarding/service/auth_service.dart`, `lib/module/onboarding/provider/biometric_login_provider.dart`, `lib/module/core_banking/provider/biometric_transfer_provider.dart`, `lib/helper/biometric_operation_result.dart`, `lib/module/account/screens/account_control_screens.dart`. Touch `lib/app/interceptors.dart` only if the backend cannot supply the preferred distinct status.

- [ ] Establish the User Service contract first: wrong current password/PIN returns HTTP 400 or 422 with `code: INVALID_CURRENT_PASSWORD` or `INVALID_CURRENT_PIN`; an invalid bearer returns 401. The `ApiService` already preserves `errorCode`, so the normal service calls in `AuthService` require no transport change under this contract.
- [ ] Extend `BiometricOperationResult` with a default-false `credentialRejected` field. In each enrollment notifier's `enable`, delete the existing `verified.noAuth || verified.statusCode == 401` condition (`biometric_login_provider.dart` and `biometric_transfer_provider.dart`, in the `!verified.isDone` branch). Match only the agreed validation `errorCode` to `credentialRejected: true` and the existing “That password/PIN is incorrect.” message. Do not infer wrong credentials from `noAuth` or HTTP 401. A 401 remains a session-expiry/cancellation path; do not turn it into a retryable credential error.
- [ ] In `_showBiometricEnrollmentDialog` and `_showBiometricApprovalDialog`, keep local `String? credentialError` in `StatefulBuilder` state around the existing `Consumer`. After a `credentialRejected` result, clear `_currentSecretController`, set the error, and show `FieldError(credentialError)` immediately below the field. Clear the error on the next edit. Keep the modal open and enabled. Use the current snackbar for biometric capability or storage failures.
- [ ] Change the approval prompt to explain the sequence: “Enter your current 4-digit transaction PIN. After we verify it and you confirm with biometrics, the PIN is saved securely on this device to approve transfers and bill payments.” This keeps the scope the current copy states. The existing secure-storage write must remain after both checks; a wrong credential must not create enrollment.
- [ ] If User Service must keep 401 for a wrong credential, add a **documented code-specific** exception in `AuthInterceptor.onError`, limited to the two verify-current paths and the exact invalid-credential codes. All other 401s still call `expireSessionOnce`. Do not set `suppressSessionExpiry` on every verification request.

### Task 3 — Per-user balance visibility

**App files:** `lib/app/preferences.dart`, `lib/module/home/provider/home_provider.dart`.

- [ ] Add `String homeBalanceHiddenKey(String userId) => 'boctrust.prefs.$userId.balance_hidden';` in `preferences.dart`. Use `SharedPreferences.getBool`, with absent or unreadable values returning `true` (hidden).
- [ ] In `HomeBalanceHiddenNotifier.build`, watch `authSessionProvider.select((session) => session?.userId)`. Return `true` when signed out; for a signed-in user read only that user's key. This makes an account switch rebuild the preference before account amounts render.
- [ ] Mirror `AccessibilityPreferencesNotifier.update`: `toggle()` sets `state = !state`, reads the current user ID, returns if signed out, then awaits `setBool(homeBalanceHiddenKey(userId), state)`. Keep the `void`/`Future<void>` signature so the two existing callers in `home_screen.dart` and `savings_screens.dart` need no change. No in-flight flag, return value or failure snackbar: `shared_preferences` updates its in-memory cache before the platform write, so a rollback would not match what `build()` reads back anyway. Existing consumers of `homeBalanceHiddenProvider` continue to receive a `bool`; do not add a second visibility source.
- [ ] Review the Home transaction row/detail path plus savings and account-history amount rendering for any direct amount that ignores the provider. Mask it with the same `hidden` value before display. Keep the default hidden on first use and after corrupt preference data.

### Task 4 — SmartSave target field and duration quote

**App files:** `lib/module/savings/screens/savings_plan_screens.dart`. `savings_plan_models.dart` is unchanged; `SavingsPlanQuote.acceptsTarget` keeps `kobo > _minKobo` plus its max check.

- [ ] Add one private target-error helper in the wizard that replaces the `_targetProblem` getter. It takes the typed amount and optional `SavingsPlanQuote`. With a quote, use `acceptsTarget` and `exceedsMax` to produce the quote-specific error, dropping the current “Go back to change it.” suffix since the field becomes editable on that step. Without a quote, compare the target's Kobo value against `_product?.lowestMinAmount` and report that the target must exceed the minimum opening deposit. Return null only when the value is valid for the known boundary.
- [ ] Add a SmartSave branch to the `_amountField` validator (it covers only Fixed and Padi today) that returns the helper's error, so the message shows directly below the field. On `_WizardStep.goal`, include the helper in `_stepValid`. Replace the callout title with “Opening deposit starts at ₦X” and explicitly state “Your target must be greater than the opening deposit; the exact deposit depends on duration.” This avoids implying that ₦X is itself a valid target.
- [ ] On `_WizardStep.schedule`, place an editable `_amountField('Target amount')` beside the quoted deposit; its validator shows the helper's quote-specific error immediately below it. Use the existing `_amount` controller and `_draft.copyWith(amount: value)` so the review and create request use the corrected value. Remove the separate far-away `_targetProblem` text from `_quoteSection`; keep the schedule Continue button gated by the quote and target validity.
- [ ] When the duration changes and a new quote arrives, recompute the field error from the current draft amount. Do not clear the amount or permit continuation while the quote is loading. The create request's existing `toCreateRequest(quote)` remains the final guard.

### Task 5 — Airtime/data number validation

**App files:** create `lib/module/core_banking/model/bill_phone_number.dart`; modify `lib/module/core_banking/screens/bill_payment_screen.dart`.

- [ ] Define `bool isValidBillMobileNumber(String number)` in the new file: exactly eleven digits beginning `0`. No wire-format conversion; Core's docs give `customerId` as a free-form string and the app sends the validated value as typed. Keep bill-specific rules separate from signup's `isValidNigerianPhone`.
- [ ] In `_details`, derive `phoneBiller` from the existing `_groupOf(biller)` being `BillerGroup.airtime` or `BillerGroup.data`; it already resolves `BillerGroup.all` through `BillerGroup.of(biller)`. Replace the current `widget.group` keyboard check with it. For a phone biller, use `TextInputType.phone`, `FilteringTextInputFormatter.digitsOnly`, and `LengthLimitingTextInputFormatter(11)`. Other billers keep their current field behavior.
- [ ] Show a field-adjacent error after the user edits an invalid number. Require `isValidBillMobileNumber(customerId)` alongside `amount is ValidMoney` for Review; an empty, short, long, symbol-containing or invalid-prefix value cannot advance. Recheck just before `BillPaymentDraft` construction.
- [ ] When a saved beneficiary fills the field, leave the stored value as is; if it fails `isValidBillMobileNumber`, show the field error. Never strip symbols or convert formats into a different phone number.

### Task 6 — Reject identical new secrets

**App files:** `lib/module/account/screens/account_screens.dart`, `lib/module/onboarding/provider/security_action_providers.dart`. **User Service:** the two change endpoints, outside this checkout.

- [ ] In the password dialog's new-password validator, run the existing strength validator first, then compare the proposed and current strings exactly and return “Choose a different password.” Revalidate the new field when the current field changes. Keep confirmation matching the proposed new password.
- [ ] In the PIN dialog's new-PIN validator, run `validators.strongTransactionPin` first, then compare with `_currentSecretController.text` and return “Choose a different PIN.” Wire `PinInputField.onChanged` for the current PIN so the new-PIN error refreshes. Retain four-digit, strength and confirmation behavior.
- [ ] In `ChangePasswordNotifier.submit` and `ChangePinNotifier.submit`, add equality checks **before** `NotifierState.loading` and before the HTTP call. Return `NotifierState.error` with the same copy. Do not wipe saved biometric credentials on a locally rejected same-value attempt; existing wipe/forget logic remains only after an accepted change.
- [ ] In User Service, verify the supplied current secret, compare the proposed new value with the stored one using the service's existing secret-verification mechanism, then reject reuse with stable `NEW_PASSWORD_SAME_AS_CURRENT` or `NEW_PIN_SAME_AS_CURRENT` validation codes. Do not rely on plaintext storage or a direct hash-string comparison if salts make hashes differ. Preserve strength checks and any existing secret history policy.

## Delivery order and dependencies

1. Ship the local privacy fix (#4), app-side transfer copy fix (#2), SmartSave target field (#5) and airtime/data number validation (#6) first; none waits on a backend decision. For #2, settle the Tracking ID question with support before coding.
2. Agree and implement the User Service wrong-credential contract (#3), then finish the enrollment UI. Preserve genuine expiry behavior.
3. Raise #5's boundary or #6's wire format with product/Core only if Core rejects what the app sends.
4. Add app-side equality guards (#7) and coordinate the User Service enforcement before treating the issue as closed.
5. Close #2 only after the original transfer's backend outcome and identifier availability have been checked; a corrected screen alone does not explain the failed payment.

## Completion record

For each item, record the backend contract decision where applicable, changed files or service deployment, manual device/build and environment, observed result, and any remaining service limitation. Do not include PINs, passwords, full phone numbers, account numbers or raw transfer payloads in the record.
