# Core Account Statement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a customer generate and save a Core account statement PDF for a selected account and date range.

**Architecture:** Add the per-account Core statement route and typed PDF response to the existing account service. Replace the email-request placeholder with a PDF save action, reusing the existing `_StatementPeriodField` and its one-year selection behavior. Keep request validation in the service so invalid ranges cannot reach Core.

**Tech Stack:** Flutter, Dart, Riverpod, Dio, existing `ApiService`, `file_picker`.

**Spec:** Core Swagger UI, Customer Accounts (Mobile), `GET /api/v1/me/bank-accounts/{accountNumber}/statement`: https://core-dev-api.centurysoftware.dev/api/v1/docs/

## Global Constraints

- `accountNumber` is 10 digits; `fromDate` and `toDate` are required `YYYY-MM-DD` query values.
- The range may be at most one year and cannot end in the future. Reject reversed ranges locally.
- Reuse `_StatementPeriodField`; do not create a second date-range picker. Use its existing `onChanged` callback as the selected request range and keep its one-year clamp.
- Core returns `accountNumber`, `fromDate`, `toDate`, `fileName`, `contentType` (`application/pdf`), and base64 `content`. Decode only after confirming the content type.
- Core documents `400` (validation/range), `404` (no such account for this customer), and `500` (core banking couldn't generate the statement). Show Core's message and keep the form for retry.
- Use the authenticated Core transport and account numbers from Core account data; do not route this through the User Service.
- Keep the capability staging-only until verified against staging.
- **Tests: none.** No money moves and the service rejects invalid input before HTTP. Update existing tests only where this change breaks them (for example, placeholder assertions on the statement route).

---

### Task 1: Register the Core statement route and capability

**Files:**
- Modify: `lib/app/core_api_endpoints.dart`
- Modify: `lib/app/feature_capability.dart`

- [ ] Add `bankAccountStatement(String accountNumber)` and `bankAccountStatementTemplate` beside the other bank-account paths; encode the account number with `Uri.encodeComponent`.
- [ ] Add the `FeatureCapability.accountStatement` requirement with exactly `(backend: ApiBackend.core, method: 'GET', path: bankAccountStatementTemplate)` and `stagingOnly: true`.
- [ ] Run `flutter test test/feature_capability_test.dart`; fix any existing assertion that expected `accountStatement` to have no contract.

### Task 2: Parse and fetch a Core PDF statement

**Files:**
- Create: `lib/module/core_banking/model/core_account_statement.dart`
- Modify: `lib/module/core_banking/service/core_account_service.dart`

- [ ] Add `CoreAccountStatement` with `accountNumber`, `fromDate`, `toDate`, `fileName`, `contentType`, and decoded `Uint8List bytes`. `fromJson(Object? json)` requires every field, `application/pdf`, and valid base64; otherwise throw `FormatException`.
- [ ] Add `formatCoreDateOnly(DateTime)` returning zero-padded `YYYY-MM-DD`, and a range validator: dates ordered, `toDate` no later than today, span at most one calendar year. Keep transaction history's `CoreHistoryRange` rules untouched.
- [ ] Add `CoreAccountService.getAccountStatement(String accountNumber, {required DateTime fromDate, required DateTime toDate}) -> Future<NotifierState<CoreAccountStatement>>`; return a local error before HTTP for a non-10-digit account number or an invalid range.
- [ ] Send `GET bankAccountStatement(accountNumber)` with only `fromDate` and `toDate` query parameters.

### Task 3: Wire the account statement screen and PDF save action

**Files:**
- Modify: `lib/module/account/screens/account_control_screens.dart`
- Create: `lib/module/account/provider/core_account_statement_provider.dart`

- [ ] Add an auto-dispose `CoreAccountStatementNotifier` / `coreAccountStatementProvider` with `Future<void> request(String accountNumber, DateTime fromDate, DateTime toDate)`. It starts idle and never fetches on selection changes.
- [ ] Remove the `assertPlaceholderFor(FeatureCapability.accountStatement, FeatureAvailability.unavailable)` call from `_accountStatementScreen`; gate the request on the capability's availability instead.
- [ ] Replace the email-request copy. Take eligible accounts from `customerBankAccountsProvider` (valid 10-digit numbers, not closed). With one eligible account (usually BocFlex), select it and show it as plain text with no picker; with several, show a picker defaulting to BocFlex.
- [ ] Pass `_StatementPeriodField.onChanged` into screen state as the selected range.
- [ ] Enable `Request statement` only when an account and range are selected and the capability is available. On tap, call the notifier once; after a parsed PDF, call `FilePicker.platform.saveFile(fileName:, bytes:)` directly — no saver interface.
- [ ] Treat a null save result as cancellation, not a request failure. After a Core error or cancellation, keep the account and range so the customer can retry.

### Task 4: Verify the statement integration

- [ ] Run `flutter test test/feature_capability_test.dart test/account_controls_test.dart`.
- [ ] Run `flutter analyze`.
- [ ] On staging, request a statement for an owned account with an allowed range; confirm the saved PDF opens on Android and iOS. Keep the capability staging-only until this succeeds.
