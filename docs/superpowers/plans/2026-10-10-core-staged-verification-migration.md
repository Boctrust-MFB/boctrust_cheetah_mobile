# Core Staged Verification Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task. Checkboxes track execution; saving this plan does not enable a capability.

**Goal:** Move BOCTRUST transfers, interbank transfers, and transaction-limit edits onto Core's PIN-verify → conditional OTP-verify → bodyless-finalize contract, with their UI and result handling wired end to end.

**Architecture:** Migrate the existing single transfer-attempt provider and its two Send entry points in place. Add a separate limit-edit attempt beside the existing read-only limits provider. Share only the credential-entry widgets and a small check-progress response model; each service owns its route family and each capability remains independently gated.

**Tech Stack:** Flutter, Dart, Riverpod, Dio, Core `ApiService`, existing widget and HTTP-adapter test harness.

**Spec:** [Live Core Swagger](https://core-dev-api.centurysoftware.dev/api/v1/docs/) inspected 10 October 2026 (swagger-ui-init SHA-256 `4c143b37…`) — the single source of truth for every route, body, status code and field; where this plan or earlier notes disagree with it, the Swagger wins; [previous staged-transfer plan](2026-10-10-staged-customer-transfers.md), [Core expansion plan](2026-10-10-core-history-statements-freeze.md), and [staging notes](../../verification/2026-10-10-staged-transfers.md). This plan supersedes those plans' transfer/limit verification sequence. Paths below are relative to `/api/v1`.

## Global constraints

- Intrabank and interbank initiate send a **digit-only integer-Kobo string**. Keep the reviewed `amountKobo`, the ₦25,000,000 client ceiling, and the exact recipient/name lookup behavior. Do not change the unrelated account-history, savings, statement, or freeze flows.
- `POST /{reference}/pin/verify` takes `{transactionPin}` and dispatches an OTP when one is required. `POST /{reference}/otp/verify` takes `{otpCode}`. The customer's PIN and OTP do **not** go to finalize. Finalize has the path reference and **no request body**.
- The PIN-verify and OTP-resend responses can include `otpCode` in development/staging. Never display, retain, persist, or use that value on the mobile; obtain the code from the customer.
- **Logging (product decision, 10 October):** transfer and limit requests and replies are logged **in full** on staging — initiate, PIN verify, OTP resend, OTP verify, finalize, status and requery carry no `privacySensitivePathKey`. The logger's built-in rules still mask `transactionPin`; the customer's `otpCode` and the staging `otpCode` will appear in staging logs. The only exception is the existing interbank name enquiry, which stays redacted because Core can return the recipient's BVN. Production keeps the logger's key-based redaction. Leave logger redaction lists unchanged.
- Implement `pin` and `otp` only. The new transfer `/liveness/verify` routes are documented but **out of scope** under the earlier product decision. If `requiredChecks` includes `liveness` or an unknown check, stop before PIN/finalize and leave the attempt unavailable.
- One reviewed attempt is reserved across BOCTRUST and interbank entry points. Do not automatically retry initiate, check, resend, or finalize POSTs. No duplicate finalize after timeout, 409, navigation, restart, or repeated taps.
- A 200 finalize means the request was accepted, not necessarily settled. Intrabank `retrievalReference` and interbank `transactionReference` are final tracking identifiers; neither is interchangeable with the pending initiation `reference`. Preserve a confirmed status when later requery fails.
- Maintain separate staging-only capabilities for BOCTRUST, interbank, and limit **editing**. The existing limits **view** remains independent. Do not expose the new write action until its amount unit and recovery behavior are verified.
- Preserve unrelated working-tree changes. `docs/` is ignored by Git in this checkout; any eventual plan commit needs an explicit `git add -f` of the intended document only.

## Live endpoint contract and mobile data

| Flow | Route after initiate | Request | 200 data / mobile action |
|---|---|---|---|
| BOCTRUST | `POST /me/intrabank/transfers/{reference}/pin/verify` | `{transactionPin: "1234"}` | `reference`, `requiredChecks`, `completedChecks`, `pendingChecks`, `otpSent`, `otpExpiresAt`; OTP is dispatched when required. |
| BOCTRUST | `POST .../{reference}/otp/resend` | No body; only after PIN verified and OTP required | `otpSent`, `otpExpiresAt`; explicit customer action only. |
| BOCTRUST | `POST .../{reference}/otp/verify` | `{otpCode: "123456"}` | Check progress. Then finalize only if the required supported checks are complete. |
| BOCTRUST | `POST .../{reference}/finalize` | No body | Accepted response with `retrievalReference`; continue live requery. |
| Other bank | Same four routes under `/me/interbank/transfers` | Same bodies/ordering | Finalize returns `transactionReference` and status; use status/requery. |
| Limits | `POST /me/transaction-limits/initiate` | Nonempty subset of `singleTransferLimit`, `singleBillPaymentLimit`, `dailyTransferLimit` | `reference`, `requiredChecks`, `expiresAt`. |
| Limits | `POST .../{reference}/pin/verify`, `/otp/resend`, `/otp/verify`, `/finalize` | PIN body, no resend body, OTP body, no finalize body | PIN + OTP are required by the route description; finalize returns updated limit values. Refetch GET afterward. |

The old `/otp/request` path is absent from all three route families. Transfer `/liveness/verify` has no body and is deliberately not called. The Swagger example lists a check in both `completedChecks` and `pendingChecks`; do not infer a real transition from that generated example. Capture sanitized staging replies to establish how those arrays change, and treat contradictory or unknown values as a stopped attempt.

### UI paths

| Checks / action | Customer-visible sequence |
|---|---|
| Transfer, `['pin']` | Recipient and amount review → initiate → PIN sheet → PIN verify → finalizing state → bodyless finalize → accepted/pending result → requery. |
| Transfer, `['pin','otp']` | Review → initiate → PIN sheet → PIN verify (Core sends OTP) → OTP sheet → OTP verify → bodyless finalize → result. Offer **Resend code** on the OTP sheet only after PIN verification, with in-flight suppression and no automatic resend. |
| Transfer, liveness/unknown | Review → initiate → unavailable explanation; no check or finalize call. |
| Limit edit | Current effective and tier-ceiling values → edit only chosen fields → review changed values → initiate → PIN verify (sends OTP) → OTP verify, with optional explicit resend → bodyless finalize → refetch GET → updated values or an unresolved-state explanation. |

## Current component audit

| Available | Required migration |
|---|---|
| `CoreApiEndpoints` and capability operations still reference `/otp/request`. `CoreTransferService.requestTransferOtp` calls it; `finalizeTransfer` sends PIN/OTP in its body. | Replace paths, request contracts, and capability requirements together. Keep `moneyMoving` on transfer finalize only. |
| `CoreTransferAttemptNotifier` has `initiating`, `awaitingChecks`, `finalizing`, `settled`; `authorizeStagedTransfer` holds PIN while the OTP sheet requests a code and later passes both to finalize. | Add verification phases and server-confirmed check progress. PIN verify sends OTP, so the OTP sheet no longer requests one on open or returns a raw code to finalize. |
| `TransactionPinSheet` has a transfer-specific **Confirm transfer** button; `TransferOtpSheet` sends on open and returns six digits. | Make the PIN CTA configurable for transfer/limit verification; make the OTP sheet verify and optionally resend in place, clearing input on exit. |
| Transfer result mapping calls every interbank 500 a definite recipient failure. | Treat interbank finalize 500/timeouts as uncertain; map documented 422 bank decline to definite failure. A finalize 409 may mean already processing, so never label it safely retryable. |
| `kTransferAuthorizationEvidenceReady` (`lib/app/feature_capability.dart`) documents the PIN and OTP in the finalize body. | Rewrite the note for the Swagger contract: credentials go only to `pin/verify` and `otp/verify`; finalize carries none. The gate itself stays staging-only. |
| `TransactionLimitsScreen` is read-only, `CoreTransactionLimitService` only has GET, and `FeatureCapability.limitIncrease` is unregistered. | Add a separate edit capability, draft/provider/service, and a conditional **Change limits** entry on the existing screen. Keep GET view available when edit is gated. |

## Review focus

- A PIN-verify 200 that reports no OTP requirement must never open the OTP sheet; a response that says an OTP is pending must never finalize early. Task 3 tests both.
- Wrong PIN or OTP must keep the same unexpired initiation, show the error on the appropriate sheet, and never create a second initiation. Tasks 3–4 test this.
- A late check reply after sign-out, account change, cancellation or a different attempt must not advance the next customer's flow. Tasks 3 and 6 test this.
- Interbank 500, ambiguous finalize 409, and timeout after finalize must never show “no money left” or start a blind retry. Task 5 tests this.
- A 409 "already completed" on PIN or OTP verify must advance to the next step and finalize exactly once. Task 3 tests this.
- A limit edit with no changed fields, an unconfirmed amount unit, or values above the Core tier ceiling must send no initiate request. Tasks 6–7 test this.

---

### Task 1: Replace route definitions and capability contracts

**Files:** Modify `lib/app/core_api_endpoints.dart`, `lib/app/feature_capability.dart`; test `test/feature_capability_test.dart`, `test/core_transfer_staged_service_test.dart`.

**Interfaces:** Add encoded `intrabankTransferPinVerify(reference)`, `intrabankTransferOtpResend(reference)`, `intrabankTransferOtpVerify(reference)` and matching interbank builders and literal templates. Add limit initiate/PIN/resend/OTP/finalize builders and templates. Delete the two old transfer `/otp/request` builders/templates and their uses once consumers migrate.

- [ ] Write path tests for an encoded reference and capability tests asserting each transfer's actual route family, no `/otp/request`, separate limit view/edit, and `moneyMoving` containing only transfer finalizes among these routes. Run the focused tests and observe the expected failures.
- [ ] Add the builders/templates and replace the capability operation sets. Use `FeatureCapability.transactionLimitsEdit` for the write flow (rename the unused `limitIncrease` value after checking all call sites). Its required operations include GET plus limit initiate, PIN verify, OTP resend, OTP verify, and finalize. Leave `transactionLimitsView` on GET only. Keep `transferAuthorizationReadyProvider` as the existing transfer authorization gate and test it against the revised operations.
- [ ] Rerun the focused tests until green. Confirm a missing staged write route cannot make the view capability unavailable.

### Task 2: Implement PIN, OTP, resend, and bodyless-finalize transport

**Files:** Create `lib/module/core_banking/model/core_check_progress.dart`; modify `lib/module/core_banking/service/core_transfer_service.dart`, `lib/module/core_banking/service/transaction_authorizer.dart`, `lib/module/core_banking/model/core_transfer_initiation.dart`, `lib/module/core_banking/model/core_submission_models.dart`; test `test/core_transfer_staged_service_test.dart`, `test/core_transfer_initiation_test.dart`, `test/core_payments_models_test.dart`.

**Interfaces:** `verifyTransferPin(CoreTransferKind kind, CoreTransferInitiation initiation, String pin)`, `resendTransferOtp(kind, initiation)`, `verifyTransferOtp(kind, initiation, String otp)`, `finalizeTransfer(kind, initiation)`; all return typed response/status without storing credentials. `CoreCheckProgress.fromJson(Object?)` parses safe check names and `otpSent`/`otpExpiresAt` as present; deliberately drops staging-only `otpCode`.

- [ ] Write failing adapter tests for exact PIN/OTP JSON, no-body resend/finalize, encoded paths, full logging (no `privacySensitivePathKey`) on every transfer route except the name enquiry, and no automatic retry. Assert that a response containing `otpCode: "123456"` cannot appear in model props or error copy.
- [ ] Implement the new service calls and progress parser. Reject unexpected checks, mismatched references, or expired initiations locally; do not send the liveness route. Update the stale `TransactionAuthorizer` comment and the `kTransferAuthorizationEvidenceReady` note: check-specific verification requests carry credentials, while finalize carries none. Treat HTTP 200 for a step as that step's acknowledgment, then use the real staging progress shape to refine `completedChecks`/`pendingChecks` validation before release.
- [ ] Run the service/model tests. Keep the current integer-Kobo initiate bodies and existing name-enquiry/status/requery service behavior intact.

### Task 3: Migrate the one-transfer attempt state machine

**Files:** Modify `lib/module/core_banking/provider/core_transfer_attempt_provider.dart`; test `test/core_transfer_attempt_provider_test.dart`.

**Interfaces:** Replace `requestOtp(id)` and credential-taking `finalize(id, ...)` with `verifyPin(id, pin)`, `resendOtp(id)`, `verifyOtp(id, otp)`, and `finalize(id)`. Add phases for verifying PIN, awaiting OTP, verifying OTP, ready to finalize, and finalizing; hold initiation/progress, never PIN or OTP.

- [ ] Write failing transition tests for PIN-only and PIN+OTP paths, explicit resend only after verified PIN, and no finalize before every required supported check. Test duplicate taps, expiry, wrong PIN, wrong/expired OTP, a 409 “already completed” check reply, and unexpected liveness.
- [ ] Implement the transitions against Task 2. A wrong PIN/OTP 401 stays on its own sheet while the initiation is valid. A check timeout stops automatic progress; do not convert it into success or repeat it silently. Keep generation and attempt-ID guards for late replies.
- [ ] **Already-completed checks:** the Swagger documents a 409 on `pin/verify` and `otp/verify` as "This step has already been completed for this initiation". Treat it as that step's success and move to the next step: after PIN, the OTP sheet if OTP is required, otherwise ready to finalize; after OTP, ready to finalize. Only finalize's 409 is ambiguous. Test both: a PIN-verify 409 on a PIN-only initiation reaches finalize, and an OTP-verify 409 reaches finalize, each with exactly one finalize POST.
- [ ] **Ready to finalize:** decide from the step results the Swagger documents, not from the generated `completedChecks`/`pendingChecks` example. PIN-only: `pin/verify` 200 or 409. PIN+OTP: `otp/verify` 200 or 409. If a reply's `pendingChecks` still lists a supported check after its step succeeded, or lists `liveness`/an unknown check, stop the attempt instead of finalizing. Test a contradictory reply.
- [ ] Run provider tests, including sign-out, cancellation before finalize, account switch, and a late response for a previous attempt. Preserve the existing unresolved-attempt and requery invariants.

### Task 4: Wire transfer PIN and OTP UI

**Files:** Modify `lib/module/core_banking/screens/core_transfer_attempt_view.dart`, `transaction_pin_sheet.dart`, `transfer_otp_sheet.dart`; touch `interbank_transfer_screen.dart` only where the existing Send entry needs changed state/copy. Test `test/core_transfer_pin_ui_test.dart`, `test/transaction_pin_sheet_test.dart` and a focused OTP widget test.

**Interfaces:** PIN sheet accepts a button label such as **Verify PIN** and returns one ephemeral string. OTP sheet receives `verifyCode(String) -> Future<String?>` and `resendCode() -> Future<String?>` callbacks; it returns a verified result rather than the raw OTP. The callbacks pass credentials directly to Task 3 methods.

- [ ] Write failing widget tests: PIN-only has no OTP UI; PIN+OTP shows a sent-code message after PIN verification, verifies code before finalization, and offers explicit resend after that initial send, with concurrent requests suppressed. Check loading/disabled controls, errors, expiry, cancel/back, background return, and accessibility announcements.
- [ ] Replace the current `requestCode`-on-open behavior. Do not show the staging `otpCode` response. Clear both text controllers on close/dispose, keep PIN/OTP out of routes/provider/models, and avoid a transfer-specific CTA on the limit flow.
- [ ] Run focused widget tests for both BOCTRUST and interbank Send entry points, including a recipient edit while a lookup is in flight. Confirm the existing exact-name preselection and 10-digit lookup remain intact.

### Task 5: Correct transfer outcomes and recovery copy

**Files:** Modify `lib/module/core_banking/model/core_submission_models.dart`, `lib/module/core_banking/screens/core_transfer_attempt_view.dart`; test `test/core_payments_models_test.dart`, and create `test/core_transfer_requery_ui_test.dart` for result/recovery widgets.

**Interfaces:** `mapCoreTransferSubmission` remains the outcome boundary; extend its classification for 422 bank-declined, interbank 500 unknown, and 409 possible in-progress/duplicate. Keep `CoreTransferAck` tracking identifiers distinct from initiation reference.

- [ ] Write failing tests for 422 → definite decline with safe server reason, interbank 500/timeout → unknown, 409 → no retry and no definite “nothing moved” claim, 200 → accepted/pending until status confirms finality.
- [ ] Change mapping and result copy. An unknown finalize with no final tracking reference stays unresolved; use interbank status only if staging proves it accepts the pending initiation reference. Otherwise show a balance/support path and require a backend recovery route before that flow is release-ready.
- [ ] Run outcome and result-widget tests. Test that a later failed requery never erases an already confirmed final status.

### Task 6: Add typed transaction-limit update transport and state

**Files:** Create `lib/module/account/model/transaction_limit_update_models.dart`, `lib/module/account/provider/transaction_limit_update_provider.dart`; modify `lib/module/account/service/core_transaction_limit_service.dart`, `lib/app/private_user_state.dart`; test new `test/transaction_limit_update_service_test.dart`, `test/transaction_limit_update_provider_test.dart`.

**Interfaces:** Draft holds only changed `singleTransferLimit`, `singleBillPaymentLimit`, `dailyTransferLimit`; service exposes `initiateLimitUpdate(draft)`, `verifyLimitPin(reference, pin)`, `resendLimitOtp(reference)`, `verifyLimitOtp(reference, otp)`, `finalizeLimitUpdate(reference)`. Reuse Task 2's safe check-progress model, not transfer attempt state. Parse finalize as a distinct typed update acknowledgment, then GET refreshes the `TransactionLimits` view; do not assume its response has the GET shape.

- [ ] Write failing request tests for a nonempty subset of changed fields, a path-encoded reference, PIN and OTP in their respective verify requests, no-body resend/finalize, full logging (no `privacySensitivePathKey`), and no POST retry. Add 400 tier-ceiling, 403 Tier-0, 401 credential, 409 in-progress, and timeout cases.
- [ ] Implement a session-scoped single limit-edit attempt with expiry and late-reply guards. PIN and OTP remain in widget-local input only. Clear the attempt on logout/account change through `clearPrivateUserState`. Limit editing moves no money: gate it on `transactionLimitsEdit` only, never on `transferAuthorizationReadyProvider`.
- [ ] Run the focused tests. **Do not choose the limit-input unit by analogy:** Swagger calls them strings but does not state Kobo or naira; it documents only the GET tier ceilings as Kobo. The existing read-only screen already reads custom and effective values as Kobo (an earlier ruling), so the same staging test must confirm the accepted input unit **and** the GET custom/effective unit before the edit capability can be available.

### Task 7: Add limit editing to the existing limits screen

**Files:** Modify `lib/module/account/screens/transaction_limits_screen.dart`; optionally extract `transaction_limit_edit_sheet.dart` for the form/review; reuse the Task 4 credential sheets. Test `test/transaction_limits_test.dart` and new limit-edit widget tests.

**Interfaces:** A **Change limits** action appears only under `transactionLimitsEdit`; `transactionLimitsView` continues to show effective values even when editing is gated. The edit form accepts the three current values in naira-display form, shows each tier ceiling, and submits only fields the customer changed after exact unit conversion is confirmed.

- [ ] Write failing widget tests for view/edit capability separation, Tier-0/Core-tier-lag error states, unchanged fields, a value over its tier ceiling, review confirmation, PIN → OTP order, resend, error recovery, and disabled duplicate submission.
- [ ] Add edit/review/verify/success UI. The PIN sheet says **Verify PIN**; the OTP sheet verifies the code. On finalize 200, refetch `GET /me/transaction-limits` before showing updated limits. On an uncertain finalize, do not claim success or retry blindly; show the returned GET values and an unresolved explanation.
- [ ] Run focused widgets and accessibility tests; verify that leaving/re-entering the screen does not lose an unresolved attempt or expose credentials.

### Task 8: Staging verification and release gates

**Files:** Modify `lib/app/feature_capability.dart` and tests as needed; record sanitized evidence in `docs/verification/2026-10-10-core-staged-check-migration.md`.

- [ ] Run `flutter test --no-pub` on the focused service, provider, widget, and capability tests; run `flutter analyze`; then run the full `flutter test --no-pub` suite. Identify any existing unrelated failures by test name rather than silently ignoring them.
- [ ] On staging, verify real PIN-only and PIN+OTP transfer responses, automatic OTP dispatch after PIN verify, explicit resend, wrong/expired code, `completedChecks`/`pendingChecks` consistency, and bodyless finalize. Confirm a ₦10.00 transfer debits exactly ₦10.00 on **both** routes.
- [ ] Test final 200/409/422/500 behavior and a lost finalize reply. The Swagger's interbank status 404 reads "No transfer with that reference belongs to the caller" without naming which reference; record whether interbank status can use the initiation reference and how BOCTRUST recovers without `retrievalReference`; keep the affected transfer capability gated if recovery cannot be established. Use sanctioned staging test accounts and amounts for money-moving verification.
- [ ] Establish the exact limit-write unit with a sanctioned staging test; confirm a successful final GET reflects the intended three values, and test a lost finalize response. Keep `transactionLimitsEdit` gated if units or recovery remain unclear. `transactionLimitsView` stays available.
- [ ] Verify the two transfer capabilities and limit edit cannot unlock each other, no obsolete route is called, no liveness route is called, and no PIN, OTP or staging `otpCode` is persisted or shown in the UI. Staging logs carry these requests in full by decision; confirm the PIN is still masked there and that production builds redact by key as before. Record production/staging release state separately.

## Suggested order

Complete Tasks 1–5 as the transfer migration, then Tasks 6–7 as the limit-edit slice. Task 8 independently gates BOCTRUST, interbank, and limits. The present app sends to removed routes, so keep transfer capabilities staging-only while Tasks 1–5 are incomplete. Reinspect live Swagger immediately before coding and again before staging verification, comparing its swagger-ui-init SHA-256 with `4c143b37…`; treat any change as a plan correction before enabling money-moving calls.
