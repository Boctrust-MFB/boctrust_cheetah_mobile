# Core mobile banking endpoint implementation plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan task by task. Checkboxes track execution. This document is a plan only; no endpoint is activated by saving it.

**Goal:** Connect customer account history, then implement the newly documented savings-plan, transaction-limit, and staged transfer routes; request statements by email once delivery is confirmed, and safely freeze or unfreeze an owned account after the `referenceId` contract is clarified.

**Architecture:** Keep the existing Core transport and account ownership list. Add an account-scoped history request/provider separately from the existing summary capability; retain opaque rows until staging confirms their fields. Implement savings, limits, and transfers as separate customer-scoped flows with their own capability gates and server-owned references. Statement and freeze remain unavailable to customers until their authorization and account ownership rules are verified or exposed through customer-scoped backend routes. The statement flow requests email delivery and has no in-app PDF viewer.

**Tech stack:** Flutter, Dart, Riverpod, Dio; existing Core API client. Freeze reference storage depends on the pending backend clarification.

**Spec:** The user request of 10 October 2026 and the [Core API reference](https://core-dev-api.centurysoftware.dev/api/v1/docs/#/), reread on 10 October 2026 after new routes appeared. Relevant prior evidence: [Core account activity verification](../../verification/2026-10-07-core-account-activity.md). The API reference and live staging replies take precedence over that older verification note where they differ.

## Field availability audit

| Route and field | Required by API | Available on mobile? | Source or required change |
|---|---|---|---|
| History `accountNumber` | Yes, path | Yes | `CustomerBankAccount.accountNumber` from `GET /me/bank-accounts`; account detail also receives it as `entityId`. Validate a unique owned 10-digit account before calling. |
| History `fromDate`, `toDate` | Yes, query, `DD-MM-YYYY` | Yes | `CoreHistoryRange` already generates 7/30/60-day windows and `CoreAccountService.getAccountTransactions` sends them. |
| History `numberOfItems` | Optional, integer 1–1000; docs default 20 | Yes | Service sends 50, within the documented bound. Keep it explicit. |
| Statement `accountNumber` | Yes, path | Yes | Core account list provides it. Account statement screen currently has no account selector; add one rather than guessing the Flex account. |
| Statement `fromDate`, `toDate` | Yes, query, `YYYY-MM-DD` | Partly | `_StatementPeriodField` selects a range, but its callback is discarded by the parent. Capture and validate the range, then format it separately from history dates. |
| Freeze `action` | Yes, body | Can be generated | API enum is `freeze` / `unfreeze`. Derive the proposed action from fresh server status and explicit user confirmation. |
| Freeze `accountNumber` | Yes, body | Yes | Core account list provides it. Security Center currently has one account-wide disabled toggle; add an account picker or make the control account-specific. |
| Freeze `referenceId` | Yes, body | **Unresolved** | The current app has no freeze reference. The API says unfreeze must reuse the freeze reference; the source and recovery behavior await clarification. Do not choose a client-only storage design yet. |
| Freeze `reason` | No, body | Not currently collected | Add a short reason choice/input if product requires it; do not invent a reason silently. Confirm any backend length/content constraints. |

The bearer token is already supplied to Core by `coreDioProvider`. That does **not** establish that the two non-`/me` routes authorize a customer token or restrict access to the customer's own account.

## Contract gates before customer activation

1. **History response:** The existing request can be integrated and called before row mapping. Obtain sanitized nonempty and empty staging replies. The docs note that every sandbox account has returned an empty history, so ask the backend for a staging account with real postings; until one exists, row mapping stays blocked. Swagger does not define usable transaction item fields. Until those fields are confirmed, keep rows opaque and display no transaction details; distinguish a nonempty but unmapped response from an empty history. Then confirm date/time zone, amount unit and sign, direction, status, stable ID, and receipt fields before mapping.
2. **Statement delivery:** Verify a signed-in mobile token can call `GET /accounts/{accountNumber}/statement` only for an owned account. The documented response is `{isPdf, content}` and does **not** promise email delivery. Confirm that this call actually emails the statement, or obtain a customer-scoped email-delivery route; do not tell the customer an email was sent merely because content was returned. No viewer, download, local PDF file, or sharing flow is planned.
3. **Freeze route:** Verify customer-token authorization and ownership for `POST /accounts/freeze-status`, the authoritative frozen status, and any required step-up authorization. Resolve who creates and retains `referenceId`, how unfreeze obtains the same value after reinstall or device change, and what happens after an uncertain response. Also ask whether customer freeze should use BankOne's post-no-debit (`/account-management/pnd-status`) instead of a full freeze. The freeze/unfreeze UI stays disabled until that contract is clarified and verified.
4. **Sensitive Core logs:** Use the existing `LoggingInterceptor.privacySensitivePathKey` request extra on these three route calls, with a path template, to suppress payloads and account-number paths. Do not change the logger redaction lists. Add focused tests before staging requests.
5. Record sanitized staging evidence and activation decisions in `docs/verification/`. Never use a production account to probe freeze semantics.

## File map

- `lib/app/core_api_endpoints.dart`: path constants for statement and freeze; history path already exists.
- `lib/module/core_banking/model/core_account_transactions.dart`: keep the opaque fetch response initially; add row mapping only after contract verification.
- `lib/module/core_banking/service/core_account_service.dart`: history request and statement request; use the existing Core service provider.
- New focused statement model/provider files under `lib/module/core_banking/`: request email delivery once verified and hold loading/error state without retaining statement content.
- New focused freeze model/service/provider files under `lib/module/core_banking/`: follow the clarified reference contract, validate the action and account, and refresh account status.
- `lib/module/core_banking/provider/core_account_activity_providers.dart` and `lib/module/core_banking/screens/bank_account_detail_screen.dart`: scoped history state and account detail UI.
- `lib/module/send/provider/transaction_provider.dart` and `lib/module/send/screens/transaction_flow_screens.dart`: keep the general history page unavailable until a confirmed row mapping and cross-account presentation exist.
- `lib/module/account/screens/account_control_screens.dart`: account/date selection, correct statement delivery, and account-specific freeze control.
- `lib/app/feature_capability.dart`, `lib/app/private_user_state.dart`: add a separate history capability while preserving `coreAccountActivity` for summary; clear user-scoped in-memory state on sign-out.
- `test/`: focused contract, service, provider, and widget tests using sanitized fixtures.

## Tasks

### Task 1: Protect requests and establish route contracts

- [ ] Add request/logging tests proving history and statement account numbers, transaction rows, statement content, and freeze `referenceId`/`reason` do not reach the Core logger. Apply the existing `privacySensitivePathKey` to each call; do not edit logger redaction lists.
- [ ] Save sanitized staging examples for history (nonempty and empty) and document exact item fields and status codes. Request a staging account with postings from the backend if sandbox accounts stay empty; record that row mapping is blocked until it exists. Keep account numbers, names, statement contents, tokens, and reference IDs out of committed fixtures.
- [ ] Verify owned and unowned account access for statement and freeze using test accounts. Record whether the mobile bearer token is accepted and unowned access is rejected.
- [ ] Confirm whether the statement route sends an email. If it only returns content, request a customer-scoped email-delivery route and keep the statement action unavailable until that route works. Verify the server's permitted date range.
- [ ] Record the clarified freeze `referenceId` lifecycle and recovery contract, including repeat/uncertain requests. If it cannot support safe unfreeze, keep the freeze action unavailable and specify the required backend change.

### Task 2: Connect customer account history before row mapping

- [ ] Keep the existing `DD-MM-YYYY` request and raw-row parser. Add tests for nonempty, empty, malformed, 400, and 404 replies.
- [ ] Add an account-scoped, session-scoped provider that calls the route on the account detail page and supports loading, refresh, error, empty, and nonempty-unmapped states. Discard stale results on account switch or sign-out.
- [ ] Add `coreAccountHistory` as a separate, staging-only capability for this GET. Leave `coreAccountActivity` and its summary UI independent. The nonempty-unmapped state must not present guessed transaction rows: show "You have activity in this period. Details aren't available in the app yet." and assert that copy in its widget test. Keep the general history page unavailable.
- [ ] After the staging row contract is confirmed, add failing mapping tests for amount unit/sign, date/time zone, stable ID, direction, status, and receipt absence; implement only fields supported by the response.
- [ ] Render mapped rows on account detail with 7/30/60-day selection. Test refresh, account switch, sign-out, and empty/error states. Decide any later cross-account history work as a separate plan.

### Task 3: Request account statements by email

- [ ] After Task 1 confirms ownership and email delivery, add request tests for owned account selection and `YYYY-MM-DD` formatting; reject missing account/range, reversed dates, future dates, and a range beyond the verified server limit.
- [ ] Add an account selector and retain `_StatementPeriodField`'s selection in the parent. Wire a single request through a session-scoped provider. The parser discards any returned `content` (a base64 PDF), so it never reaches provider state; test that it is absent.
- [ ] Show an email confirmation only when the verified backend contract confirms delivery. Otherwise show an accurate pending/failure state and keep the action unavailable until the email route is provided. Update both the statement screen and its account-page entry copy in `lib/module/account/screens/account_screens.dart`, which has unrelated uncommitted changes to preserve.
- [ ] Test loading, failure, retry, account switch, and sign-out. Register `accountStatement` only after the Task 1 email and ownership gates pass. Do not add a PDF viewing or sharing dependency.

### Task 4: Freeze and unfreeze after `referenceId` clarification

- [ ] Resolve Task 1's reference and authorization gates first. Write the chosen reference source, retention, lookup, and recovery behavior into the verification record before implementing a submit action.
- [ ] Add request tests for exact `action`, `accountNumber`, `referenceId`, and optional `reason`; test that unfreeze uses the original reference and that duplicate taps cannot produce duplicate POSTs.
- [ ] Implement an account-specific confirmation and one POST per intent, followed by a fresh server status read. After timeout or unknown outcome, read status and reference state before allowing another action.
- [ ] Replace the disabled Security Center toggle with per-account status and actions only after the backend contract is verified. Reject unknown or ambiguous account status; keep frozen-account transfer controls consistent with refreshed status.
- [ ] Test server error and sign-out on the client. Verify restart, device-change recovery, and unowned-account denial on staging, since they depend on backend behavior. Register `freezeAccount` only after all gates pass; otherwise retain the disabled UI and record the backend dependency.

### Task 5: Verify and document release readiness

- [ ] Run focused Flutter tests, `flutter analyze`, and the full test suite. Fix failures introduced by these changes.
- [ ] On staging devices, verify the history call and later row display, statement email delivery, freeze, unfreeze, interrupted requests, and accessibility for account selection and confirmations. Do not issue duplicate freeze requests after an unknown outcome.
- [ ] Update `docs/verification/` with sanitized contract evidence, test results, route authorization decisions, and any remaining blocked capability. Recheck that logs contain no account number, reference ID, or statement content.

## Review focus

- A history row whose amount unit or sign differs from the fixture must not display an incorrect balance or direction.
- Switching accounts while a request is in flight must not show the first account's history or statement for the second.
- A statement response containing `content` must not be mistaken for proof of email delivery or logged/stored on device.
- A freeze response lost after the server applies it must not trigger an automatic second POST; refresh status first.
- An app reinstall or device change must not strand a frozen account without an authorized unfreeze path.

## Suggested order

The logging protection in Task 1 precedes all three staging calls. Task 2's call/provider can precede history row mapping. Tasks 3 and 4 depend on their respective Task 1 backend findings, including the pending `referenceId` clarification. The new workstreams below can be delivered independently after their own contract gates; staged transfers should take priority because the current direct customer POST routes are absent from the latest reference. Preserve the existing unrelated working-tree changes when executing this plan.

## 10 October API expansion: scope and flow

The following routes are newly present under customer/mobile tags in the [live reference](https://core-dev-api.centurysoftware.dev/api/v1/docs/#/) (Swagger init SHA-256 `ab5f1bf9…`, 10 October; earlier sections cite `920fbbc4…`). All paths in this section are relative to `/api/v1`. This extends Tasks 1–5; it does not change their history, statement, freeze, or logger decisions. The internal `/compliance/transfer-rules` and `/tier-transaction-limits` CRUD routes require an internal-service token and are excluded from the mobile implementation.

| Feature | New customer routes | Short flow |
|---|---|---|
| Savings plans | `POST/GET /me/savings-plans`, `GET /me/savings-plans/flat`, `GET /me/savings-plans/{planId}`, `POST /me/savings-plans/{planId}/fund`, `POST /me/savings-plans/{planId}/liquidate` | List grouped or flat plans → open a plan for events → create from a supported product/tenor, or fund from BocFlex → refresh plan and account balances. Liquidation returns the full principal to BocFlex without interest; require an explicit confirmation. |
| Transaction limits | `GET /me/transaction-limits`, `POST /me/transaction-limits/initiate`, `POST /me/transaction-limits/{reference}/otp/request`, `POST /me/transaction-limits/{reference}/finalize` | Read business, custom, and effective caps → initiate only changed values → request OTP with the returned reference → collect PIN and OTP → finalize → refetch effective caps. |
| BOCTRUST transfer | `POST /me/intrabank/transfers/initiate`, `POST /me/intrabank/transfers/{reference}/otp/request`, `POST /me/intrabank/transfers/{reference}/finalize` | Auto-resolve a 10-digit recipient (or use an exact preselected account/name pair) → initiate with a digit-only Kobo amount → collect PIN → if OTP is required, open its page and request it → send PIN and any OTP to finalize → use `retrievalReference` for live requery. |
| Other-bank transfer | `POST /me/interbank/transfers/initiate`, `POST /me/interbank/transfers/{reference}/otp/request`, `POST /me/interbank/transfers/{reference}/finalize` | Select bank and auto-resolve a 10-digit recipient → initiate with a naira amount → collect PIN → if OTP is required, open its page and request it → send PIN and any OTP to finalize → use `transactionReference` for status/requery. |

The customer `POST /me/intrabank/transfers/own`, `POST /me/intrabank/withdrawals`, `POST /me/intrabank/transfers`, and `POST /me/interbank/transfers` are no longer in Swagger, and the app no longer calls them (10 October, commit `7ee2610`): own-account moves and savings withdrawals were removed, and the BOCTRUST and other-bank flows keep their screens, attempt provider, PIN sheet and requery code but send nothing until Task 10. Do not route own-account moves or withdrawals through the new recipient-transfer endpoints; they return only if Core documents a replacement. `POST /me/scan-to-pay` and `POST /me/snap-to-pay` both remain documented.

## New route field availability and contract decisions

| Route/field | Documented input or output | Mobile availability and required change |
|---|---|---|
| Savings create `productCode` | Required; supported values `bocSmartSave`, `boctrustFixedDeposit` | `SavingsProductType.smartSave` and `.fixed` exist, but add an explicit code mapping. Padi has no documented plan route; keep `padiCreate` gated. |
| Savings create `tenorDays` | Required; must match a product rate band | Wizard has `durationMonths`, not days; never approximate a month as 30 days. **No customer route exposes rate bands or their `min_amount`:** `GET /bank-products` gives one `tenure` and `interestRate`, grouped `defaultTenorDays` exists only for products the customer already has plans in, and `/products/{code}` is an unauthenticated back-office route. Creation stays blocked until the backend provides a customer route for each product's tenors, rates and minimum debit (Task 6). |
| Savings create `planName`, `targetAmount` | `planName` optional (Fixed Deposit auto-generates one); `targetAmount` in Kobo, **required for `bocSmartSave`** | Wizard has name and amount. For SmartSave, send the entered amount as `targetAmount` in Kobo and require it. For Fixed Deposit, send no `targetAmount`: create has no caller-selected principal, and the server immediately debits the product/tenor minimum from BocFlex. Change the confirmation copy and remove any promise that the entered fixed-deposit amount is the initial debit. |
| Savings create `saveFrequency`, `recurringAmount` | Optional, `bocSmartSave` only; `recurringAmount` in Kobo | Never send either for Fixed Deposit. Wizard has frequency and auto-save flag, but no recurring-amount field. Add one only if recurring saving is being enabled; otherwise omit both. Weekly/monthly contribution-day selections have no matching API field, so do not submit or advertise a schedule the backend cannot honor. |
| Savings create funding source/PIN | Neither accepted | Wizard currently requires a funding-source choice; remove or replace it with a fixed BocFlex explanation. No PIN is requested by this endpoint; check the product/security decision before activating an automatically money-moving create action. |
| Savings list `productCode` | Optional query on grouped and flat GET; values limited to the two supported products | Map product filter from the existing product screen. Use grouped GET for per-product cards with `accountBalance`, flat GET only where an all-plan list is needed. Avoid mixing grouped balance with one plan's `principalAmount`. |
| Savings detail/fund/liquidate `planId` | Required path; detail includes events | Use server `planId`, not account number or route name. Current `SavingsPlan.id` can hold it after typed response mapping. Refresh detail/list/account balance after actions; use server status and returned amounts as authoritative. |
| Savings fund `amount` | Required string body, in Kobo; source is BocFlex | Reuse the plan UI amount entry with `parseNairaToKobo`. Do not use the old own-account-transfer route for plan funding. |
| Savings liquidate | `planId` path only; no body, PIN, or chosen amount | Existing withdraw UI can confirm forfeited interest, but it must say full principal returns to BocFlex. Do not offer partial withdrawal. Statuses are documented (`pending_funding`, `active`, `matured`, `liquidated`, `cancelled`); 403 covers matured, liquidated or cancelled plans. |
| Limits GET response | `tier`, business ceilings (Kobo strings), custom overrides, effective single-transfer, single-bill-payment, and daily-transfer limits | The app has `limitIncrease` enum but no limit screen/service. Add a read-only display first; use effective limits for customer-facing values. Tier 0 may return 403 with BVN/liveness onboarding direction. |
| Limits initiate values | `singleTransferLimit`, `singleBillPaymentLimit`, `dailyTransferLimit`; at least one, each optional | Add inputs for all three rather than an increase-only UI. Send only changed fields; validate positive numeric format and compare against returned tier ceilings. The business ceilings are documented in Kobo, but these inputs and the custom/effective values state no unit: confirm they are Kobo on staging before submission (the only open unit question). |
| Limits reference/checks | Initiate returns `reference`, `requiredChecks`, `expiresAt`; OTP request needs reference; finalize needs `transactionPin`, `otpCode` | No current limit state machine or OTP collection exists. Add one, keep credentials transient, handle expiry, and refetch after finalization. The route documents `requiredChecks` as always `['pin', 'otp']`, never liveness; the shared schema is reused as-is, which is why it lists liveness. Still read `requiredChecks` rather than hard-coding it. |
| Transfer initiate recipient/amount | Intrabank: `toAccountNumber`, `amount`, optional `narration`; interbank: `receiverBankCode`, `receiverAccountNumber`, `amount`, optional `narration` | Keep integer Kobo drafts. Intrabank sends digit-only Kobo: decimal `1650.00` was rejected by the route, so ₦1,650.00 sends `165000`. Interbank keeps exact naira conversion under the earlier decision. Verify each flow's actual debit in staging. Reject amounts over ₦25,000,000 before initiating. Use `CancelToken` and stale-result checks to clear lookup data on edits and auto-run at 10 digits. |
| Transfer checks/reference | Initiate returns `reference`, `requiredChecks`, `expiresAt`; OTP request takes the reference; finalize accepts requested `transactionPin` and `otpCode` | Handle PIN-only by opening the PIN sheet then finalizing. For PIN+OTP, collect PIN first, open the OTP page, call `/{reference}/otp/request` there, and send PIN plus entered OTP to finalize. Keep credentials only in active UI memory, not provider state. Do not implement or send `livenessVerified`; stop before finalize if liveness or an unknown check is returned. |
| Transfer final result | Intrabank returns `retrievalReference`; interbank returns `transactionReference`, status and response details | Existing requery types can be adapted, but keep initiation `reference` distinct from final BankOne tracking reference. After timeout/unknown finalize outcome, check status/requery when a final tracking reference exists; otherwise retain the unresolved state and require a backend lookup/recovery contract before any retry. Do not auto-finalize twice. |

**Cross-cutting constraints:** `POST /me/bank-accounts` now documents BocFlex as the only account it auto-provisions; creating the first savings plan lazily opens that product's BankOne account. Reflect this in product/account loading. A savings create/fund/liquidate or transfer finalize changes money; update `CoreApiEndpoints.moneyMoving` and the capability registry when wiring each route, and test that the existing denied authorization gate cannot be bypassed. The present `TransactionAuthorizer` comment says credentials never enter Core request bodies, whereas the new finalize contracts require PIN/OTP in the body; resolve that security-interface mismatch explicitly before implementing finalization. Do not add PIN, OTP, liveness data, account numbers, or plan events to logs or persisted state; use the existing `privacySensitivePathKey` mechanism without changing logger redaction lists.

## Expansion file map

- `lib/app/core_api_endpoints.dart` and `lib/app/feature_capability.dart`: exact new path templates, separate read/action capabilities, money-moving set, and removal of obsolete customer submission requirements only after migration is verified.
- `lib/module/savings/model/savings_plan_models.dart`, `lib/module/savings/provider/savings_plan_provider.dart`, `lib/module/savings/screens/savings_plan_screens.dart`, `lib/module/savings/screens/savings_screens.dart`: typed plan/group/event/status mapping, Core service and provider, supported-product wizard, list/detail/fund/liquidate states.
- New focused `lib/module/savings/service/core_savings_plan_service.dart`: grouped/flat/detail reads and create/fund/liquidate calls through `coreApiServiceProvider`.
- New focused `lib/module/account/model/transaction_limit_models.dart`, `lib/module/account/service/core_transaction_limit_service.dart`, and `lib/module/account/provider/transaction_limit_provider.dart`: typed limits and pending-update state.
- `lib/module/account/screens/account_control_screens.dart` (or a focused screen extracted from it): limit display/edit/OTP confirmation; preserve the existing statement and freeze work and unrelated changes.
- `lib/module/core_banking/service/core_transfer_service.dart`, `lib/module/core_banking/provider/core_transfer_attempt_provider.dart`, `lib/module/core_banking/screens/core_transfer_attempt_view.dart`, and transfer screens: initiation, required-check collection, finalize, status/requery, and transient credentials.
- New focused transfer initiation model under `lib/module/core_banking/model/`: server reference, `requiredChecks`, and expiry, separate from the final transfer acknowledgment.
- `test/`: focused service/parser/state/widget cases for each independently deliverable flow. Record sanitized staging observations in `docs/verification/`.

## Detailed implementation contracts

### Shared transport, authorization, and lifecycle

1. Keep all `/me/...` requests on `coreApiServiceProvider`, whose base URL already includes `/api/v1`; endpoint constants therefore start at `/me`. Add path builders for `{planId}` and `{reference}` with `Uri.encodeComponent`, alongside literal templates for capability registration and sensitive-path logging. Never build a path by concatenating unvalidated user text in a screen.
2. Parse the API envelope through the existing `ApiService` and `ServiceResponse`/`NotifierState` conventions. Treat a malformed success body as an error. A success response from `initiate` means a pending action was created; it does not mean a transfer or limit change completed. A transfer `finalize` acknowledgment means accepted, and the existing status classifier decides what may be shown as settled.
3. Put secrets only in the final request scope. PIN and OTP must not be stored in `Equatable` model props, Riverpod state, route arguments, error copy, analytics, or retry queues. Attach `LoggingInterceptor.privacySensitivePathKey` to reads and writes that carry an account number, recipient details, plan event/reference, PIN, OTP, or statement content. Retain the user's instruction to leave logger redaction lists unchanged.
4. Each provider watches the signed-in session and drops late responses after sign-out or user switch. Key account history by account number (and by range once the selector exists); key savings detail by `planId`. Clear pending references and user-specific list/detail state on session change. Persisting an unresolved money movement requires a separately reviewed recovery contract; an in-memory pending reference alone does not survive restart.
5. Keep feature gates granular: savings list/detail, create for each supported product, fund, liquidate, limits read, limits change, BOCTRUST transfer, other-bank transfer, history, statement, and freeze may each have different release readiness. Do not register an operation as available merely because its route appears in Swagger.

### Account history, statement, and freeze handoff

| Slice | Request/response implementation | Screen and success rule | Test anchor |
|---|---|---|---|
| History | Done on `feat/core-account-history`: a session-scoped caller keyed by account number requests the last 30 days; `data.transactions` remains `List<Object?>` until a real nonempty example defines row fields. | On account detail, load and refresh independently of the live summary. Show distinct empty, error, and nonempty-unmapped states. Never show invented dates or amounts. The 7/30/60-day selector arrives with row mapping (Task 2), keyed then by account and range. | `test/core_account_activity_test.dart` and `test/bank_account_detail_test.dart` cover the log template and the empty and nonempty-unmapped states; add per-range calls with the selector. |
| Statement | After verified customer authorization and email behavior, request owned `accountNumber` plus `YYYY-MM-DD` dates. If the current route still only returns `{isPdf, content}`, keep email action gated until an email-delivery contract exists. | Capture selected account and period in the existing statement screen; show “sent” only on a response that confirms email delivery. No PDF viewer or download. | Extend `test/account_controls_test.dart` for date formatting, ownership, failed delivery, and absence of PDF content from provider state/logs. |
| Freeze | After backend clarification, send `action`, owned `accountNumber`, original `referenceId`, and optional user-provided `reason`; refresh authoritative status. | One account-specific confirmation and one POST per intent. Unknown outcomes block another action until status/reference are reconciled. | Extend `test/account_controls_test.dart` plus a service test for original-reference unfreeze, duplicate taps, restart recovery, and unowned-account rejection. |

### Savings plans: exact mobile data path

| Step | Core request and expected data | App work and decision |
|---|---|---|
| 1. Browse | `GET /me/savings-plans?productCode=...` returns groups with `accountNumber`, `productCode`, `productInterestRatePercent`, `defaultTenorDays`, `accountBalance`, and nested `plans`. `GET /me/savings-plans/flat` returns the plans without group balances. | Use grouped data for the product cards and nested plan list. `accountBalance` falls back to summed plan principal when the live balance call fails, and the response does not say which; do not label it a live balance. Use flat only for a cross-product “my savings” list if that screen actually needs it; avoid duplicate fetches for the same screen. No plan is shown until parsed from Core. |
| 2. Open | `GET /me/savings-plans/{planId}` returns the plan plus `accountNumber` and `events` (`eventType`, `amount`, before/after balances, rate, reference, timestamp). | Navigate with `planId`. Render only supported server fields. Keep raw event identifiers out of telemetry; preserve server amounts and dates until units and timezone are verified. Handle 404 as “plan no longer available” and refresh the list. |
| 3. Create | `POST /me/savings-plans` body requires `productCode` and `tenorDays`; optional `planName`, `targetAmount`, `saveFrequency`, `recurringAmount`. No caller funding amount, funding-source field, or PIN. First plan lazily opens that product's BankOne account and automatically funds the minimum from BocFlex. | Replace fixed-deposit principal and funding-source promises with the documented minimum-debit review. `CoreBankProduct` currently has only one `tenureDays` and no `minAmount`/rate-band list, and no customer route provides them; creation stays blocked on the Task 6 rate-band route. On 200, parse `planId` and fetch detail/group/accounts; do not assume the generic sample status `pending_funding` means fully funded. On a timeout, fetch list/detail before offering another create. |
| 4. Add funds | `POST /me/savings-plans/{planId}/fund` body `{amount: string}` in Kobo; 403 for a closed/matured/liquidated plan, 404 for an unowned/missing plan. | Use the existing amount entry, sent in Kobo. Display BocFlex as the source and require a single explicit submit. Fetch detail/group/BocFlex after response; avoid duplicating a request after unknown outcome. |
| 5. Exit early | `POST /me/savings-plans/{planId}/liquidate` has no body and returns full principal to BocFlex, without interest. | Show amount and interest forfeiture from current server detail, obtain explicit confirmation, submit once, then refetch. Hide partial-withdraw controls. A mature plan is not eligible for this early-exit action per documented 403. |

**Savings UI reconciliation:** `SavingsPlanDraft` currently has `durationMonths`, `amount`, `fundingSource`, `contributionDays`, `memberCount`, and `startDate`. Only some of these map to SmartSave/Fixed Deposit creation. Keep Padi-specific fields and routes gated. Do not silently turn the current monthly duration into days, use the draft amount as a funding debit, or claim that an unsupported contribution-day schedule will run. The server's `principalAmount`, `interestEarned`, and `status` override client estimates and the current three-value `SavingsPlanStatus` enum; map known statuses explicitly and show an unavailable state for unknown statuses.

### Transaction limits: exact mobile state path

1. **Read:** `GET /me/transaction-limits` returns `tier`, three business ceilings, optional custom values, and three effective values. Show all three effective limits and their tier ceilings. A Tier-0 403 leads to the existing BVN/liveness onboarding route; do not render zero limits from an error.
2. **Edit:** Present single-transfer, single-bill-payment, and daily-transfer inputs. Build a request containing only changed fields and at least one field. Check each candidate against the latest business ceiling, then let the server validate again at initiate and finalize. A `limitIncrease`-only label is inaccurate if the backend permits reductions; use a neutral “Manage limits” control.
3. **Initiate:** `POST /me/transaction-limits/initiate` returns `reference`, `requiredChecks`, `expiresAt`. Hold this only as pending session state. If initiation fails or expires, do not proceed to OTP or finalize. A tier change may invalidate the requested value before finalization.
4. **OTP/finalize:** `POST /me/transaction-limits/{reference}/otp/request` sends the OTP; `POST /me/transaction-limits/{reference}/finalize` submits `transactionPin` and `otpCode`. Do not send `livenessVerified` unless the backend changes the described limits contract; the route documents PIN and OTP as always required and never liveness.
5. **Refresh:** On 200, replace displayed limits with the finalize response or a fresh GET. On timeout/uncertain result, GET before proposing another update. No documented pending-update status lookup exists, so do not claim a failed finalize from a timeout alone.

### BOCTRUST and interbank transfers: exact mobile state path

| State | Request or local action | Transition and failure behavior |
|---|---|---|
| Draft/review | `BoctrustTransferDraft` or `InterbankTransferDraft` capture account, bank where relevant, amount, and optional narration. On account or bank edits, cancel the prior lookup, reset its provider, and clear the name; automatically look up at 10 account digits. An exact BOCTRUST account/name pair may be preselected. | Freeze the reviewed draft before initiating. Changing recipient/amount invalidates review. Send `amountKobo` unchanged on intrabank initiate; convert it exactly to plain naira on interbank initiate. Check each flow's actual debit in staging. Reject amounts over ₦25,000,000. |
| Initiating | `POST .../transfers/initiate` sends draft fields **without PIN**. | Parse `reference`, `requiredChecks`, `expiresAt`; do not show payment success. A 400/404 leaves no known money movement. Handle a lost initiate response carefully because a pending record may exist server-side. |
| Awaiting checks | Support only PIN-only and PIN+OTP. Open the PIN sheet first. For PIN-only, finalize with `transactionPin`; for PIN+OTP, open the OTP page, call `.../{reference}/otp/request` there, collect the code, and finalize with both values. | OTP-request 400/403/404 returns to a clear, non-success state. Stop before finalize if liveness or an unknown check is requested; do not send `livenessVerified`. Allow cancellation before finalize while making clear no transfer has been confirmed. |
| Finalizing | POST `.../{reference}/finalize` with only requested checks. | One in-flight finalize per attempt. 401 wrong PIN/OTP may be corrected only while the initiation remains valid; 403 means restriction/lock/expiry. 409 has two documented meanings (reference collision, or a similar transaction in the last 60 seconds); never retry automatically, and show the server message. Interbank only: the documented 500 (name enquiry failed or transfer rejected) with its error envelope is a definite failure. Any other 5xx, a 500 without that envelope, or a timeout is unknown and not safe to repeat. |
| Tracking | Intrabank response yields `retrievalReference`; interbank yields `transactionReference`, `status`, and response details. Existing intrabank/interbank requery routes remain documented; interbank also has GET status. | Map the final tracking reference to the existing result UI. Do not use the pending initiation `reference` as a BankOne tracking reference. Preserve a confirmed final state; a later failed requery does not erase it. When no final reference was received after an uncertain finalize, require the Task 6 recovery contract before another submission or release. |

The existing `CoreTransferAttemptProvider` has `authorizing/submitting/settled` states and reserves a single attempt across transfer screens. Extend that one-attempt invariant rather than creating a second provider that could concurrently finalize another transfer. The current PIN sheet can be reused after initiation; the OTP page is new mobile work. The OTP request asks the backend to deliver the code, and the app sends the entered code to finalize. No resend or alternate delivery flow is planned. `TransactionAuthorizer` presently denies authorization, and its comment about credentials never entering Core bodies conflicts with the new finalize API. Task 6 resolves that boundary before money-moving routes are activated. Interbank name enquiry for preview may remain, but the API explicitly defers its time-sensitive BankOne name enquiry to finalize; a preview must not be treated as final recipient proof.

### Acceptance and release matrix

| Deliverable | Minimum automated checks | Staging proof before capability activation |
|---|---|---|
| History call | `test/core_account_activity_test.dart`, `test/bank_account_detail_test.dart`: log template, empty and nonempty-unmapped states; range selection with row mapping. | Empty and nonempty sanitized response; row mapping waits for documented fields. |
| Savings reads | `test/savings_provider_test.dart`, `test/savings_live_ui_test.dart`: grouped/flat/detail parsing, unknown status, 404, sign-out. | Owned plan/list shape and product filter, including events and balances. |
| Savings writes | New focused savings service/state tests plus `test/savings_ui_test.dart`: exact body per product (SmartSave `targetAmount` required, Fixed Deposit none), Kobo amounts, one submit, unknown outcome, refresh, liquidation copy. | Customer rate-band/minimum route exists; balance changes and 403/404 behavior. |
| Limits | New limit service/provider/widget tests: optional-field diff, tier ceiling, OTP/PIN step, expiry, Tier-0 403, no credential retention. | Confirm the unit of limit inputs and custom/effective values; successful update followed by GET. |
| Transfers | `test/core_transfer_attempt_provider_test.dart`, `test/core_transfer_pin_ui_test.dart`, `test/core_transfer_requery_ui_test.dart`: cancelled/stale lookup suppression, 10-digit lookup, preselection, integer-Kobo intrabank and exact-naira interbank serialization, PIN-only and PIN+OTP order, no duplicate finalize, liveness fail-closed, 409 never retried, and tracking-reference distinction. | Test required checks, expiry, each flow's amount and actual debit, final response semantics, interbank 500 envelope, recipient name enquiry, and uncertain-outcome recovery. Any liveness-required initiation remains unavailable. |
| Statement/freeze | `test/account_controls_test.dart` plus focused service tests: owned account, period, no false email confirmation, original freeze reference, uncertain response. | Verified email delivery and owned-account authorization; clarified freeze reference lifecycle and status source. |

For every row, run the focused tests first, then `flutter analyze` and the full `flutter test` suite when that deliverable is ready. Save sanitized results and the exact feature-capability decision in `docs/verification/`. Release a read-only slice independently when its proof passes; keep its related write capability gated until its own proof passes.

## Expansion tasks

### Task 6: Reconcile route migration and security contracts

- [ ] Ask the backend for the supported replacement (if any) for own-account transfers and product withdrawals, whose routes left the docs and were removed from the app. Do not switch either to a recipient-transfer route by inference.
- [ ] Request a customer-scoped route for each savings product's tenors, rates and minimum debit (`min_amount`); none exists, and savings creation stays blocked until it does. Confirm the unit of limit inputs and custom/effective values (the only undocumented unit). Record this in `docs/verification/` before activating those writes.
- [ ] Verify the OTP-request → finalize sequence and expiry in staging. Do not plan resend, alternate OTP delivery, or liveness implementation; keep liveness-requiring transfers gated. Verify recipient-name lookup authorization. Test how the two 409 meanings and interbank 500 error body appear, and test uncertain-finalize recovery after app restart when only the initiation reference is known. Record final response semantics and each route's amount unit.
- [ ] Decide and document the new finalization security boundary: the approved authorization gate, transient credential capture, Core request body, privacy-sensitive logging, and unknown-outcome recovery. Write tests proving an unapproved gate cannot call a money-moving route and that no credential is retained in provider state.

### Task 7: Savings plans read experience

- [ ] Add endpoint constants and typed models for grouped products, flat plans, detail events, and server status. Test missing optional fields, unknown status, empty lists, and separation of aggregate product balance from plan principal.
- [ ] Add `CoreSavingsPlanService` and a session-scoped provider for grouped GET, flat GET when needed, and detail GET. Test product filter encoding, owned-plan 404, refresh, account switch, and sign-out clearing.
- [ ] Connect the existing product cards and plan detail to server results. Enable `savingsPlansView` only when the reads and mapping work; keep create, deposit, edit, withdraw, and Padi capabilities separate.

### Task 8: Savings create, fund, and liquidate

- [ ] Map only SmartSave and Fixed Deposit to their documented `productCode` values. Source valid `tenorDays` from verified rate-band data; remove unsupported funding-source, contribution-day, and caller-chosen initial-funding promises from the corresponding wizard. Keep Padi creation and plan edit gated.
- [ ] Add create request tests for required product/tenor, SmartSave's required Kobo `targetAmount`, SmartSave-only frequency and recurring amount, and Fixed Deposit sending none of these. Show the exact automatic BocFlex minimum debit before confirmation; test insufficient balance, missing rate band, unknown response, and single-submit behavior. Enable the two create capabilities only after these pass.
- [ ] Add fund-by-`planId` with a Kobo amount and an explicit BocFlex source. Add liquidate-by-`planId` with no body, full-principal/no-interest confirmation, and no partial-withdraw option. Test 403/404, duplicate taps, timeout/unknown result, and refresh of plan plus BocFlex balances before declaring success. Enable deposit and withdraw separately after their gates pass.

### Task 9: Transaction limits read and update

- [ ] Add typed GET mapping for tier, business/custom/effective limits and a read-only screen. Test absent custom values and Tier-0 403 onboarding state before adding edits.
- [ ] Add initiate request/state for a nonempty subset of `singleTransferLimit`, `singleBillPaymentLimit`, `dailyTransferLimit`; validate against the current tier ceiling, in the unit Task 6 confirms. Test unchanged and over-ceiling inputs and a tier change between initiate and finalize.
- [ ] Request OTP with the server reference, collect PIN and OTP transiently, finalize once, and refetch GET. Test expiry, missing verified OTP destination, wrong credentials, lost response, sign-out, and no duplicate finalize. Register read and update capabilities separately; rename or replace `limitIncrease` if both increases and decreases are supported.

### Task 10: Staged customer transfers

For the current checkout, use the focused [staged customer transfers implementation plan](2026-10-10-staged-customer-transfers.md) as the executable version of this task. It reflects the removed single-step submission calls and the current Send UI. The bullets below are retained as scope history.

- [ ] Add initiate, OTP-request, and finalize path templates for both transfer types, plus typed `reference`/`requiredChecks`/`expiresAt` parsing. Send draft `amountKobo` as digit-only intrabank `amount`; convert to plain naira for interbank. Test both payloads without PIN, the ₦25,000,000 ceiling, expiry, and unexpected checks. Cancel and reset lookup on recipient edits, run it at 10 digits, and allow exact BOCTRUST preselection.
- [ ] Refactor the attempt provider into reviewed → initiating → awaiting checks → finalizing → settled/unknown states. For PIN-only, open the PIN sheet and finalize. For PIN+OTP, collect PIN first, then open the OTP page, request OTP there, and send PIN and entered OTP on finalize. Keep credentials only in active UI memory; stop on liveness or unknown checks. Test rejection, cancellation before finalize, sign-out, and expiry while a sheet is open.
- [ ] Map the final intrabank `retrievalReference` and interbank `transactionReference` to the existing status/requery paths. Test accepted/pending, final failure, 409 never auto-retried, interbank documented 500 as final failure, and other 5xx/timeout as unknown. Test restart recovery only after Task 6 establishes a server lookup or safe reference-recovery contract; otherwise keep the relevant transfer capability gated. Do not confuse either final tracking value with the pending initiation reference.
- [ ] Update `moneyMoving`, capability requirements, privacy-sensitive request metadata, and the BOCTRUST/interbank screens together. Enable each transfer capability only after the authorization and staging gates pass. Own-account moves and savings withdrawals were removed with their routes and return only with a documented replacement.

### Task 11: Expansion verification

- [ ] Run focused parser/service/provider/widget tests, `flutter analyze`, and the full test suite after implementation. Verify on staging with sanitized product, plan, transfer, and limit fixtures; never use production money movement for contract discovery.
- [ ] Record which capabilities are activated or still gated, the exact staging response fields and units, UI copy for automatic funding and liquidation, security decisions, and remaining backend questions in `docs/verification/`.
