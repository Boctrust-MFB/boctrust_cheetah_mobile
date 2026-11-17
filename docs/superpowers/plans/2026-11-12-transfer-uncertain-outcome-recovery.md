# Uncertain Transfer Recovery (Mobile Stopgap) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep an unconfirmed BOCTRUST or interbank transfer visible, and checkable, after an app restart or signing in again on the same device. Also record whether Core's interbank status route can find a transfer by its initiation reference.

**Architecture:** Before finalize is sent, the attempt notifier writes a small marker to secure storage. The marker is keyed by the initiation reference and bound to the customer. It is updated with the tracking reference when one arrives, and deleted once the outcome is definite. On sign-in or cold start, the signed-in customer's markers come back as set-aside attempts. The existing `SetAsideTransfers` card and `check()` show them, so no new UI is needed. This is a stopgap layer only: the real fix needs the Core contract in the spec, and that gets its own plan once Core publishes it.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_secure_storage` through `lib/helper/secure_storage.dart`.

**Spec:** [`docs/superpowers/specs/2026-11-12-transfer-recovery-core-contract.md`](../specs/2026-11-12-transfer-recovery-core-contract.md). Its "The problem" section and the stopgap paragraph are what this plan implements. The requested contract is out of scope here.

## Global Constraints

- Keep `boctrustTransfers` and `interbankTransfers` `stagingOnly`. Change no capability flag.
- Never resend or automatically replay finalize. A restored attempt is settled: it can be checked, never finalized.
- A marker holds only: schema version, `userId`, kind, initiation reference, tracking reference (when known), amount in integer Kobo, the last four digits of the recipient's account, the bank name (interbank only), and `createdAt`. No PIN, OTP, liveness data, full account number or account name.
- A secure-storage failure never blocks or changes a transfer. The marker is best effort.
- Known limitation, accepted for the stopgap: a marker with no tracking reference can't be checked. It stays listed as "not confirmed" until it ages out after 30 days.
- Tests: exactly one new provider test, in Task 3 (project rule: tests only where money movement needs a guard).

## Review Focus

Per the project's test policy, these are reviewer checks. Only the first two are pinned by Task 3's single test.

- A different customer signs in on the same device: none of the previous customer's markers appear (pinned).
- Cold restart after an unconfirmed finalize: the attempt comes back as set aside, still unresolved, with its amount (pinned).
- A late finalize reply that lands after sign-out must not update or remove a marker. It stays unconfirmed for its own customer.
- A malformed, foreign-version or over-30-day marker is skipped without throwing, and the transfer flow still works.
- A restored attempt that a check confirms as completed, failed or reversed is removed from storage and does not return on the next launch.

---

### Task 1: Staging check of interbank status by initiation reference

Kenechukwu runs this on staging. It needs the Pixel and a staging token, which no subagent has. No code changes.

**Files:**
- Modify: `docs/verification/2026-10-10-staged-transfers.md`

- [ ] **Step 1: Send ₦10.00 interbank on staging and note both references**

Run: `flutter run -d 2B161FDH30033N --dart-define-from-file=.env.stage`. Send ₦10.00 to another bank. In the staging log, note the `reference` from the initiate reply and the `reference` and `transactionReference` from the finalize reply.

- [ ] **Step 2: Call status with the initiation reference**

Use your own staging access token:

```bash
curl -s -H "Authorization: Bearer $STAGING_TOKEN" "$CORE_BASE_URL/me/interbank/transfers/<initiation reference>/status"
```

Expected: either 200 with a status (the route accepts the initiation reference) or 404/400 (it does not). Repeat with the finalize `reference` so we know which one the route means.

- [ ] **Step 3: Record the result and correct two stale lines in the verification doc**

In `docs/verification/2026-10-10-staged-transfers.md`:
- Tick the "Uncertain finalize" item, recording which reference `status` accepts. Use sanitized references (first and last two characters only).
- Replace "The documented interbank 500 is a definite failure." with "The interbank 500 means BankOne could not be reached or timed out; the app treats it as unconfirmed (Swagger: requery before retrying)."
- Replace the "Amount (updated 10 October)" bullet's unit claim with the current contract: initiate takes a naira decimal string (`"1650.00"`), converted from Kobo by `koboToNaira` in the draft's `toJson`.
- Add under "Recovery after restart": "Mobile stopgap: unconfirmed transfers persist on this device (plan 2026-11-12). Cross-device recovery waits on the Core contract (spec 2026-11-12)."

- [ ] **Step 4: Commit**

```bash
git add docs/verification/2026-10-10-staged-transfers.md
git commit -m "docs(transfers): record interbank status-by-reference result and fix stale notes"
```

If status accepts the initiation reference, tell Core in reply to the spec's decision 7. A follow-up could then let interbank markers without a tracking reference be checked through `getTransferStatus`. That follow-up is not part of this plan.

### Task 2: Recovery marker and store

**Files:**
- Create: `lib/module/core_banking/model/core_transfer_recovery_marker.dart`
- Create: `lib/module/core_banking/service/core_transfer_recovery_store.dart`
- Modify: `lib/helper/secure_storage.dart` (three methods beside the biometric-transfer ones)

**Interfaces:**
- Consumes: `CoreTransferKind` (`core_transfer_requery_models.dart`), `BoctrustTransferDraft`, `InterbankTransferDraft`, `SecureStorage`, `secureStorageProvider`.
- Produces:
  - `class CoreTransferRecoveryMarker extends Equatable` with final fields `String userId`, `CoreTransferKind kind`, `String initiationReference`, `String? trackingReference`, `String amountKobo`, `String accountLast4`, `String? bankName`, `DateTime createdAt` (UTC).
  - `Map<String, Object?> toJson()` (includes `'v': 1`) and `static CoreTransferRecoveryMarker? tryParse(Object? json)`. `tryParse` returns null for a non-map, `v != 1`, any missing or empty required string, a `kind` that isn't a `CoreTransferKind` name, `accountLast4` that isn't four digits, or an unparseable `createdAt`.
  - `CoreTransferRecoveryMarker withTracking(String value)`.
  - `Object toDraft()`. Intrabank: `BoctrustTransferDraft(toAccountNumber: '•••• $accountLast4', amountKobo: amountKobo)`. Interbank: `InterbankTransferDraft(bankCode: '', bankName: bankName ?? '', accountNumber: '•••• $accountLast4', accountName: '', amountKobo: amountKobo)`. A restored draft is display-only and is never sent.
  - `SecureStorage.readTransferRecovery() → Future<String?>`, `writeTransferRecovery(String json) → Future<void>`, `deleteTransferRecovery() → Future<void>`. Key: `'$_prefix.transfer_recovery.v1'`. Use `_biometricAppleOptions` so the marker never syncs or migrates to another device.
  - `final coreTransferRecoveryStoreProvider = Provider<CoreTransferRecoveryStore>((ref) => CoreTransferRecoveryStore(ref.watch(secureStorageProvider)));`
  - `class CoreTransferRecoveryStore` with:
    - `Future<List<CoreTransferRecoveryMarker>> readFor(String userId, {required DateTime now})`: that customer's markers, newest first.
    - `Future<void> save(CoreTransferRecoveryMarker marker)`: upsert by `initiationReference`.
    - `Future<void> remove(String initiationReference)`.

- [ ] **Step 1: Implement the marker in `core_transfer_recovery_marker.dart`**

Field names on the wire match the Dart field names, with `createdAt` as ISO-8601 UTC and `kind` as `CoreTransferKind.name`.

- [ ] **Step 2: Add the three `SecureStorage` methods**

- [ ] **Step 3: Implement `CoreTransferRecoveryStore` in `core_transfer_recovery_store.dart`**

Storage holds one JSON array of markers for every customer on the device.
- Every public method runs after the previous one finishes. Chain them on a private `Future<void> _queue`, so a `save` and a `remove` can't interleave their read-modify-write.
- Every storage or JSON error is caught. `readFor` then returns `[]`, and `save` and `remove` do nothing.
- On each write, drop entries that `tryParse` rejects and entries older than 30 days before `now`. If more than 10 remain, keep the 10 newest across all customers.
- `readFor` applies the same 30-day filter, then filters by `userId`.
- If the list ends up empty, delete the key rather than writing `[]`.

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/module/core_banking lib/helper/secure_storage.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/module/core_banking/model/core_transfer_recovery_marker.dart lib/module/core_banking/service/core_transfer_recovery_store.dart lib/helper/secure_storage.dart
git commit -m "feat(transfers): add a device-local recovery marker for unconfirmed transfers"
```

### Task 3: Persist and restore unconfirmed attempts in the notifier

**Files:**
- Modify: `lib/module/core_banking/provider/core_transfer_attempt_provider.dart` (`build`, `finalize`, `check`, `clear`, plus new private `_restore` and `_referenceOf`)
- Test: `test/core_transfer_attempt_provider_test.dart`

**Interfaces:**
- Consumes from Task 2: `CoreTransferRecoveryMarker` (fields, `withTracking`, `toDraft`), and `coreTransferRecoveryStoreProvider` with `readFor` / `save` / `remove`.
- Produces: no new public API. Restored attempts appear in `CoreTransferAttemptState.acknowledged` with `phase: CoreTransferPhase.settled`. Their `outcome` is `AcceptedSubmission(CoreTransferAck(retrievalReference: t))` for intrabank, or `AcceptedSubmission(CoreTransferAck(transactionReference: t))` for interbank, when the marker has a tracking reference `t`. Otherwise it is `const UnknownSubmission()`. So `unresolved`, `tracking` and `check()` work unchanged.

- [ ] **Step 1: Write the failing test**

In `_setUp`, add a `SecureStorage? storage` parameter and always override `secureStorageProvider` with `storage ?? SecureStorage(storage: MemorySecureStorage())` (from `test/support/memory_secure_storage.dart`). Then add:

```dart
test('an unconfirmed transfer is restored after restart for the same '
    'customer only', () async {
  final storage = SecureStorage(storage: MemorySecureStorage());
  final first = _setUp(storage: storage);
  final id = await _initiate(first.container);
  final notifier = first.container.read(coreTransferAttemptProvider.notifier);
  await notifier.verifyPin(id, '1234');
  first.transfers.reply.complete(_error(500));
  await notifier.finalize(id);
  expect(_current(first.container)?.outcome, isA<UnknownSubmission>());

  // Cold restart: a new container over the same device storage.
  final second = _setUp(storage: storage);
  second.container.read(coreTransferAttemptProvider);
  await pumpEventQueue();
  final restored = second.container.read(coreTransferAttemptProvider).acknowledged;
  expect(restored, hasLength(1));
  expect(restored.single.unresolved, isTrue);
  expect((restored.single.draft as BoctrustTransferDraft).amountKobo, '1000');
  expect(second.transfers.finalized, 0);

  // A different customer on the same device sees nothing.
  (second.container.read(authSessionProvider.notifier) as SavingsSession)
      .setSession(savingsSession(user: 'someone-else'));
  await pumpEventQueue();
  expect(second.container.read(coreTransferAttemptProvider).acknowledged, isEmpty);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core_transfer_attempt_provider_test.dart --plain-name "restored after restart"`
Expected: FAIL at `expect(restored, hasLength(1))` (actual length 0).

- [ ] **Step 3: Write the marker before finalize and update it after**

In `finalize`, after `_set(... phase: CoreTransferPhase.finalizing)` and before calling the service:
- Read `ref.read(authSessionProvider)?.userId`.
- If it is non-null, build the marker from the attempt: `kind`, `initiation.reference`, the draft's `amountKobo`, the last four digits of `toAccountNumber` / `accountNumber`, the interbank `bankName`, and `DateTime.now().toUtc()`.
- `await` the store's `save` inside `try`/`catch`. A failure never stops finalize.
- That `await` is a new async gap before money moves. Afterwards, re-check `ref.mounted`, `generation == _generation` and `_open(id, CoreTransferPhase.finalizing)`. If any fails (for example, the customer signed out during the write), call `remove(initiation.reference).ignore()` and return without calling the service. Nothing was sent, so nothing moved. The existing test "signing out drops the attempt and ignores a late reply" covers this path and must keep passing.

After the existing generation and phase guard, once the outcome is known:
- `AcceptedSubmission` whose `tracking` is non-null: `save(marker.withTracking(tracking.value))`.
- `RejectedSubmission`: `remove(initiation.reference)`.
- Anything else: leave the marker unchanged.

Fire both with `.ignore()`. They must not delay the state update.

- [ ] **Step 4: Remove the marker when a check is final**

In `check`, after `_replace(latest._checked(live: next))`: if `next.state` is `completed`, `failed` or `reversed` and `_referenceOf(latest)` is non-null, call `remove` on it with `.ignore()`.

`String? _referenceOf(CoreTransferAttempt a)` returns `a.initiation?.reference ?? _restoredReferences[a.id]`, where `final Map<int, String> _restoredReferences = {}` is a new notifier field.

- [ ] **Step 5: Restore on sign-in and cold start**

Add `Future<void> _restore(String userId)`:
- Capture `_generation`, then `await store.readFor(userId, now: DateTime.now().toUtc())`.
- Afterwards, return if `!ref.mounted` or the generation changed.
- Skip markers whose `initiationReference` already belongs to `current` or to an acknowledged attempt (`_referenceOf`).
- For each remaining marker, create a `CoreTransferAttempt(id: ++_nextId, draft: marker.toDraft(), phase: CoreTransferPhase.settled, outcome: …)` as described in Interfaces, and record `_restoredReferences[id] = marker.initiationReference`.
- Append them to `acknowledged` with `_set(current: state.current, acknowledged: [...])`.

In `build`:
- In the existing `authSessionProvider` listener, after `clear()`, call `_restore(next.userId).ignore()` when `next != null`.
- Before returning, if `ref.read(authSessionProvider)?.userId` is non-null, schedule `Future.microtask(() => _restore(userId))`. Riverpod forbids setting state during `build`.

In `clear()`, also empty `_restoredReferences`. Do not touch storage: sign-out keeps the markers for that customer's next sign-in.

- [ ] **Step 6: Run the new test and the rest of the file**

Run: `flutter test test/core_transfer_attempt_provider_test.dart`
Expected: all tests pass, including "restored after restart".

- [ ] **Step 7: Analyze and run the full suite**

Run: `flutter analyze` and then `flutter test --no-pub`
Expected: `No issues found!`. Every test passes, or any failure is one that also fails on `main` before this branch. Name any such failure in the task report.

- [ ] **Step 8: Commit**

```bash
git add lib/module/core_banking/provider/core_transfer_attempt_provider.dart test/core_transfer_attempt_provider_test.dart
git commit -m "feat(transfers): restore unconfirmed transfers after restart and re-sign-in"
```

### Task 4: Device check

Kenechukwu runs this on staging (Pixel 7 Pro).

- [ ] **Step 1: Restart after a lost finalize reply**

Start ₦10.00 BOCTRUST, turn on airplane mode as soon as you approve, and wait for "Transfer not confirmed". Force-stop the app, turn off airplane mode, and relaunch. Expected: "Earlier transfer not confirmed · ₦10.00" appears above the transfer form.

- [ ] **Step 2: Sign out and back in**

Sign out, then sign in as the same customer. Expected: the card is still there. Sign in as a different customer. Expected: no card.

- [ ] **Step 3: Resolve it**

On a restored attempt that has a tracking reference, tap "Check status" until it shows completed, failed or reversed. Relaunch. Expected: that attempt no longer appears.

## Next plan (not in scope)

Once Core publishes the contract in the spec, write a separate plan to:
- generate and store `clientRequestId` before initiate;
- look up a lost initiate or finalize reply with `by-client-request`;
- merge `GET /me/transfers?state=unresolved` with these markers;
- use `stateVersion` ordering, `cancel` for abandoned pre-finalize attempts, and `POSSIBLE_DUPLICATE_UNRESOLVED` handling.

These markers will then gain a `clientRequestId` field (schema `v: 2`).
