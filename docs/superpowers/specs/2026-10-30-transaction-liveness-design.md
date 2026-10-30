# Transaction liveness design

Date: 30 October 2026, revised the same day after review. Status: approved for implementation. Sources: [User Service Swagger](https://user-dev-api.centurysoftware.dev/api/v1/docs/) and [Core Service Swagger](https://core-dev-api.centurysoftware.dev/api/v1/docs/), read on this date. The Swagger documents settle contract questions; staging observations refine customer copy but are not preconditions for building.

## Intent

Complete a BOCTRUST or other-bank transfer when Core's initiation asks for `liveness`, using a fresh identity reconfirmation bound to that pending transfer. Keep the current PIN, optional OTP, one-shot finalize, result, and live requery behavior. Existing transfers that do not ask for liveness are unchanged.

## When liveness applies

The threshold is dynamic and set from the admin; the User Service seed value (strictly above NGN 5 million) is only a default. The app never compares amounts. Core's initiate reply decides: liveness applies exactly when `requiredChecks` contains `liveness`. For staging tests, an admin lowers the threshold so a controlled small transfer asks for liveness.

## Chosen flow

Review → Core initiate → PIN verify → OTP verify if required → identity consent → User Service reconfirmation initiate with the Core initiation `reference` → backend-selected provider capture → User Service outcome read until `verified` → Core bodyless finalize **once**, before Core's initiation `expiresAt` and the reconfirmation's `validUntil` → existing accepted/processing/completed/failed/unconfirmed result and requery.

Core's `{reference}/liveness/verify` is optional; finalize repeats the same check, so the app goes straight to finalize. The client never sets a verified flag and never treats an SDK callback, a capture screen closing, or `comparing` as approval.

Core's `GET /me/transfers/{reference}/identity-context` and the reference/session binding are User Service ↔ Core concerns. The app does not call or verify them.

## Contract (from Swagger)

- `POST /users/me/identity-reconfirmations/initiate`, body `{withdrawalReference, consent: {granted: true, grantedAt, noticeLanguage, privacyPolicyUrl}}`. `withdrawalReference` is the Core initiation reference. `grantedAt` is the real consent time in UTC, `noticeLanguage` is `EN`, `privacyPolicyUrl` is `sitePageUri('privacy')`. Responses 200, 400, 401, 403, 404, 429, 502. A 200 may resume an existing challenge.
- `GET /users/me/identity-reconfirmations/{id}` is the authoritative outcome. Responses 200, 401, 404.
- `ReconfirmationData` (shared by both): `verificationId` (UUID), `status` (`pending`, `comparing`, `verified`, `failed`, `expired`, `superseded`), `provider` (`smile_id`, `dojah`), `method`, `withdrawalReference`, `expiresAt`, `verifiedAt`, `validUntil`, `authorizedAt`, `failureReason`. Pending challenges also carry capture data; for Dojah, `metadata.reference` is the nonce to forward unchanged in the Dojah SDK metadata. Errors are `ReconfirmationError` with a `code`.
- Dojah delivers its signed result to the backend (`/users/identity-reconfirmations/dojah/webhook` or the existing `/users/kyc/dojah/webhook` with `metadata.reference`). The app never submits a Dojah result.
- Smile submits through `POST /users/me/identity-reconfirmations/{id}/submit`, which requires `selfieImage`, 6–8 `livenessImages`, `encryptedPackage`, `packageNonce`, `packageTag`, `sourceSdk`, and `sourceSdkVersion`.
- Core intrabank and interbank finalize are bodyless and check for a successful, unexpired proof for this transfer and session; missing or expired proof returns 403, which Core also uses for restrictions and expiry.

## Providers

**Dojah: supported.** Reuse the existing `DojahCaptureScreen` / `NativeDojahGateway`, which already forwards `metadata.reference` on Android and iOS, with the reconfirmation's `metadata.reference` as the reference. The widget ID comes from `DOJAH_TRANSACTION_WIDGET_ID` and falls back to the BVN widget (`DOJAH_SELFIE_WIDGET_ID`) when unset. Confirm the right widget during testing.

**Smile ID: deferred, not upgraded.** The submit endpoint requires `encryptedPackage`, `packageNonce`, and `packageTag`. The app's `smile_id` 11.2.12 does not produce them, and no Flutter v12 exists (pub.dev latest is 11.2.14, checked 30 October 2026). An upgrade would also put Tier 1 KYC capture at risk. When User Service selects `smile_id`, the app stops safely without capture: no money moves, and the customer sees that this check can't be done in the app yet. The app never substitutes Dojah. Revisit when a Smile Flutter SDK emits the capture-only package.

## Customer outcome and safety

- After PIN/OTP, show an identity step that explains the transfer-bound check and asks for consent; initiate is sent only after consent.
- After Dojah capture, show a pending state with **Check again** and bounded foreground polling. Only `verified` with a matching `withdrawalReference` and unexpired `validUntil` and Core `expiresAt` triggers finalize, once.
- `failed`, `expired`, `superseded`, a mismatched reference, or an unknown value ends the attempt with no money moved; the customer starts a new transfer (a new Core initiation). Initiate 429 or 502 also ends the attempt with copy to try later.
- Leaving the screen keeps a pending identity attempt visible from either transfer entry and stops polling. Re-entry re-reads the status for the same verification ID before finalizing. Explicit cancel, logout, account change, or expiry clears it, and late replies are dropped.
- A finalize 403 on a liveness transfer shows non-specific copy (expired, not confirmed, or restricted), never "account locked". A lost finalize reply stays unconfirmed and is never resent.
- Never log images, nonces, tokens, callback URLs, or consent data. Reconfirmation requests use the existing privacy-sensitive path marker.

## Acceptance

- Dojah × BOCTRUST and Dojah × other bank reach `verified` and one finalize on a physical Android and iOS device, with PIN-only and PIN+OTP initiations, using controlled small transfers after the admin lowers the threshold.
- No finalize happens on pending, comparing, failed, expired, superseded, mismatched, cancelled, or expired-window proof.
- A `smile_id` selection stops safely with no capture and no finalize.
- Successful finalize continues through the existing result and live requery, with the amount debited once.
- Non-liveness transfers are unchanged.
- No new activation gate for now; the feature rides the existing staging-only transfer capabilities.
- Tests: the minimum necessary, which is one provider test guarding the finalize gate.
