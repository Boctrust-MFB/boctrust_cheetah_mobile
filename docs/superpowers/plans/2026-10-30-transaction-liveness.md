# Transaction Liveness Implementation Plan

> **For agentic workers:** Execute the tasks **in order, one at a time** (superpowers:subagent-driven-development with a single implementer, or superpowers:executing-plans). Each task builds on the previous one and they share files, so they never run in parallel. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Finish a Core transfer whose initiation asks for `liveness`: after PIN and OTP, run a backend-selected Dojah reconfirmation, wait for User Service `verified`, then finalize once. Smile ID selections stop safely.

**Architecture:** The session-owned `CoreTransferAttemptNotifier` gains two identity phases. A small User Service client handles reconfirmation initiate and status. Capture reuses the existing `DojahCaptureScreen`. `finalize` refuses a liveness transfer unless the stored reconfirmation is `verified`, for the same reference, and inside both expiry windows. The attempt view, not the PIN/OTP sheet loop, drives the identity step, so it survives leaving and re-entering either transfer screen.

**Spec:** `docs/superpowers/specs/2026-10-30-transaction-liveness-design.md`. Supersedes `docs/superpowers/plans/2026-10-24-core-transfer-liveness.md`.

## Global constraints

- Preserve unrelated working-tree edits.
- The app never checks the amount threshold; `requiredChecks` containing `liveness` decides.
- Never override the provider User Service picks; a `smile_id` challenge stops without capture. No Smile SDK upgrade.
- Finalize stays bodyless and at most once; a lost reply stays `UnknownSubmission`.
- Hold only non-secret identifiers and status in state. The Dojah nonce lives on the pending reconfirmation only until capture.
- No activation gate; the existing staging-only transfer capabilities cover it.
- **Tests: one.** The finalize-gate test in Task 3. Delete or trim the existing tests that assert liveness is refused; add nothing else.

## File map

| File | Change |
|---|---|
| `lib/app/api_endpoints.dart` | Reconfirmation paths |
| `lib/app/services.dart`, `.env.example`, `README.md` | `DOJAH_TRANSACTION_WIDGET_ID` |
| `lib/app/feature_capability.dart` | Declare the two User Service operations on both transfer capabilities |
| `lib/module/core_banking/model/transaction_reconfirmation.dart` (new) | Model and the `provesTransfer` predicate |
| `lib/module/core_banking/service/transaction_reconfirmation_service.dart` (new) | initiate and status |
| `lib/module/core_banking/model/core_transfer_initiation.dart` | `requiresLiveness`; `supported` no longer refuses liveness |
| `lib/module/core_banking/model/core_check_progress.dart` | Pending liveness is fine when initiation required it |
| `lib/module/core_banking/model/core_submission_models.dart` | New rejections and liveness-aware 403 |
| `lib/module/core_banking/provider/core_transfer_attempt_provider.dart` | Identity phases, actions, finalize gate |
| `lib/module/core_banking/screens/core_transfer_attempt_view.dart` | Hand-off, `showsAttempt`, identity panel |
| `lib/module/core_banking/screens/transfer_identity_panel.dart` (new) | Consent, Dojah launch, pending, polling |
| tests | One new provider test; remove obsolete liveness-refusal tests |

---

### Task 1: Endpoints, config, and the reconfirmation client

**Files:** `lib/app/api_endpoints.dart`, `lib/app/services.dart`, `.env.example`, `README.md`, `lib/app/feature_capability.dart`, new `transaction_reconfirmation.dart`, new `transaction_reconfirmation_service.dart`.

- [ ] In `ApiEndpoints`, add the following, following the `withdrawalBankAccounts` style:

  ```dart
  static const initiateIdentityReconfirmation =
      '/users/me/identity-reconfirmations/initiate';
  static const identityReconfirmationTemplate =
      '/users/me/identity-reconfirmations/{id}';
  static String identityReconfirmation(String id) =>
      '/users/me/identity-reconfirmations/${Uri.encodeComponent(id)}';
  ```

- [ ] In `Env`, add `dojahTransactionWidgetId = String.fromEnvironment('DOJAH_TRANSACTION_WIDGET_ID')`. Add the key to `.env.example`, and add one line in the README next to the other Dojah keys: "optional; falls back to the BVN selfie widget".
- [ ] In `capabilityRequirements` for `boctrustTransfers` and `interbankTransfers`, add `(backend: ApiBackend.user, method: 'POST', path: ApiEndpoints.initiateIdentityReconfirmation)` and `(backend: ApiBackend.user, method: 'GET', path: ApiEndpoints.identityReconfirmationTemplate)`. The User backend is always configured, so availability is unchanged. If an exact-path assertion in `test/feature_capability_test.dart` fails, update that expectation only.
- [ ] Create `transaction_reconfirmation.dart`:

  ```dart
  enum ReconfirmationStatus { pending, comparing, verified, failed, expired, superseded }
  enum ReconfirmationProvider { smileId, dojah } // wire: smile_id, dojah

  class TransactionReconfirmation extends Equatable {
    // verificationId (UUID string), status, provider, withdrawalReference,
    // expiresAt (UTC), validUntil (UTC, nullable),
    // dojahReference (metadata.reference, nullable; pending only)
    factory TransactionReconfirmation.fromJson(Object? json);

    /// Whether this proves [reference] for finalize at [now].
    bool provesTransfer(String reference, DateTime now) =>
        status == ReconfirmationStatus.verified &&
        withdrawalReference == reference &&
        validUntil != null &&
        now.toUtc().isBefore(validUntil!);

    /// A terminal state that can never become verified.
    bool get isTerminalFailure => status == failed || expired || superseded;

    /// This record without the capture nonce, for keeping after capture.
    TransactionReconfirmation withoutCapture();
  }
  ```

  `fromJson` throws a `FormatException` on a non-map, a missing `verificationId` or `withdrawalReference`, an unknown status or provider, or an unparsable `expiresAt`. It ignores `method`, `captureMode`, token, callback URL, partner params, and consent; they are not stored.
- [ ] Create `transaction_reconfirmation_service.dart` with `transactionReconfirmationServiceProvider = Provider((ref) => TransactionReconfirmationService(ref.watch(apiServiceProvider)))`, using the same shape as `KycService`:

  ```dart
  Future<NotifierState<TransactionReconfirmation>> initiate(
    String reference, {required DateTime consentedAt}) =>
    _api.postData(ApiEndpoints.initiateIdentityReconfirmation,
      data: {
        'withdrawalReference': reference,
        'consent': {
          'granted': true,
          'grantedAt': consentedAt.toUtc().toIso8601String(),
          'noticeLanguage': 'EN',
          'privacyPolicyUrl': sitePageUri('privacy').toString(),
        },
      },
      parser: TransactionReconfirmation.fromJson,
      requestExtra: {LoggingInterceptor.privacySensitivePathKey:
          ApiEndpoints.initiateIdentityReconfirmation}) → NotifierState.fromResponse

  Future<NotifierState<TransactionReconfirmation>> status(String verificationId)
    // GET ApiEndpoints.identityReconfirmation(id), privacy marker set to
    // identityReconfirmationTemplate.
  ```

- [ ] Run `flutter analyze`.

### Task 2: Let liveness through the models

**Files:** `core_transfer_initiation.dart`, `core_check_progress.dart`, `core_submission_models.dart`; remove obsolete tests.

- [ ] In `CoreTransferInitiation`, add `bool get requiresLiveness => checks.contains(CoreTransferCheck.liveness);`. Change `supported` to `true` and remove it with its callers (`core_transfer_service.dart:81`, the two checks in the attempt provider), or keep it as `=> true` if removing it is noisy. Update the doc comments that say liveness is never finalized.
- [ ] In `coreCheckProgressContradicts`, replace `pending.contains(CoreTransferCheck.liveness) ||` with `(pending.contains(CoreTransferCheck.liveness) && !initiation.requiresLiveness) ||`. A pending liveness after PIN/OTP is expected when initiation asked for it.
- [ ] In `CoreRejection`, add:
  - `identityFailed("We couldn't confirm your identity, so this transfer was not sent.")`
  - `identityUnavailable("The identity check isn't available right now. Please try again later.")`
  - `identityProviderUnsupported("This transfer needs an identity check the app can't do yet.")`
  - `identityNotConfirmed("This transfer couldn't be confirmed. It may have expired. Please start it again.")`

  Change `checksUnsupported` copy to drop "Try a smaller amount", since the threshold is dynamic.
- [ ] Remove the tests that assert the old refusal: `core_transfer_initiation_test.dart` "liveness is understood but not supported" (keep it only as a parse check that `requiresLiveness` is true); `core_transfer_staged_service_test.dart` (drop the liveness half of "a liveness or expired initiation is never sent" and keep the expired half); `core_transfer_pin_ui_test.dart` "a liveness check is refused without finalizing"; `core_transfer_attempt_provider_test.dart` "a liveness check stops before any check is sent". Task 3 replaces that last one.
- [ ] Run `flutter analyze`.

### Task 3: Identity phases and the finalize gate

**File:** `core_transfer_attempt_provider.dart`. **Test:** `test/core_transfer_attempt_provider_test.dart` (the one test).

- [ ] Add phases after `verifyingOtp`:

  ```dart
  /// PIN/OTP passed and Core asked for liveness: consent and capture next.
  awaitingIdentity,
  /// Capture done or resumed; waiting for User Service to say verified.
  checkingIdentity,
  ```

- [ ] Add `final TransactionReconfirmation? identity;` to `CoreTransferAttempt`, its constructor, `props`, and `_checked`. Give `_with` an `identity` parameter that defaults to `this.identity`.
- [ ] In `_verify`, the next phase after a pass becomes:

  ```dart
  step == CoreTransferCheck.pin && initiation.needsOtp
      ? CoreTransferPhase.awaitingOtp
      : initiation.requiresLiveness
          ? CoreTransferPhase.awaitingIdentity
          : CoreTransferPhase.readyToFinalize
  ```

- [ ] Add `bool _identityBusy = false;` and these actions. Each captures `_generation`, re-checks `ref.mounted`, the generation, and `_open(id, phase)` after every await, and returns early otherwise.
  - `Future<TransactionReconfirmation?> startIdentity(int id, {required DateTime consentedAt})` runs in `awaitingIdentity`.
    - Settle `initiationExpired` if the initiation has expired.
    - Call `initiate(initiation.reference, consentedAt: ...)`.
    - 429 or 502 → settle `identityUnavailable`. Another failure or a parse error → settle `identityFailed`. A `withdrawalReference` mismatch → settle `identityFailed`. A terminal status → settle `identityFailed`.
    - `smile_id` → settle `identityProviderUnsupported`.
    - `verified` → store it and go to `_proceedIfProven`.
    - `comparing` → store `withoutCapture()` and move to `checkingIdentity`.
    - `pending` with a non-empty `dojahReference` → store the record and return it to the caller for capture.
  - `void identityCaptured(int id)` runs in `awaitingIdentity` with a stored identity: store `identity.withoutCapture()` and move to `checkingIdentity`. A cancelled or failed capture calls `cancelReview(id)`; no money moved.
  - `Future<void> refreshIdentity(int id)` runs in `checkingIdentity`. It allows one request at a time via `_identityBusy`.
    - If either the initiation or the challenge `expiresAt` has passed → settle `initiationExpired`.
    - GET `status(identity.verificationId)`. An error keeps the phase (the panel shows Check again), except 404, which settles `identityFailed`.
    - A mismatched reference or terminal status → settle `identityFailed`.
    - `verified` → store it, then `_proceedIfProven`.
    - `pending`/`comparing` → store it and stay.
  - `_proceedIfProven(current)`: if `identity.provesTransfer(initiation.reference, now)` and `!initiation.isExpiredAt(now)`, set `readyToFinalize` and `await finalize(id)`. Otherwise settle `identityNotConfirmed`.
- [ ] Gate `finalize`. After the existing expiry check, add:

  ```dart
  if (initiation.requiresLiveness &&
      !(current.identity?.provesTransfer(initiation.reference, DateTime.now()) ?? false)) {
    return _settle(current, CoreRejection.identityNotConfirmed);
  }
  ```

  For liveness transfers, map a finalize 403 to `RejectedSubmission(CoreRejection.identityNotConfirmed)` instead of `transferRestricted`:

  ```dart
  if (initiation.requiresLiveness &&
      outcome case RejectedSubmission(reason: CoreRejection.transferRestricted)) {
    outcome = const RejectedSubmission(CoreRejection.identityNotConfirmed);
  }
  ```

  Keep the Home refresh it triggers today.
- [ ] `cancelReview` already allows any phase before `finalizing`; the identity phases rely on that. `clear()` and the auth listener already bump `_generation`, which drops late replies on logout or account change.
- [ ] **The one test.** Stub a reconfirmation service in the existing `_setUp` style. Use initiation `['pin', 'liveness']` and a PIN reply with pending `['liveness']`:
  1. After `verifyPin`, the phase is `awaitingIdentity`.
  2. With a `comparing` status, `finalize(id)` sends nothing (`transfers.finalized == 0`).
  3. With `verified` but a different `withdrawalReference`, `refreshIdentity` settles and `finalized` stays 0.
  4. In a fresh attempt, `verified` with a matching reference and future `validUntil` gives exactly one finalize, and a second `finalize(id)` still leaves `finalized == 1`.
- [ ] Run `flutter test --no-pub test/core_transfer_attempt_provider_test.dart test/core_transfer_initiation_test.dart test/core_transfer_staged_service_test.dart` and `flutter analyze`.

### Task 4: Customer journey

**Files:** `core_transfer_attempt_view.dart`, new `transfer_identity_panel.dart`. No tests.

- [ ] In `authorizeStagedTransfer`, after the OTP block and before the final finalize line, add `if (at(CoreTransferPhase.awaitingIdentity)) return;`. The attempt view takes over, and leaving no longer cancels the attempt. The existing finalize line then only runs for non-liveness transfers.
- [ ] In `showsAttempt`, add `CoreTransferPhase.awaitingIdentity || CoreTransferPhase.checkingIdentity`, so both transfer screens show the attempt on re-entry.
- [ ] In `_CoreTransferAttemptViewState.build`, route both identity phases to `TransferIdentityPanel(attempt: attempt)` before the `case _` loading fallback.
- [ ] `TransferIdentityPanel` (ConsumerStatefulWidget, existing `AppUi`/`BocStatusKind` building blocks):
  - **`awaitingIdentity`:** one short paragraph ("To protect larger transfers, confirm it's you with a quick selfie. This check is only for this transfer."). Add a **Privacy policy** link that opens `LegalDocumentScreen.privacy()`, a primary **Continue** button, and a **Cancel transfer** button (`cancelReview` + `onExit` via callback).
  - **Continue:** record `DateTime.now().toUtc()` at the tap, call `startIdentity`, and keep the button busy. On a returned pending challenge, push `DojahCaptureScreen(widgetId: _transactionWidgetId(), referenceId: challenge.dojahReference!, operation: KycOperation.identity, email: <profile email, as kyc_screens.dart:1487>)`. `KycCaptureOutcome.submitted` → `identityCaptured(id)` then `refreshIdentity(id)`; anything else → `cancelReview(id)`.
  - **Widget ID:** `Env.dojahTransactionWidgetId.trim()`, else `ref.read(dojahConfigProvider).selfieWidgetId`. If both are empty, settle via `cancelReview` and show "Identity check is not configured for this environment."
  - **`checkingIdentity`:** "Checking your identity…" with **Check again** (`refreshIdentity`) and **Cancel transfer**. On `initState`, or on entering this phase, start a `Timer.periodic(5s)` calling `refreshIdentity`. Stop after 24 ticks (2 minutes) or in `dispose`; on re-entry it starts again, which also re-reads the same verification ID before any finalize.
  - Once `readyToFinalize`, `finalizing`, or `settled`, the existing view takes over (loading, then result and requery).
- [ ] Run `flutter analyze` and `dart format --output=none --set-exit-if-changed lib test`. Then run the focused transfer suites: `flutter test --no-pub test/core_transfer_attempt_provider_test.dart test/core_transfer_pin_ui_test.dart test/core_transfer_staged_service_test.dart test/feature_capability_test.dart`.

### Task 5: Staging check (manual, no code)

**File:** `docs/verification/transaction-liveness.md` with sanitized results.

- [ ] Ask the admin to lower the liveness threshold in staging so a small transfer asks for liveness.
- [ ] On a physical Android and iOS device: run Dojah × BOCTRUST and Dojah × other bank, each with a PIN-only and a PIN+OTP initiation. Record the widget ID used (transaction or BVN fallback), observed statuses, one finalize, the debit once, and the result and requery.
- [ ] Check cancel at consent, cancel in Dojah, leaving and re-entering during `checkingIdentity`, and logout during checking. None of them may finalize.
- [ ] If staging ever returns `smile_id`, confirm the safe stop copy and that nothing finalizes.
- [ ] Record any `ReconfirmationError.code` or finalize 403 body observed, so copy can be narrowed later.
- [ ] Run `flutter test --no-pub` and record the result with any unrelated baseline failures.

## Known deferrals

- Smile ID capture: no Flutter SDK produces `encryptedPackage`, `packageNonce`, or `packageTag`. Revisit when one ships; the `submit` route is not built until then.
- Distinguishing a technical failure (retryable) from a biometric rejection: `failureReason` values aren't documented, so any terminal failure asks for a new transfer.
- Activation gating beyond the current staging-only capabilities.
