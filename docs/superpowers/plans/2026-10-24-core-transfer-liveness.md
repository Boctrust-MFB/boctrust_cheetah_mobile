# Core Transfer Liveness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: Superseded** by `docs/superpowers/plans/2026-10-30-transaction-liveness.md` (30 October 2026). Do not execute. The one item still needed, declaring the routes the transfer flow calls in each transfer capability, moved to the new plan for the User Service reconfirmation routes. Core's `{reference}/liveness/verify` is optional (finalize performs the same check), so its routes and service method are not built.

**Goal:** Prepare for Core-required liveness checks in BocTrust and interbank transfer authorization, without changing how current PIN and PIN+OTP transfers finalize.

**Architecture:** Declare the two Core liveness-completion routes and add one service method that records completion. Nothing calls it until the deferred work lands.

**Tech Stack:** Flutter, Dart, Riverpod, Dio, existing Core transfer service.

**Spec:** Core Swagger UI, Customer Intrabank and Customer Interbank (Mobile), `POST /api/v1/me/{intrabank|interbank}/transfers/{reference}/liveness/verify`: https://core-dev-api.centurysoftware.dev/api/v1/docs/

## Global Constraints

- Both endpoints take only the `reference` path parameter (12 lowercase hex characters, `^[a-f0-9]{12}$`) and no request body.
- Core describes the endpoint as marking liveness complete after the liveness check passes. It accepts no selfie, template, or liveness payload, and it does not move money.
- The `200` reply is `TransferCheckProgressResponse` (`reference`, `requiredChecks`, `completedChecks`, `pendingChecks`), parsed by the existing `CoreCheckProgress`.
- Core documents `400` (liveness not required, or PIN/OTP not done), `403` (initiation expired), `404` (no pending transfer), and `409` (liveness already recorded). Each is a stop; a `409` documents no progress body and is never treated as success. Never retry automatically.
- Do not change `finalizeTransfer`, `CoreTransferInitiation.supported`, `coreCheckProgressContradicts`, or the attempt provider in this plan.
- Keep transfer capabilities staging-only.
- **Tests: none.** The method has no caller and moves no money; existing transfer tests must keep passing unchanged.

---

### Task 1: Register the liveness routes in Core and capabilities

**Files:**
- Modify: `lib/app/core_api_endpoints.dart`
- Modify: `lib/app/feature_capability.dart`

- [ ] Add `intrabankTransferLivenessVerify(String reference)` and its template, and the matching interbank builder/template, beside each transfer's PIN/OTP paths. Encode the reference with `Uri.encodeComponent` like the sibling paths.
- [ ] Add `(backend: ApiBackend.core, method: 'POST', path: <liveness template>)` to `boctrustTransfers` and `interbankTransfers`; keep their staging-only requirements.
- [ ] Run `flutter test test/feature_capability_test.dart`; fix only an existing assertion that lists exact transfer operations.

### Task 2: Add the Core liveness completion service method

**Files:**
- Modify: `lib/module/core_banking/service/core_transfer_service.dart`

- [ ] Add `CoreTransferService.completeTransferLiveness(CoreTransferKind kind, CoreTransferInitiation initiation) -> Future<NotifierState<CoreCheckProgress>>`; choose the route by kind and POST a null body.
- [ ] Before HTTP, require Core configuration, `liveness` in `initiation.checks`, and a non-expired initiation.
- [ ] Parse the reply with `CoreCheckProgress.fromJson`, and reject a `reference` that does not match the initiation. Return Core's error message for `400`/`403`/`404`/`409` as failures.
- [ ] Run `flutter test test/core_transfer_staged_service_test.dart` and `flutter analyze`.

---

## Deferred: resume when a transfer liveness provider is approved

Prerequisite: the product/backend owner names the bank-approved liveness provider, its capture flow, and its verified-success signal. Device Face ID/Touch ID approval is not proof of liveness, and the Tier 1 Smile ID KYC job is not a transfer-purpose check; neither may stand in.

When unblocked, write a fresh plan covering:

- `CoreTransferPhase.awaitingLiveness` / `verifyingLiveness`, and accepting a liveness requirement in `CoreTransferInitiation.supported` and `coreCheckProgressContradicts` (liveness pending only after PIN/OTP, only when initiation required it).
- Running the provider after PIN/OTP succeeds, then calling `completeTransferLiveness`, then finalize only when Core's progress shows no pending checks.
- Requiring complete `CoreCheckProgress` before `finalizeTransfer` for every transfer kind, with existing PIN and PIN+OTP flows updated to carry it.
- The UI step between PIN/OTP and finalize, with cancel/failure/expiry showing that no transfer was sent.
- One test: finalize is refused while progress still has pending checks.
- Staging verification of both transfer kinds end to end, then lifting staging-only.
