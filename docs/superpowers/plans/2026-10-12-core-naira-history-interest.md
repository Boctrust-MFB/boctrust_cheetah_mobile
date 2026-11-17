# Core Naira Amounts, Account History and Interest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the new customer mobile endpoints — BocFlex interest, BocFlex and savings-plan daily interest history — and the contract changes they arrive with: Naira amounts everywhere, typed and paginated account history, and early-withdrawal interest.

**Architecture:** One shared Naira reader and one shared page model in `core_banking/model`. Each endpoint gets a typed model, a service method on the service that already owns its area (`CoreAccountService`, `CoreSavingsPlanService`, a new `CoreFlexInterestService`), a session-scoped autoDispose provider, and a staging-only capability. UI extends existing screens: account detail (history rows), Flex screen (interest card), plan detail (interest history and withdrawal terms), and one shared interest-history screen.

**Tech Stack:** Flutter, Dart, Riverpod, Dio, existing `ApiService`/`NotifierState` and widget/HTTP-adapter test harness.

**Spec:** [Live Core Swagger](https://core-dev-api.centurysoftware.dev/api/v1/docs/), swagger-ui-init SHA-256 `f54d3ae9…`, fetched 12 October 2026 — the single source of truth. Compared with `4c143b37…` (the staged-verification branch's contract): every amount became Naira; `GET /me/bocflex/interest`, `GET /me/bocflex/interest/accruals` and `GET /me/savings-plans/{planId}/accruals` were added; savings plans gained `accruedInterest` and `earlyWithdrawalFeePercent`; liquidation now pays interest minus a fee. `GET /me/bank-accounts/{n}/transactions` already uses `YYYY-MM-DD` and `page`/`pageSize` (changed in `4c143b37…`; the app still sends `DD-MM-YYYY` and `numberOfItems`). Admin, internal and interest-job routes (`/savings-products*`, `/bocflex/settings`, `/bocflex/accruals/run`, `/bocflex/interest/credit`, `/savings-plans/accruals/run`, `/savings-plans/pending-interest-payouts`, `/savings-plans/{planId}/interest-payout/retry`) are out of scope: no bearer security.

## Global Constraints

- Build on `feat/core-staged-verification` (it holds the routes Task 1 corrects). Re-fetch the Swagger before coding and before staging; if its SHA-256 differs from `f54d3ae9…`, re-diff before continuing.
- Every amount this plan touches is a **Naira decimal string** per the Swagger (`"1500.50"`): transfer initiate `amount`, limit inputs and all limit values, savings plan/product/event/action amounts, history `amount`/`balance`, interest values. Never multiply or divide by 100 when reading them.
- Outgoing amounts stay integer Kobo inside the app (`amountKobo`, `parseNairaToKobo`) and are converted once, exactly, with `koboToNaira` at the request boundary.
- History, Flex interest and accruals are read-only and staging-only: `coreAccountHistory`, new `flexInterestView`, and `savingsPlansView` (which gains the plan-accruals read).
- Logging: these requests and replies are logged in full on staging (product decision, 10 October); no `privacySensitivePathKey`. Leave logger redaction lists unchanged.
- Tests are minimal and strictly necessary (user preference); each task's tests pin its own behaviour.

## Review Focus

- A history row's direction comes only from `type` (`credit`/`debit`); an `amount` string with a sign or unexpected format must not flip it or show a wrong sign. (Task 3 test `direction comes from type, not the amount text`.)
- A `reversed: true` row must read as reversed, not as an ordinary credit or debit. (Task 4 test `a reversed row says so`.)
- "Show more" must not duplicate a row when a new transaction shifts later pages; rows are de-duplicated by `id`. (Task 3 test `a later page never repeats a row`.)
- A Naira value such as `"1500.50"` must display as ₦1,500.50 everywhere — no Kobo reading left behind. (Task 1 test `amounts read as Naira`.)
- A Flex customer whose `ratePercent` is null, or a customer with no Flex account (404), must see no rate rather than "0%" or an error banner. (Task 5 test `no rate and no Flex account are shown plainly`.)

---

### Task 1: Read and send Naira amounts

**Files:**
- Modify: `lib/module/core_banking/model/core_json.dart` (add `coreNaira`)
- Modify: `lib/module/core_banking/model/intrabank_models.dart`, `lib/module/core_banking/model/interbank_models.dart` (`toJson` amount)
- Modify: `lib/module/account/model/transaction_limit_models.dart` (`_naira` → `coreNaira`)
- Modify: `lib/module/account/screens/transaction_limits_screen.dart` (send `koboToNaira(kobo)`)
- Modify: `lib/module/savings/model/savings_plan_models.dart` (`_naira` → `coreNaira`)
- Test: `test/core_transfer_staged_service_test.dart`, `test/core_payments_models_test.dart`, `test/transaction_limits_test.dart`, `test/core_savings_plan_test.dart`, `test/savings_plans_ui_test.dart`

**Interfaces:**
- Produces: `String? coreNaira(Object? value)` in `core_json.dart` — a trimmed non-negative decimal string (`^\d+(\.\d+)?$`) or a finite non-negative JSON number, returned as a decimal string; anything else null. Used by Tasks 2–6.

- [ ] **Step 1: Change the tests to the Naira contract**

`test/core_transfer_staged_service_test.dart` → `initiate sends the reviewed fields, a naira amount and no PIN`: `amountKobo: '165000'` sends `'amount': '1650.00'`; `amountKobo: '1'` sends `'amount': '0.01'`; the ceiling test expects `'25000000.00'` for `'2500000000'`.
`test/core_payments_models_test.dart`: BOCTRUST draft `amountKobo: '1000'` → `'amount': '10.00'`; interbank `'5000'` → `'50.00'`.
`test/transaction_limits_test.dart` → `reads Naira limits` (rename `reads Kobo limits as Naira…`): `businessSingleTransferLimit: '500000.00'` → `singleTransfer.business == '500000.00'`; `effectiveDailyTransferLimit: '2000000'` → `'2000000'`; `_tier1` fixture becomes `'50000.00'`, `'10000.00'`, `'200000.00'`; the edit test expects the draft `TransactionLimitDraft(dailyTransferLimit: '1000.00')`.
`test/core_savings_plan_test.dart` → `amounts read as Naira`: `principalAmount: '5000.00'` → `principal == '5000.00'`, `targetAmount: '100000'` → `'100000'`; the old "unreadable decimal" case becomes `principalAmount: 'abc'` → `principal == null`. Event `amount: '2500.00'` → `'2500.00'`.

- [ ] **Step 2: Run them**

Run: `flutter test --no-pub test/core_transfer_staged_service_test.dart test/core_payments_models_test.dart test/transaction_limits_test.dart test/core_savings_plan_test.dart`
Expected: FAIL on every changed amount expectation.

- [ ] **Step 3: Implement**

Add `coreNaira`. Drafts: `'amount': koboToNaira(amountKobo)`. `TransactionLimits.fromJson` and `SavingsPlan`/`SavingsPlanEvent` use `coreNaira`. Limits screen: send `koboToNaira(kobo)`; compare with the ceiling via `balanceToKobo(limit.business)` as now. Update the Kobo comments in those files and in `feature_capability.dart` (`savingsPlansView`, limits) to Naira.

- [ ] **Step 4: Run the focused tests, then `flutter analyze`**

Expected: PASS; no issues.

- [ ] **Step 5: Commit** — `fix(core): read and send amounts in Naira, as Core now documents`

### Task 2: Early-withdrawal interest on savings plans

**Files:**
- Modify: `lib/module/savings/model/savings_plan_models.dart` (`SavingsPlan`)
- Modify: `lib/module/savings/screens/savings_plan_screens.dart` (`_savingsPlanDetailScreen`, `_withdrawFromPlan`)
- Test: `test/core_savings_plan_test.dart`, `test/savings_plans_ui_test.dart`

**Interfaces:**
- Consumes: `coreNaira` (Task 1).
- Produces: `SavingsPlan.accruedInterest` (`String?`, Naira) and `SavingsPlan.earlyWithdrawalFeePercent` (`String?`, e.g. `'2.5'`).

- [ ] **Step 1: Write the failing tests**

`core_savings_plan_test.dart` → `reads accrued interest and the early-withdrawal fee`: `accruedInterest: '120.40'`, `earlyWithdrawalFeePercent: '2.5'` → those values. `savings_plans_ui_test.dart` → `plan detail shows interest so far`: detail with `accruedInterest: '120.40'` shows `'₦120.40'` beside the label `'Interest so far'`.

- [ ] **Step 2: Run** — `flutter test --no-pub test/core_savings_plan_test.dart test/savings_plans_ui_test.dart` → FAIL (fields missing).

- [ ] **Step 3: Implement**

Add both fields to `SavingsPlan` (props too) and a `(label: 'Interest so far', …)` row on plan detail. Replace the withdraw sheet's early-exit message with: `'Withdrawing early returns your principal and the interest earned so far to Boc Flex Savings, minus a {fee}% early withdrawal fee on that interest.'` (when `earlyWithdrawalFeePercent` is null: `'…minus the early withdrawal fee on that interest.'`). Liquidation itself stays unregistered (`savingsPlanWithdraw`).

- [ ] **Step 4: Run the tests** → PASS.

- [ ] **Step 5: Commit** — `feat(savings): show interest so far and early-withdrawal terms`

### Task 3: Typed, paginated account history transport

**Files:**
- Create: `lib/module/core_banking/model/core_page.dart`
- Modify: `lib/module/core_banking/model/core_account_transactions.dart` (`CoreHistoryRange.window` format, row model)
- Modify: `lib/module/core_banking/service/core_account_service.dart` (`getAccountTransactions`)
- Test: `test/core_account_activity_test.dart`

**Interfaces:**
- Produces:
  - `class CorePage { final int page, pageSize, total, totalPages; bool get hasMore => page < totalPages; static CorePage? tryParse(Object?) }` in `core_page.dart` (reused by Task 6).
  - `enum CoreTransactionType { credit, debit }`.
  - `class CoreAccountTransaction { final String id; final DateTime? date; final CoreTransactionType type; final String amount; final String? balance; final String? narration; final String? reference; final bool reversed; static CoreAccountTransaction? tryParse(Object?) }` — `amount`/`balance` via `coreNaira`; a row without `id`, a known `type` or a readable `amount` is dropped; `coreBankingReference` is not kept.
  - `class CoreTransactionPage { final List<CoreAccountTransaction> rows; final CorePage? page; factory CoreTransactionPage.fromJson(Object?) }`.
  - `CoreHistoryRange.window(DateTime today)` returns `YYYY-MM-DD` strings.
  - `Future<NotifierState<CoreTransactionPage>> getAccountTransactions(String accountNumber, CoreHistoryRange range, {int page = 1, int pageSize = 20, DateTime? today})`.

- [ ] **Step 1: Write the failing tests** (replace `transactions request the documented window and item count`)

`transactions request YYYY-MM-DD dates and a page`: `last30Days` on 2026-10-07, `page: 2` → query `{'fromDate': '2026-09-07', 'toDate': '2026-10-07', 'page': 2, 'pageSize': 20}`.
`rows parse with their documented fields`: `{id:'922223', date:'2026-10-10T20:17:35', type:'debit', amount:'40.38', balance:'1009900.62', narration:'POS', reversed:false}` → `amount == '40.38'`, `type == CoreTransactionType.debit`, `date == DateTime(2026,10,10,20,17,35)`; page `{page:1,pageSize:20,total:45,totalPages:3}` → `hasMore` true.
`direction comes from type, not the amount text`: `type:'credit', amount:'-40.38'` → row dropped (amount unreadable); `type:'refund'` → dropped.
`a later page never repeats a row` lives in Task 4 (provider merge).

- [ ] **Step 2: Run** — `flutter test --no-pub test/core_account_activity_test.dart` → FAIL.

- [ ] **Step 3: Implement** the interfaces above. Keep the 10-digit guard and the 7/30/60-day ranges (within Core's three-month limit).

- [ ] **Step 4: Run the tests** → PASS.

- [ ] **Step 5: Commit** — `feat(core): read typed, paginated account history`

### Task 4: Account history rows with range selection

**Files:**
- Modify: `lib/module/core_banking/provider/core_account_activity_providers.dart`
- Modify: `lib/module/core_banking/screens/bank_account_detail_screen.dart` (`_history`)
- Test: `test/bank_account_detail_test.dart`

**Interfaces:**
- Consumes: Task 3's `getAccountTransactions`, `CoreTransactionPage`, `CoreAccountTransaction`.
- Produces: `final coreAccountHistoryProvider = NotifierProvider.autoDispose.family<CoreAccountHistoryNotifier, NotifierState<CoreAccountHistory>, ({String accountNumber, CoreHistoryRange range})>` where `CoreAccountHistory { List<CoreAccountTransaction> rows; bool hasMore; bool loadingMore; }` and the notifier exposes `Future<void> loadMore()`. Session-scoped (watches `authSessionProvider`).

- [ ] **Step 1: Write the failing tests** (replace the unmapped/empty tests)

`history shows each row with its direction`: rows credit `'5000.00'` "SALARY" and debit `'40.38'` "POS" → texts `'+₦5,000.00'`, `'-₦40.38'`, `'SALARY'`, `'POS'`.
`choosing a range re-reads that range`: tap `'7 days'` → the fake records `CoreHistoryRange.last7Days`.
`a reversed row says so`: `reversed: true` → text `'Reversed'` on that row.
`a later page never repeats a row`: page 1 `[a,b]` (totalPages 2), page 2 `[b,c]`; tap `'Show more'` → rows `a,b,c` once each; `'Show more'` gone.
`empty history is not shown as activity`: keep, text `'No transactions in this period.'`.

- [ ] **Step 2: Run** — `flutter test --no-pub test/bank_account_detail_test.dart` → FAIL.

- [ ] **Step 3: Implement** — range chips `'7 days' | '30 days' | '60 days'` (default 30); one `ListTile` per row (narration or `'Transaction'`, date `d MMM, h:mm a`, signed amount from `type`, `'Reversed'` subtitle when reversed); `'Show more'` when `hasMore`, merging by `id`; existing loading/error/retry states; pull-to-refresh reloads page 1.

- [ ] **Step 4: Run the tests** → PASS.

- [ ] **Step 5: Commit** — `feat(core): show account history rows with a range and paging`

### Task 5: BocFlex interest summary

**Files:**
- Create: `lib/module/savings/model/flex_interest_models.dart`, `lib/module/savings/service/core_flex_interest_service.dart`, `lib/module/savings/provider/flex_interest_provider.dart`
- Modify: `lib/app/core_api_endpoints.dart`, `lib/app/feature_capability.dart`, `lib/module/savings/screens/savings_screens.dart` (`_flexScreen`)
- Test: create `test/flex_interest_test.dart`; modify `test/feature_capability_test.dart`

**Interfaces:**
- Produces:
  - `CoreApiEndpoints.flexInterest = '/me/bocflex/interest'`, `CoreApiEndpoints.flexInterestAccruals = '/me/bocflex/interest/accruals'`.
  - `FeatureCapability.flexInterestView` — staging-only, operations `GET flexInterest`, `GET flexInterestAccruals`.
  - `class FlexInterest { final String? ratePercent; final String? currentMonthAccruedInterest; final String? totalInterestEarned; factory FlexInterest.fromJson(Object?) }` (amounts via `coreNaira`; `accountNumber` not kept).
  - `CoreFlexInterestService.getInterest() -> Future<NotifierState<FlexInterest>>`; `coreFlexInterestServiceProvider`.
  - `final flexInterestProvider = FutureProvider.autoDispose<NotifierState<FlexInterest>>` (watches `authSessionProvider`).

- [ ] **Step 1: Write the failing tests**

`flex_interest_test.dart` → `reads the Flex interest summary`: `{ratePercent:'12.5', currentMonthAccruedInterest:'84.10', totalInterestEarned:'1203.55'}` → those values. `the Flex screen shows interest`: texts `'12.5% p.a.'`, `'₦84.10'` (label `'This month so far'`), `'₦1,203.55'` (label `'Total interest earned'`). `no rate and no Flex account are shown plainly`: `ratePercent: null` → no `'% p.a.'` text; a 404 → no interest card and no error text. `feature_capability_test.dart` → add `flexInterestView` to the staging slices list.

- [ ] **Step 2: Run** — `flutter test --no-pub test/flex_interest_test.dart test/feature_capability_test.dart` → FAIL.

- [ ] **Step 3: Implement** the interfaces; the Flex screen shows an interest card under the balance only when `flexInterestView` is available and the read succeeds, with an `'Interest history'` action (Task 6 route). Other errors show a compact retry card.

- [ ] **Step 4: Run the tests** → PASS.

- [ ] **Step 5: Commit** — `feat(savings): show BocFlex interest`

### Task 6: Daily interest history for Flex and savings plans

**Files:**
- Create: `lib/module/savings/model/interest_accrual_models.dart`, `lib/module/savings/provider/interest_history_provider.dart`, `lib/module/savings/screens/interest_history_screen.dart`
- Modify: `lib/module/savings/service/core_flex_interest_service.dart`, `lib/module/savings/service/core_savings_plan_service.dart`, `lib/app/core_api_endpoints.dart`, `lib/app/feature_capability.dart` (`savingsPlansView` gains `GET savingsPlanAccrualsTemplate`), `lib/app/app_router.dart`, `lib/module/app_flow/route_definitions.dart`, `lib/module/savings/screens/savings_plan_screens.dart` (plan detail action)
- Test: create `test/interest_history_test.dart`

**Interfaces:**
- Consumes: `CorePage` (Task 3), `coreNaira` (Task 1), `CoreFlexInterestService` (Task 5).
- Produces:
  - `CoreApiEndpoints.savingsPlanAccruals(String planId)` and `savingsPlanAccrualsTemplate = '$savingsPlans/{planId}/accruals'`.
  - `class InterestAccrual { final DateTime? date; final String? base; final String? ratePercent; final String? interest; final String? cumulativeInterest; static InterestAccrual? tryParse(Object?, {required String baseKey}) }` — `base` is Flex `balance` or plan `principalAmount`.
  - `class InterestAccrualPage { final List<InterestAccrual> accruals; final CorePage? page; }`.
  - `CoreFlexInterestService.getAccruals({int page = 1, int pageSize = 30})` and `CoreSavingsPlanService.getPlanAccruals(String planId, {int page = 1, int pageSize = 30})`, both `-> Future<NotifierState<InterestAccrualPage>>`.
  - `sealed class InterestSource { flex(); plan(String planId) }` and `final interestHistoryProvider = NotifierProvider.autoDispose.family<InterestHistoryNotifier, NotifierState<List<InterestAccrual>>, InterestSource>` with `loadMore()` and `bool hasMore`.
  - `AppRoutes.interestHistory = '/savings/interest-history'`, opened with `AppRouteArguments(entityId: planId)` for a plan, without for Flex.

- [ ] **Step 1: Write the failing tests**

`plan accruals use the encoded plan id and a page`: `getPlanAccruals('p/1', page: 2)` → path `/me/savings-plans/p%2F1/accruals`, query `{'page': 2, 'pageSize': 30}`.
`accruals read with their documented fields`: Flex row `{date:'2026-10-11', balance:'100000.00', ratePercent:'12.5', interest:'34.25', cumulativeInterest:'342.50'}` → `base == '100000.00'`, `interest == '34.25'`.
`the history screen lists days and pages on`: two accruals then `'Show more'` loads page 2 → texts `'₦34.25'`, `'11 Oct 2026'`, and the second page's day.
`a plan that is no longer available says so`: 404 → `'This plan is no longer available.'`.

- [ ] **Step 2: Run** — `flutter test --no-pub test/interest_history_test.dart` → FAIL.

- [ ] **Step 3: Implement** the interfaces. The screen titles itself `'Flex interest history'` or `'Plan interest history'`; each row shows the date, the day's interest, the rate and the running total (`'So far: ₦…'`). Plan detail adds an `'Interest history'` action; the Flex card's action from Task 5 opens the Flex variant. Flex uses `flexInterestView`; plans use `savingsPlansView`.

- [ ] **Step 4: Run the tests and `flutter analyze`** → PASS; no issues.

- [ ] **Step 5: Commit** — `feat(savings): show daily interest history for Flex and plans`

### Task 7: Verification

**Files:**
- Create: `docs/verification/2026-10-12-core-naira-history-interest.md` (commit with `git add -f`)

- [ ] **Step 1:** Run `flutter analyze` and `flutter test --no-pub`. Expected: no issues; any failure named (the known `platform_branding_config_test` push-entitlement failure is pre-existing until the Debug entitlements decision).
- [ ] **Step 2:** Write the note: what shipped per task, the Swagger SHA-256, the commands' results, and these staging checks — a ₦10.00 transfer on each route debits exactly ₦10.00; limits, plan, product and history amounts match the BankOne statement; a 60-day history pages correctly; Flex interest matches this month's accruals' last `cumulativeInterest`; a plan's accruals sum to its `accruedInterest`.
- [ ] **Step 3: Commit** — `docs: record the Naira, history and interest verification`
