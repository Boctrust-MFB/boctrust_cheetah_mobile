# Transfer Recovery: Core Contract Request

**Date:** 12 November 2026
**For:** the Core team (transfer initiation, finalization, BankOne dispatch and reconciliation)
**From:** BocFlex mobile
**Status:** proposal. Nothing here is a confirmed route. Mobile will not build against it until Core publishes the agreed contract in Swagger.

## The problem

A customer must be able to find the real outcome of a BOCTRUST (intrabank) or interbank transfer after a lost reply, an app restart, signing in again, or switching devices, without sending the money twice.

Today the app cannot do this:

- `finalize` is sent once. If its reply is lost, the app has only the initiation `reference`. The app can check status only through `retrievalReference` (intrabank) or `transactionReference` (interbank), and those arrive only in a successful finalize reply.
- No documented route looks up a transfer by its initiation `reference`. Interbank `GET {reference}/status` describes its parameter as "the reference returned in the original transfer's response", and nothing says whether that means initiate's or finalize's reference. Mobile is testing this on staging.
- The only guard against duplicates is finalize's 409: "a similar transfer was made in the last 60 seconds, or the transfer is already being processed". That is too short to protect a customer who restarts the app, and a 409 alone doesn't say which of the two happened.
- If the initiate reply itself is lost, nobody holds any identifier.

The risks are a duplicate debit, a customer believing a transfer failed when it is still processing, and support being unable to match a customer's attempt to a BankOne instruction.

As a stopgap, mobile will keep a small local record of each unresolved transfer on the device. That record can't survive a reinstall or a device change, and it can't prove what Core or BankOne did. Only Core can.

## What Core documents today (Swagger, 12 November 2026)

| Route | Relevant behavior |
| --- | --- |
| `POST /me/{intrabank\|interbank}/transfers/initiate` | Amount is a **naira decimal string** (`"1500.50"`). Returns `reference`, `requiredChecks` and `expiresAt`. No idempotency key. |
| `POST …/{reference}/pin/verify`, `…/otp/verify`, `…/otp/resend`, `…/liveness/verify` | Every check is keyed by the initiation `reference`. |
| `POST …/{reference}/finalize` | 400 checks incomplete; 403 restricted, locked or expired; 404 not found; 409 similar transfer within 60 s **or** already processing; 422 bank declined; interbank 500 "BankOne could not be reached or timed out — requery before retrying". With liveness, finalize requires a User Service reconfirmation "for this withdrawal and session". |
| `POST /me/intrabank/transfers/{retrievalReference}/requery`, `POST /me/interbank/transfers/{reference}/requery` | Live CBS status by tracking reference. |
| `GET /me/interbank/transfers/{reference}/status` | Status by "the reference returned in the original transfer's response". No intrabank equivalent. |
| `GET /me/transfers/{reference}/identity-context` | Liveness context, keyed by the initiation `reference`. |

## Requested contract

**Principle: the initiation `reference` is the attempt's identity.** Keep every existing route and its `{reference}`. The PIN, OTP and liveness routes, `identity-context`, and the User Service reconfirmation's `withdrawalReference` all bind to it already, so a new `attemptId` would break liveness. Add the following:

| Change | Behavior |
| --- | --- |
| `clientRequestId` on both `initiate` routes | A UUID v4 the app generates and stores before sending. Enforced unique on `(customerId, clientRequestId)`. The same ID with the same canonical payload returns the existing attempt, with the same `reference` and current state. The same ID with a different payload returns 409 `IDEMPOTENCY_CONFLICT`. |
| Idempotent `…/{reference}/finalize` | Core atomically records that finalize was requested **before** dispatching. A repeated or concurrent call returns the attempt's current state and never creates a second BankOne instruction. Split today's 409 into typed codes: `ALREADY_FINALIZING` (with state) and `POSSIBLE_DUPLICATE_UNRESOLVED` (below). |
| `GET /me/transfers/by-client-request/{clientRequestId}` | Read-only. Finds an attempt when the initiate or finalize reply was lost. Returns the attempt body below. It never initiates or sends money. |
| `GET /me/transfers/{reference}` | Read-only status of a known attempt, for both kinds, including before any tracking reference exists. |
| `GET /me/transfers?state=unresolved` | Paginated, scoped to the customer. Returns attempts in `finalizing`, `processing` or `reconciliation_required`, for recovery after a reinstall or on another device. Pre-finalize attempts are left out because no money can have moved. |
| `POST …/{reference}/cancel` | Valid only in `awaiting_checks` or `ready_to_finalize`; moves the attempt to `cancelled`. Lets a customer drop an abandoned attempt so it never blocks a new transfer. |

**Attempt body:** `reference`, `kind`, `state`, `stateVersion` (strictly increasing per attempt), `updatedAt`, `serverTime`, `amount` (naira decimal string, same as initiate), masked recipient, `retrievalReference` / `transactionReference` once known, and a customer-safe `supportReference`. No internal provider errors and no BVN or identity fields.

**States and how the app will read them:**

| Core state | Meaning | App's `CoreLiveState` |
| --- | --- | --- |
| `awaiting_checks`, `ready_to_finalize` | Not finalized; no money moved | none (pre-finalize) |
| `cancelled`, `expired_unfinalized` | Never finalized; no money moved | none (no money moved) |
| `finalizing`, `processing`, `reconciliation_required` | Money may be moving | `pending` |
| `completed` | Debited and delivered | `completed` |
| `failed_no_debit` | Core can **prove** that no instruction was accepted | `failed` |
| `reversed` | Debited, then returned | `reversed` |

Terminal states never regress, with one exception: `completed` may later become `reversed`. The app already enforces the same rule on live requery results. Core must not issue `expired_unfinalized` once dispatch has begun. An attempt whose expiry passes mid-dispatch stays `finalizing` or moves to `reconciliation_required`.

## Duplicate protection

A new `clientRequestId` alone doesn't stop a customer from repeating the same transfer. If an attempt by the same customer with the same kind, destination and amount is in `finalizing`, `processing` or `reconciliation_required`, initiate returns 409 `POSSIBLE_DUPLICATE_UNRESOLVED` with that attempt's `reference`, and creates nothing.

Pre-finalize attempts never trigger this. An abandoned PIN sheet must not block the customer, and that is what `cancel` and expiry are for.

## Dispatch and reconciliation

- Keep one durable dispatch record per attempt, with a unique BankOne correlation ID. Write it before the BankOne call.
- When a BankOne reply is lost, reconcile against BankOne before any retry. If BankOne can't deduplicate by correlation ID, Core can't promise exactly-once delivery. It must still promise never to create a second instruction while the first might have succeeded.
- Document the maximum time an attempt can spend in reconciliation, the support escalation path when that SLA is breached, and how long attempts stay queryable. Retention must outlast BankOne settlement and the customer dispute window.

## What Core should prove before mobile builds on it

- Retrying with the same `clientRequestId` and payload returns the same `reference`; a changed payload gets `IDEMPOTENCY_CONFLICT`.
- `by-client-request` finds the attempt after a lost initiate reply, and after a lost finalize reply before any tracking reference exists.
- Concurrent and repeated finalize calls produce one BankOne instruction and one debit.
- Crashing or timing out at each durable boundary produces no second instruction. The boundaries are: initiation insert, finalize intent, dispatch record, BankOne acceptance, and reply serialization.
- Another customer can't read, list or cancel the attempt, whether by `reference` or by `clientRequestId`.
- An attempt whose expiry passes after dispatch is never reported as `expired_unfinalized`.
- A late or out-of-order BankOne status never moves a terminal state backwards, except `completed` to `reversed`.

## Decisions Core needs to make

1. Which team owns this contract, persistence, and BankOne reconciliation?
2. Can BankOne deduplicate by a stable correlation ID, or must Core rely on reading status before any retry?
3. What evidence proves `failed_no_debit` and `expired_unfinalized` once dispatch has begun?
4. The reconciliation SLA, the escalation path, and the retention period.
5. Are PIN, OTP and liveness approvals tied to the session? Liveness is ("for this withdrawal and session"). If they are, an attempt restored in a new session can only be cancelled, not finalized, and mobile will treat it that way.
6. Product: for a genuine repeat payment (same recipient and amount while the first is still `processing`), should Core offer an explicit `confirmDuplicate` override, or block until the first transfer reaches a terminal state?
7. Does interbank `GET {reference}/status` accept the initiation `reference`? Will intrabank get an equivalent? Mobile is testing interbank on staging, but only Core can confirm it.

## Release criterion

For each transfer kind separately: a lost reply at any network boundary, followed by a restart, reinstall or device change, must reveal the same `reference`. Retried or concurrent calls must never produce a second debit. The app shows `pending` until Core reports a terminal state, and support can trace a long-running attempt by `supportReference`. Production transfer flags stay off until Core and mobile both sign off on this for that kind.
