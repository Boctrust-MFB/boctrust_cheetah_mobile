# Savings Plan Core Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire Core's savings-plan product catalogue, quotes, first-deposit amount, and soft-delete operation into the savings experience.

**Architecture:** Extend the existing Core savings service, models, providers, and capability map with product catalogue and quote reads and plan deletion. Keep the current product-grouped plan reads because the product screens and account tiles need their account metadata. Use the quote for the selected duration as the source of the rate, maturity date, and first-deposit bounds, and send the first deposit as `amount` on create. Keep deletion explicitly confirmed and Core-authoritative.

**Tech Stack:** Flutter, Dart, Riverpod, Dio, existing `ApiService` response handling and feature capability system.

**Spec:** Core Swagger UI, Customer Savings Plans (Mobile): `GET /api/v1/me/savings-products`, `GET /api/v1/me/savings-products/{productCode}/quote`, `POST /api/v1/me/savings-plans` (`CreateSavingsPlanRequest`), and `DELETE /api/v1/me/savings-plans/{planId}`. `GET /api/v1/me/savings-plans/flat` is out of scope: https://core-dev-api.centurysoftware.dev/api/v1/docs/

## Global Constraints

- **Tenors are bands, not a closed list.** Any `tenorDays` between the product's `minTenorDays` and `maxTenorDays` (never more than 365) is valid; Core documents that a length between configured tenors gets the rate of the longest tenor it reaches. The `tenors` array describes rate and minimum-deposit bands.
- **`minAmount` is the smallest first deposit** for that duration (Core: "Smallest first deposit allowed for this duration"). `maxAmount` is null when there is no maximum.
- **The quote is authoritative for the selected duration.** It accepts exactly one of `tenorDays` or `endDate` and uses the same rules as creation, so its rate and minimum are what creation applies. A `400` means the duration is out of range or neither/both inputs were sent; a `404` means an unknown or inactive product.
- **Create sends `amount`** — the first deposit, moved from Boc Flex as soon as the plan is created. It must be at least the quote's `minAmount` and at most its `maxAmount` when set. Fixed Deposit sends the principal the customer typed. SmartSave sends the opening deposit shown in its confirmation (the quote's `minAmount`), so the amount debited is the amount the customer confirmed.
- **SmartSave `targetAmount` can't exceed the tenor's maximum** (Core: "Can't be more than the maximum for the tenor"). Validate it against the quote's `maxAmount` when set, and keep the existing rule that the target exceeds the opening deposit.
- Recurring contributions have no Core-published limit; keep `minimumPeriodicSavingsNaira` and `savingsPlanMaxKobo` as the UI floor and ceiling.
- Create sends exactly one of `tenorDays` (a month preset, from the quote) or `endDate` (a custom maturity date, so the plan matures on the date shown); never rate, fee, or quote dates. Fixed Deposit never sends `saveFrequency`/`recurringAmount` (target savings only).
- Delete is a soft delete: only a plan with no money in it and no interest payout in progress can be deleted; an open plan is cancelled; the plan then no longer shows for the customer. Core documents `200`, `404` (not the caller's plan), and `409` (money remains or interest is still being paid). The delete has no request body; `planId` is one encoded path segment.
- Never liquidate or withdraw as part of deletion.
- The `200` delete response's `status` is one of `matured`, `liquidated`, `cancelled`; do not drive UI from it. Use the confirmed success plus a refreshed list as the source of truth.
- Do not automatically retry a delete whose outcome is unknown; reconcile by refreshing Core data.
- Catalogue and quote are separate from `GET /me/bank-products`. Keep the grouped `/me/savings-plans` as the only plan-list source; do not call `/flat`.
- Keep all new operations staging-only until verified against staging.
- **Tests: one.** The delete action sends exactly one DELETE after confirmation and never calls liquidate. Update existing tests only where the changed create payload or tenor rules break them; add no others.

---

### Task 1: Register savings catalogue and plan operation contracts

**Files:**
- Modify: `lib/app/core_api_endpoints.dart`
- Modify: `lib/app/feature_capability.dart`

- [ ] Add `savingsProducts`, `savingsProductQuote(String productCode)`, `savingsProductQuoteTemplate`, `savingsPlanDelete(String planId)`, and `savingsPlanDeleteTemplate` beside the existing savings paths. Encode `productCode` and `planId` with `Uri.encodeComponent`.
- [ ] Add `GET savingsProducts` and `GET savingsProductQuoteTemplate` to `smartSaveCreate` and `fixedDepositCreate` alongside their existing `POST savingsPlans`. Leave `savingsPlansView` on grouped list/detail/accrual reads.
- [ ] Add a `FeatureCapability.savingsPlanDelete` enum value and a staging-only requirement containing only `DELETE savingsPlanDeleteTemplate`. Do not add deletion to `moneyMoving`.
- [ ] Run `flutter test test/feature_capability_test.dart`; fix any existing assertion the new operations break.

### Task 2: Model savings products, tenors, quotes, and the create amount

**Files:**
- Modify: `lib/module/savings/model/savings_plan_models.dart`

- [ ] Add `SavingsPlanTenor` (`tenorDays`, `interestRatePercent`, `minAmount`, optional `maxAmount`) and `SavingsPlanProduct` (`productCode`, `productName`, optional `description`, `planType`, `earlyWithdrawalFeePercent`, optional `minTenorDays`/`maxTenorDays`, `tenors`). Amounts and rates are Core decimal strings.
- [ ] Add `SavingsPlanProduct.listFromJson(Object? json)`: reject a non-list response, drop malformed rows individually, keep valid rows in Core order.
- [ ] Add `SavingsPlanQuote` (`productCode`, `productName`, `tenorDays`, `startDate`, `endDate`, `interestRatePercent`, `minAmount`, optional `maxAmount`, `earlyWithdrawalFeePercent`). Throw `FormatException` on missing or malformed required fields.
- [ ] Remove `tenorDaysForMonths`, `minimumSavingsTenorDays`, `maximumSavingsTenorDays`, and `openingMinimumNaira` as sources of Core rules. Month presets are presentation only: offer a preset only when its day count falls within the product's `minTenorDays`–`maxTenorDays`.
- [ ] Add `amount` to `CreateSavingsPlanRequest` and its `toJson`. In `SavingsPlanDraft.toCreateRequest`, take the selected `SavingsPlanQuote`: Fixed sends the typed principal as `amount`; SmartSave sends the quote's `minAmount` as `amount`. Both send the quote's `tenorDays`. Return null if the amount is below `minAmount`, above a set `maxAmount`, or a SmartSave target exceeds a set `maxAmount` or does not exceed the opening deposit.
- [ ] Never put rate, fee, or quote dates in the create body; send `endDate` only for a custom maturity date.

### Task 3: Add catalogue and quote service/provider wiring

**Files:**
- Modify: `lib/module/savings/service/core_savings_plan_service.dart`
- Modify: `lib/module/savings/provider/savings_plan_provider.dart`

- [ ] Add `CoreSavingsPlanService.getSavingsProducts() -> Future<NotifierState<List<SavingsPlanProduct>>>` using `ApiService.getData` and `CoreApiEndpoints.savingsProducts`.
- [ ] Add `CoreSavingsPlanService.quoteSavingsProduct(String productCode, {int? tenorDays, DateTime? endDate}) -> Future<NotifierState<SavingsPlanQuote>>`. Return a local error before HTTP unless exactly one input is supplied; send `endDate` as `YYYY-MM-DD` and only that query key.
- [ ] Add `savingsPlanProductsProvider` and a `savingsPlanQuoteProvider` family keyed by product code and the selected duration. Both are auto-dispose and watch `authSessionProvider`, like the existing savings providers.
- [ ] Invalidate only grouped plans after create/fund/liquidate/delete; the catalogue needs no mutation refresh.

### Task 4: Wire catalogue, quote, and amount into the creation wizard

**Files:**
- Modify: `lib/module/savings/screens/savings_plan_screens.dart`
- Modify: `lib/module/savings/screens/savings_screens.dart` only if product tiles need published rate/term values

- [ ] Load the catalogue and match the row for `widget.type.coreCode`; show the unavailable state when Core has no row.
- [ ] Build the schedule step from the product's tenor bounds: month presets that fall in range plus the existing custom date, limited to `minTenorDays`–`maxTenorDays`. Replace the copy that names hardcoded day minimums with the product's bounds.
- [ ] Request a quote whenever the duration changes (`tenorDays` for a preset, `endDate` for a custom date). Show loading, Core's `400`/`404` message, and retry. Display the quote's maturity date, rate, early-withdrawal fee, and first-deposit minimum/maximum.
- [ ] Block continuing past the schedule step until a quote has loaded. Validate the Fixed principal against the quote's `minAmount`/`maxAmount`; validate the SmartSave target against `maxAmount` and the opening deposit.
- [ ] Replace `_openingAmount` with the quote's `minAmount` for SmartSave and the typed principal for Fixed, so the confirmation shows the exact `amount` that will be sent and debited from Boc Flex.
- [ ] Leave `/me/bank-products` and grouped `/me/savings-plans` untouched.

### Task 5: Parse Core's delete response and call the endpoint

**Files:**
- Modify: `lib/module/savings/model/savings_plan_models.dart`
- Modify: `lib/module/savings/service/core_savings_plan_service.dart`

- [ ] Add `SavingsPlanDeleteResult.fromJson(Object? value)`: require `planId`; parse optional `status` (`matured`, `liquidated`, `cancelled`) and optional ISO-8601 `deletedAt`.
- [ ] Add `CoreSavingsPlanService.deletePlan(String planId) -> Future<NotifierState<SavingsPlanDeleteResult>>` via `ApiService.deleteData`, no body, encoded path, no retry. Preserve Core's `404`/`409` messages.

### Task 6: Add a serialized delete action state

**Files:**
- Modify: `lib/module/savings/provider/savings_plan_action_provider.dart`
- Modify: `test/core_savings_plan_test.dart`

- [ ] Add `SavingsPlanAction.delete` and `SavingsPlanDeleteResult? deleteResult` to `SavingsPlanActionState`; keep the existing `result` used by funding/liquidation.
- [ ] Add `SavingsPlanActionNotifier.deletePlan(String planId)` through the same one-action-at-a-time guard. Skip the Flex debit gate and never call liquidation; Core's `409` decides eligibility.
- [ ] On success, invalidate `savingsPlanDetailProvider(planId)` and grouped `savingsPlansProvider`; do not refresh Flex balance or history. On unknown outcome, invalidate the same plan data and never resend.
- [ ] Add the plan's one test: `delete sends one DELETE and never liquidates` — the action sends exactly one `DELETE` to the encoded plan path with a null body, sends no request to the liquidate path, and does not resend after an unknown outcome.
- [ ] Run `flutter test test/core_savings_plan_test.dart`.

### Task 7: Expose a confirmed delete in the plan detail UI

**Files:**
- Modify: `lib/module/savings/screens/savings_plan_screens.dart`

- [ ] Add a `Delete plan` menu item only when `FeatureCapability.savingsPlanDelete` is available and the plan detail's `principalAmount` reads as zero. Keep the existing `Withdraw` item routed only to liquidation.
- [ ] Show a confirmation dialog stating that a plan can only be deleted with no money in it and no interest still being paid; cancelling sends no request.
- [ ] On success, return to the product list. On `409`, keep detail open with Core's message; on `404`, show unavailable and refresh; on unknown, say the result could not be confirmed and refresh without retrying.

### Task 8: Verify the savings integration

- [ ] Run `flutter test test/feature_capability_test.dart test/core_savings_plan_test.dart test/savings_provider_test.dart test/savings_plans_ui_test.dart test/savings_live_ui_test.dart`.
- [ ] Run `flutter analyze`.
- [ ] On staging: create a Fixed Deposit and a SmartSave with a preset and a custom date, confirming the quoted rate/maturity match the created plan and Boc Flex is debited exactly `amount`; then delete an empty plan and confirm a funded plan returns `409` with no withdrawal.
