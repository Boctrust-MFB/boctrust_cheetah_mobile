# Staged Customer Transfers Implementation Plan

> **Superseded for transfer verification and finalize:** Core replaced the OTP-request and credential-carrying finalize sequence. Follow [the current staged verification migration plan](2026-10-10-core-staged-verification-migration.md) for transfer and transaction-limit implementation. The endpoint table below records the earlier contract and must not be used for new integration work.

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task. Checkboxes track execution. This is a plan; saving it does not activate transfer routes.

**Goal:** Wire the documented BOCTRUST and other-bank customer transfer flows from the Send UI through initiate, conditional checks, finalize, and status/requery, with safe handling of uncertain outcomes.

**Architecture:** Reuse the Core API client, existing recipient and amount drafts, the shared transfer attempt provider, and result UI. Add typed initiation and finalization contracts and a state machine that separates a pending initiation reference from BankOne's final tracking reference. Release BOCTRUST and interbank behind separate staging capability gates after their own security and recovery contracts are verified.

**Tech Stack:** Flutter, Dart, Riverpod, Dio, existing Core transport and test harness.

**Spec:** [Core API Swagger reference](https://core-dev-api.centurysoftware.dev/api/v1/docs/#/) as reviewed 10 October 2026; the transfer section of [the broader Core plan](2026-10-10-core-history-statements-freeze.md). This plan supersedes that document's generic Task 10 for BOCTRUST and interbank transfers only. It does not cover internal-service transfers, own-account moves, savings-plan funding/liquidation, transaction limits, history, statements, or freeze.

## Global constraints

- Core paths below are relative to `/api/v1` and use `coreApiServiceProvider`. The customer's source BocFlex account is derived server-side; the mobile request supplies only the documented destination, amount, and optional narration.
- The drafts hold integer Kobo. BOCTRUST `/me/intrabank/transfers/initiate` requires a digit-only Kobo `amount`: a decimal naira value such as `1650.00` fails validation, so ₦1,650.00 is sent as `165000`. Interbank initiate remains a plain naira decimal string under the prior product decision; verify its accepted unit and actual debit in staging. Enforce the documented ₦25,000,000 single-transfer ceiling as a client precheck, while treating the server's own cap/limit response as authoritative.
- Keep BOCTRUST and interbank capabilities independent and staging-only until their route, authorization, response, and recovery evidence passes. Do not call the undocumented old single-step customer submission paths.
- A transfer initiation is not a payment. A finalize response is an acknowledgment; show success only when a documented final outcome or a subsequent authoritative status/requery confirms it. Preserve an earlier confirmed final status if a later check fails.
- Keep PIN and OTP out of Riverpod state, model props, logs, route arguments, analytics, disk, and retry queues. For a PIN+OTP transfer, hold the PIN only in the active authorization UI while the OTP page is open; pass both values to one finalize call, then clear them. Use the existing `LoggingInterceptor.privacySensitivePathKey` request extra; do not modify the logger redaction lists.
- Implement only `pin` and `otp` checks in this plan. If `requiredChecks` contains `liveness` or any unknown value, do not finalize and leave that transfer unavailable. Do not send `livenessVerified`.
- Preserve the user's unrelated working-tree changes and do not turn on production transfers as part of implementation.

## Documented customer endpoints

| Flow | Method and route | Request | Success data and next use |
|---|---|---|---|
| BOCTRUST initiate | `POST /me/intrabank/transfers/initiate` | `toAccountNumber`, `amount`, optional `narration`; no PIN | `reference`, `requiredChecks`, `expiresAt` for the pending attempt. |
| BOCTRUST OTP | `POST /me/intrabank/transfers/{reference}/otp/request` | Path reference; no body | On the OTP page, request delivery only when `requiredChecks` contains `otp`. |
| BOCTRUST finalize | `POST /me/intrabank/transfers/{reference}/finalize` | `transactionPin` alone for PIN-only checks; `transactionPin` plus `otpCode` for PIN+OTP checks | The mobile sends the collected OTP code here. Retain returned `retrievalReference` for live requery. |
| BOCTRUST requery | `POST /me/intrabank/transfers/{retrievalReference}/requery` | Path tracking reference; no body | Live BankOne status; this read method already exists in the app. |
| Other-bank bank list | `GET /me/interbank/banks` | No input | Bank code/name list; already integrated. |
| Other-bank name preview | `POST /me/interbank/name-enquiry` | Destination bank code and account number | Recipient preview; already integrated. Finalize repeats the time-sensitive BankOne enquiry. |
| Other-bank initiate | `POST /me/interbank/transfers/initiate` | `receiverBankCode`, `receiverAccountNumber`, `amount`, optional `narration`; no PIN | `reference`, `requiredChecks`, `expiresAt`. |
| Other-bank OTP | `POST /me/interbank/transfers/{reference}/otp/request` | Path reference; no body | On the OTP page, request delivery only when required. |
| Other-bank finalize | `POST /me/interbank/transfers/{reference}/finalize` | PIN alone or PIN plus OTP code, according to `requiredChecks` | The mobile sends the collected OTP code here. Retain returned `transactionReference` for requery. |
| Other-bank status | `GET /me/interbank/transfers/{reference}/status` | Path reference | Last known status; already integrated, but verify whether it accepts the initiation reference after an uncertain finalize. |
| Other-bank requery | `POST /me/interbank/transfers/{reference}/requery` | Final tracking reference | Live BankOne status; already integrated. |

The documented finalize schema is shared between transfer types. This implementation handles `requiredChecks: ['pin']` and `requiredChecks` containing both `pin` and `otp`. The OTP request route initiates delivery to the customer; the collected OTP code is supplied to the backend on finalize. OTP request can return 400 when unnecessary, 403 when the initiation expired or no verified delivery address exists, and 404 for a missing pending reference. Finalize can return 401 for wrong PIN/OTP, 403 for account restriction/lock/expiry, 409 for a duplicate or similar recent transfer, and an uncertain outcome on timeout/5xx. Do not interpret an uncertain response as rejection.

## Current app and mobile field audit

| Need | Available now | Work required |
|---|---|---|
| Recipient/bank/amount/narration | `BoctrustTransferDraft` and `InterbankTransferDraft` hold recipient fields and an integer-Kobo `amountKobo` for local math. Both screens have recipient and amount review. | Send BOCTRUST initiate `amount` as the integer-Kobo string; convert only interbank to plain naira. Test ₦0.01, ₦1.00, ₦1,650.00, and the maximum in the respective formats. Validate bank-code format, narration length, available balance, and the documented max before initiate. Freeze the reviewed draft when an attempt begins. |
| BOCTRUST recipient preview | `BoctrustTransferFlow` currently calls `/accounts/{accountNumber}/enquiry`, a non-`/me` Core route. A recipient name may be preselected with the account number. | Seed a preselected name only for the exact selected number. On any account-number edit, cancel the in-flight lookup, clear the displayed name and provider result, and automatically run lookup when the number reaches 10 digits. Verify customer-safe authorization for the lookup route before enabling BOCTRUST sends. |
| Other-bank recipient preview | `InterbankTransferFlow` already uses `/me/interbank/banks` and `/me/interbank/name-enquiry`; beneficiaries may prefill. | On bank or account-number change, cancel the in-flight lookup and clear the name/provider result. Automatically look up the selected bank plus 10-digit account number; ignore late replies for an older pair. This reset/relookup flow handles a changed recipient before review; finalization still uses the server's authoritative outcome. |
| Pending reference/checks/expiry | No typed initiate result or awaiting-check phase. | Add a typed `CoreTransferInitiation` model with `reference`, allowlisted `requiredChecks`, and UTC expiry. Keep it in session state only. |
| PIN | Reusable `TransactionPinSheet` collects four digits and clears its field. | Present it after initiation. For PIN-only checks, finalize immediately with `transactionPin`. For PIN+OTP, keep the PIN only in the active authorization UI until finalize, then clear it. |
| OTP | No Core transfer OTP entry UI or state. | After PIN entry, open an OTP page; on that page call the appropriate `/{reference}/otp/request` route. Collect the code there and send it alongside the PIN on finalize. Do not store either value in the provider. |
| Liveness | No Core transfer liveness implementation is planned. | If returned checks include `liveness`, stop without finalizing and show an unavailable state. Never send `livenessVerified`. |
| Result/requery | `CoreTransferAck`, `CoreTrackingReference`, `CoreTransferAttemptView`, and `requeryTransfer` exist. | Distinguish pending initiation `reference` from final `retrievalReference`/`transactionReference`; update result copy and preserve unknown outcomes. |
| Navigation/capabilities | Send hub and screens already route by `boctrustTransfers` and `interbankTransfers`, but neither capability has registered operations. Both `_confirm` handlers show an unavailable sheet. | Register exact staged operations only after implemented, replace `_confirm` stubs with one attempt flow, and leave production unavailable. |

## Required backend and staging decisions before activation

1. **BOCTRUST recipient lookup:** The UI behavior is decided: preselect an exact account/name pair when available; otherwise cancel and clear on edits, then look up automatically at 10 digits. Separately verify a customer-scoped recipient-name route or strict access rule for the current `/accounts/{number}/enquiry`. A signed-in customer must not be able to read arbitrary account details. Until authorization is proven, BOCTRUST send stays gated.
2. **Required checks:** Support PIN-only and PIN+OTP replies. Capture sanitized real initiation replies and confirm expiry interpretation. The OTP page calls `/{reference}/otp/request`; finalize receives the entered OTP code. Do not expand this plan into alternative OTP delivery or resend cases.
3. **Liveness:** No implementation now. An initiation asking for liveness stops before finalize; do not send the client assertion.
4. **Unknown finalize recovery:** Test on staging what happens when finalize applies but the client loses the response, including app restart. Check whether interbank `GET .../{reference}/status` accepts the pending initiation reference and how BOCTRUST recovers without a final `retrievalReference`. Record the observed recovery path or required backend fix before activation; never use a blind retry.
5. **Response semantics and amount unit:** Use staging tests to establish when `responseCode: "00"`, `status`, and live requery mean completed versus accepted/pending. Confirm exact debit for intrabank's integer-Kobo payload and interbank's naira payload. The customer token must own each pending reference. A recipient changed in the UI is handled by the cancel/reset/relookup behavior in item 1; retain the server's final result as authoritative.

Record sanitized answers in `docs/verification/` with status codes and no real account numbers, names, PINs, OTPs, or full references. The route definitions alone do not satisfy these activation gates.

## File map and interfaces

| File | Responsibility |
|---|---|
| `lib/app/core_api_endpoints.dart` | Add `intrabankTransferInitiate`, `interbankTransferInitiate`, encoded OTP/finalize builders and literal templates; keep status/requery builders; add the two finalize templates to `moneyMoving`. |
| `lib/module/core_banking/model/core_transfer_initiation.dart` (new) | Parse `reference`, `requiredChecks`, and `expiresAt`; reject empty/duplicate/unknown checks or invalid expiry. Keep final tracking identifiers out of this model. |
| `lib/app/network.dart`, `lib/module/core_banking/service/core_transfer_service.dart`, `lib/module/core_banking/screens/core_flow_widgets.dart` | Add optional Dio `CancelToken` to `ApiService.getData` and `postData`, pass it through both recipient-name lookups, and preserve cancellation as a non-result. The shared lookup helper needs a token parameter. |
| `lib/module/core_banking/provider/core_recipient_lookup_provider.dart` (new) | Hold only the active bank/account query and resolved name; reset and cancel on input changes, with a generation check against replies that race cancellation. |
| `lib/module/core_banking/model/intrabank_models.dart`, `interbank_models.dart` | Keep BOCTRUST initiate's `amount` as the digit-only `amountKobo` string. Interbank's serializer converts `amountKobo` to plain naira with exact arithmetic. Do not share one serializer across these routes. |
| `lib/module/core_banking/model/core_submission_models.dart` | Reuse final ack parsing, extend outcome classification only where verified finalize responses differ from old assumptions. |
| `lib/module/core_banking/service/core_transfer_service.dart` | Add typed `initiateBoctrust(draft)`, `initiateInterbank(draft)`, `requestTransferOtp(kind, reference)`, and `finalizeTransfer(kind, reference, checks)` methods. Request extras must suppress sensitive paths and bodies. No method may auto-retry a POST. |
| `lib/module/core_banking/provider/core_transfer_attempt_provider.dart` | Keep the existing single-attempt invariant; represent reviewed, initiating, awaiting checks, requesting OTP, finalizing, settled, and unknown outcomes. Hold no PIN/OTP. Clear on sign-out/user switch. |
| `lib/module/core_banking/screens/transaction_pin_sheet.dart` and new focused OTP page | Collect PIN first; for PIN-only checks finalize immediately. For PIN+OTP checks, open the OTP page, call OTP request there, collect the code, and finalize with both values. Keep both values local to the active authorization UI and clear on cancel/disposal. |
| `lib/module/core_banking/screens/boctrust_transfer_screen.dart`, `interbank_transfer_screen.dart`, `core_transfer_attempt_view.dart` | Replace unavailable submit stubs, show initiation/check/finalize phases, support cancellation before finalize and tracking after it; keep recipient review visible and immutable through authorization. |
| `lib/module/send/screens/send_screens.dart`, `lib/app/feature_capability.dart` | Preserve Send hub routing; register staged operations separately for the two capabilities, staging-only. Do not expose old single-step paths. |
| `lib/app/private_user_state.dart` | Include any new user-scoped transfer state in sign-out clearing if the provider does not already clear itself. |
| `test/core_transfer_attempt_provider_test.dart`, `test/core_transfer_pin_ui_test.dart`, `test/core_transfer_requery_ui_test.dart`, `test/feature_capability_test.dart`, new focused service/model/OTP tests | Verify request contracts, state transitions, availability, sensitive logging, and end-to-end widget behavior. |

## Implementation tasks

### Task 1: Lock down the staged contracts and service calls

**Files:** `core_api_endpoints.dart`, new initiation model, `core_transfer_service.dart`; new `test/core_transfer_staged_service_test.dart` and `test/core_transfer_initiation_test.dart`.

- [ ] Write failing model tests for valid `reference`/checks/expiry, malformed or expired values, and unknown checks. Implement `CoreTransferInitiation.fromJson` with one representation for both transfer types.
- [x] Write request tests that assert BOCTRUST initiate sends exactly `toAccountNumber`, digit-only Kobo `amount`, optional `narration`, and no PIN; interbank sends exactly bank code, account number, plain-naira amount, optional narration. Test ₦1,650.00 → `165000` on BOCTRUST and exact cent conversion for interbank.
- [ ] Write request tests for encoded `reference` in OTP/finalize paths, empty-body OTP request, and finalize containing only the checks this initiation requested. Add those service calls and block unexpected checks locally.
- [ ] Assert the privacy path template hides recipient, PIN, OTP, and references from the existing logger; use `privacySensitivePathKey` on all new transfer requests, plus existing name-enquiry/status/requery paths as necessary. Do not edit redaction lists.
- [ ] Map final responses through `CoreTransferAck`. Test the distinct final tracking keys and no automatic retry on 400, 401, 403, 404, 409, 5xx, or timeout. Run the new focused tests.

### Task 2: Model one transfer attempt across all phases

**Files:** `core_transfer_attempt_provider.dart`, possibly a focused transfer-state model, `test/core_transfer_attempt_provider_test.dart`.

- [ ] Add transition tests for review → initiate → PIN sheet → finalize for PIN-only, and review → initiate → PIN sheet → OTP page → OTP request → finalize for PIN+OTP. Assert a second Send entry cannot start another attempt while the first is active, and that editing the draft before initiation invalidates review.
- [ ] Initiate before opening PIN entry. Store only the server reference, checks, expiry, draft, and safe status in provider state. Keep PIN in the active authorization UI across the OTP page only when needed, never in provider state. Check expiry before OTP and finalize; discard late replies from another user/session.
- [ ] On 401, permit credential correction only if the same initiation remains valid and the backend confirms that behavior. On 403 expiry/lock, 404 missing reference, or 409 possible duplicate, show a safe result without a blind new submission. An uncertain finalize retains an unresolved attempt.
- [ ] Keep cancellation before finalize distinct from money movement. One finalize request is allowed per user confirmation; disable repeated taps and avoid HTTP retries. Preserve the existing confirmed-final-state rule when requery later fails.
- [ ] Test sign-out, app background/return, expired initiation, rapid double taps, network timeout, and an out-of-order response. Run provider tests.

### Task 3: Wire BOCTRUST and other-bank UI

**Files:** both transfer screens, `core_transfer_attempt_view.dart`, `transaction_pin_sheet.dart`, new focused OTP sheet, `send_screens.dart`; widget tests.

- [ ] Replace both `_confirm` unavailable-sheet stubs with `beginReview` followed by initiate. Keep recipient/amount review visible; show initiating progress and then the returned checks and expiry. The Send hub routes to the correct flow when that capability is available.
- [ ] Extend `ApiService.getData` and `postData` with an optional Dio `CancelToken`, then thread it through `CoreTransferService.boctrustNameEnquiry`, `nameEnquiry`, and the shared lookup helper. Wire a recipient lookup provider with a token and stale-result generation: any account-number or bank change cancels the old request, resets provider/result/name state, and starts a new lookup automatically when the account number reaches 10 digits. BOCTRUST may seed a name tied to an exact preselected number. Test 9→10 digits, 10→edited 10 digits, bank switch, cancellation, and a late response that ignores cancellation.
- [ ] Reuse the PIN sheet after initiation. For PIN-only, finalize with PIN. For PIN+OTP, open the OTP page after PIN entry, call `/{reference}/otp/request` from that page, then finalize with PIN and the entered code. Clear both values on cancel, disposal, or completion; no resend or alternative-channel flow is included in this plan.
- [ ] If returned checks include liveness or an unknown check, show an unavailable explanation and prevent finalize. Never submit `livenessVerified`.
- [ ] Show accepted/pending/failed/unknown outcomes using `CoreTransferAttemptView`. Refresh the BocFlex balance after a confirmed settlement; keep status/requery controls for final BankOne tracking references. Never label initiate or an ambiguous finalize as successful.
- [ ] Add widget tests for both screen entry points, recipient edit/cancel invalidation, preselected BOCTRUST name, PIN-only, PIN+OTP page ordering, OTP request failure, expiry, duplicate-tap suppression, unknown outcome, and sign-out while a check sheet is open. Run focused widget tests.

### Task 4: Register capabilities and verify staging behavior

**Files:** `feature_capability.dart`, `core_api_endpoints.dart`, `test/feature_capability_test.dart`, `docs/verification/`.

- [ ] Register BOCTRUST and interbank operation sets separately, including their initiate, OTP, finalize, and tracking routes plus prerequisite lookup routes. Mark both staging-only; ensure `moneyMoving` contains finalize, not initiate, OTP, status, or requery.
- [ ] Test that production remains unavailable, a missing Core backend remains unavailable, and the existing authorization gate prevents initiate/finalize. The two capabilities must not unlock each other.
- [ ] On staging, verify each endpoint with sanitized accounts across PIN-only and OTP-required amounts. Verify 400/401/403/404/409 behavior, expiry, restrictions, name mismatch, and BankOne status progression without logging secrets.
- [ ] Record the staging results for lookup authorization, PIN-only and PIN+OTP checks, each flow's amount unit and actual debit, status meanings, and uncertain-finalize recovery. Enable only the flow whose evidence passes. Any liveness-required initiation remains unavailable because liveness is out of scope. Leave the other flow gated if its evidence is incomplete.

### Task 5: Finish regression and release checks

**Files:** tests and `docs/verification/` only unless a concrete defect is found.

- [ ] Run focused transfer tests, `flutter analyze`, and the full `flutter test` suite. Fix introduced failures and rerun only the affected checks before the final full gate.
- [ ] Verify Send hub navigation, accessibility labels/focus for PIN and OTP, loading/cancel/retry copy, account switch, and return from background on a staging device. Confirm that a request cannot be sent through scan-to-pay or a beneficiary deep link while its transfer capability is unavailable.
- [ ] Record the exact release state for each capability and the remaining backend dependency, with sanitized request/response evidence. Do not infer production readiness from staging success alone.

## Review focus

- An initiation whose `requiredChecks` includes OTP must never finalize with PIN alone.
- A lost finalize response must never trigger a second money-moving POST, including after app restart.
- The BOCTRUST recipient preview must not expose arbitrary account details through a non-customer route.
- A client-side liveness boolean must never satisfy an unverified compliance check.
- A final BankOne `retrievalReference` or `transactionReference` must never be confused with the pending initiation `reference` when checking status.

## Suggested sequence

Complete Task 1's typed contract and Task 2's state flow, then wire each UI independently in Task 3. Resolve backend activation gates in parallel with read-only preparation, but do not enable a money-moving capability until Task 4 records the required proof. Task 5 verifies the complete customer path. This plan adds only BOCTRUST-to-other-customer and interbank sends; own-account movement needs a separate documented replacement route.
