# Customer account freeze and frozen-state UI

**Status:** Implementation plan based on the Core mobile-account Swagger documentation reviewed on 17 October 2026, revised the same day after a review against the Swagger and the current code.

## Summary

Let customers freeze an owned Core account from Security Center and unfreeze an account they froze themselves. Freeze requires their transaction PIN; unfreeze first sends an OTP, then requires both PIN and OTP. Reflect a frozen Boc Flex account on the Home wallet card with a restrained cool-toned treatment and a clear status label. Keep balance and history readable while frozen. Stop outbound actions from a frozen Boc Flex account in the app, while Core remains the authority that enforces the freeze.

## Core contract and scope

- [Freeze](https://core-dev-api.centurysoftware.dev/api/v1/docs/#/Customer%20Accounts%20(Mobile)/post_api_v1_me_bank_accounts__accountNumber__freeze): `POST /me/bank-accounts/{accountNumber}/freeze` with `{"transactionPin":"1234"}`. It stops money leaving the account. Documented outcomes: `200` frozen, `401` wrong PIN, `404` account not owned/found, `409` already frozen.
- [Send unfreeze OTP](https://core-dev-api.centurysoftware.dev/api/v1/docs/#/Customer%20Accounts%20(Mobile)/post_api_v1_me_bank_accounts__accountNumber__unfreeze_otp): `POST /me/bank-accounts/{accountNumber}/unfreeze/otp`, no body. `200` returns `otpSent` and a nullable `otpExpiresAt`. `403` means the bank froze the account and only support can unfreeze it; `409` means it is not frozen. Discard the staging-only `otpCode` response field. There is no separate resend route: resending calls this route again.
- [Confirm unfreeze](https://core-dev-api.centurysoftware.dev/api/v1/docs/#/Customer%20Accounts%20(Mobile)/post_api_v1_me_bank_accounts__accountNumber__unfreeze): `POST /me/bank-accounts/{accountNumber}/unfreeze` with `transactionPin` and `otpCode`. `401` means "Wrong PIN or code" (Core does not say which), `403` bank-frozen, `409` not frozen. The docs do not say whether a failed attempt consumes the code.
- Freeze and unfreeze replies return `AccountFreezeResult`: `accountNumber`, `status` (`active`/`frozen`/`closed`), nullable `frozenBy` (`customer`/`admin`) and `frozenAt`.
- [Account list](https://core-dev-api.centurysoftware.dev/api/v1/docs/#/Customer%20Accounts%20(Mobile)/get_api_v1_me_bank_accounts) and [single account](https://core-dev-api.centurysoftware.dev/api/v1/docs/#/Customer%20Accounts%20(Mobile)/get_api_v1_me_bank_accounts__accountNumber_) provide `status`; the app already parses `active`, `frozen`, `closed`, and unknown. The reads do not include `frozenBy`. A bank freeze through the internal `/accounts/freeze-status` route is recorded "so the app shows it", so it also reads as `frozen`.
- Use these customer-scoped `/me` routes. Do not use the internal `/accounts/freeze-status` or account-management routes. This is a per-account feature, not a global account-wide toggle.

### How Core rejects debits from a frozen account

These shape where the app's guards go and which Core rejections already cover a race:

| Debit | Route | Documented frozen response |
| --- | --- | --- |
| Intrabank and interbank transfers | `initiate` → `pin/verify` → `otp/verify` → `finalize` | Nothing at `initiate`. `finalize` answers `403` "The account is restricted or locked, or the initiation has expired"; the app already maps it to `CoreRejection.transferRestricted`. |
| Bill payment | `POST /me/bills/payments` | `403` "The caller's BocFlex account is frozen or otherwise restricted"; already mapped to `CoreRejection.accountRestricted`. |
| Savings plan top-up | `POST /me/savings-plans/{planId}/fund` | None. Its `403` means the plan is matured, liquidated or cancelled, so do not read it as frozen. |
| Savings plan creation (SmartSave, Fixed Deposit) | `POST /me/savings-plans` | None; Core funds the plan from Boc Flex. |

Savings plan liquidation returns the principal *to* Boc Flex. It is incoming money and stays allowed while frozen.

## Implementation changes

### Service and state

- Add encoded path builders, typed result models, and Core service methods for the three routes. Validate that `accountNumber` is one uniquely owned ten-digit Core account before any write. Never persist PIN or OTP in a provider, route, log, or analytics event. Use the existing secret redaction behavior for request logging.
- Add an account-scoped freeze controller with idle, sending OTP, awaiting OTP, submitting, and error states. Allow only one mutation per account at a time. A completed mutation triggers `GET /me/bank-accounts/{accountNumber}` and refreshes the shared account list; the refreshed Core status, not a local optimistic flag or the Swagger example's status value, determines the visible state.
- Keep the `frozenBy` from a freeze/unfreeze reply in memory for the session. When it is `admin`, show the support path straight away instead of waiting for an OTP `403`. After a restart the app cannot know, and the `403` path below applies.
- For freeze `401`, keep the PIN sheet open with "That PIN is not correct." For unfreeze `401`, keep the PIN and code form open with "The PIN or code is not correct." and offer "Send a new code", which calls `unfreeze/otp` again. For `403`, stop the unfreeze flow and show "This account was frozen by the bank. Contact support to unfreeze it." For freeze `404`, remove the action and refresh the account list. For `409` or an uncertain network result, fetch the account status before offering another mutation; never automatically retry a freeze/unfreeze POST. If the refresh fails, show "Account status could not be confirmed" with an explicit refresh action.
- Register `FeatureCapability.freezeAccount` with the three write routes plus `GET /me/bank-accounts` and `GET /me/bank-accounts/{accountNumber}`, which the flow reads. Register it only when the service, controller, and UI are ready, and remove the Security Center placeholder assertion. It is `stagingOnly: true` (Kenechukwu, 17 October 2026), like the other Core write capabilities; production release is a separate decision. Clear account-scoped freeze state on logout or user switch.

### Account selectors

`CustomerBankAccountsData.activeFlexAccount` returns null for a frozen account, so every reader of it currently treats a frozen customer as having no Boc Flex account. Add a `flexAccount` getter (the single Flex account in any status, null when absent or ambiguous) and move each call site to the right selector:

| Call site | Purpose | Selector |
| --- | --- | --- |
| `resolveFlexBalance` in `core_banking/model/flex_balance.dart` (used by Home and `savings_screens.dart`) | Show the balance | `flexAccount`; never fall back to the User wallet when it exists |
| `home_screen.dart` transactions section and pull-to-refresh history | Show history | `flexAccount` |
| `send/screens/transaction_flow_screens.dart` transaction history | Show history | `flexAccount` (otherwise a frozen customer sees "You have no Boc Flex account yet") |
| `core_banking/screens/bank_account_detail_screen.dart` | Show account detail | `flexAccount` |
| `refreshFlexTransactionHistoryProvider` in `core_account_activity_providers.dart` and `savings_plan_action_provider.dart` `_refresh` | Refresh history after money moves | `flexAccount` |
| `interbank_transfer_screen.dart` and `bill_payment_screen.dart` amount steps | Spending limit | `activeFlexAccount`, behind the frozen-source guard below |

### Security Center and account pages

- Replace the single disabled Security Center toggle with a "Freeze an account" entry. Open an account-specific page/list of owned Core accounts showing each current status. An active account offers "Freeze account"; a frozen account offers "Request unfreeze"; closed/unknown accounts have no action. Do not imply a bank-frozen account can be self-unfrozen.
- Freezing requires a confirmation explaining that outgoing money is blocked, then the existing `collectCoreTransactionPin` sheet (`core_banking/screens/transaction_pin_sheet.dart`) with `confirmLabel: 'Freeze account'`. Unfreezing requests the OTP, collects the PIN with the same sheet (`confirmLabel: 'Continue'`), then collects the six-digit code. Reuse `TransferOtpSheet` if its `verifyCode`/`resendCode` callbacks fit the single unfreeze POST; otherwise add a small sheet in the same style. Show the code's expiry when `otpExpiresAt` is present. Cancel closes the flow without another write. The customer's balance, history, and account number remain available while frozen.
- Show "Frozen" on the account detail, keep history visible, and suppress outbound actions there.

### Home wallet treatment

- Add a subtle frozen variant to `BalanceCard`: muted cool-blue tint, a thin frost-like edge or translucent accent, and a lock/snowflake icon with the visible label "Boc Flex account frozen". Place the treatment behind or beside the balance so it does not obscure amounts, eye/copy controls, or text. Expose the status in semantics and use text plus icon, not color alone. No frozen styling appears for the separate User Service wallet or for unknown status. Keep the balance-hidden control and funding details usable.
- Immediately below a frozen Boc Flex card, show a compact status banner: "Your Boc Flex account is frozen. Transfers and other outgoing payments are paused." Its "Unfreeze account" button opens the unfreeze flow for that exact account number, sending the OTP only after the customer taps through. Keep the banner visible until a refreshed Core account read reports `active`; a button tap or OTP send must not dismiss it. When the session knows `frozenBy: admin`, or Core returns the unfreeze `403`, change its action to "Contact support".

### Outgoing guards

- **Why the guard is needed:** transfer requests carry no source account, and the amount steps take their limit from `activeFlexAccount?.availableBalance`. For a frozen account that limit is null, so `amountWithin` checks nothing and the flow runs until Core rejects it at `finalize`.
- Add one shared frozen-source check that reads the Boc Flex status from the account list. Apply it:
  - on Home and Send transfer entry points, showing "Transfers paused while Boc Flex is frozen" instead of starting the flow;
  - before intrabank and interbank `initiate`, using a fresh `GET /me/bank-accounts/{accountNumber}`. If the status is frozen, unknown, or cannot be confirmed, send no `initiate`;
  - before bill payment submit;
  - before savings plan top-up and SmartSave/Fixed Deposit creation. Core documents no frozen rejection for these, so this check is the only thing that turns a frozen account into clear feedback.
- Leave savings plan liquidation, incoming funding, balance viewing, history and status checks available. Show an explanation when a customer attempts a blocked action rather than hiding the destination.
- When a transfer `finalize` returns `403` or a bill payment returns `403`, refresh the account list so a freeze made on another device shows on Home. Do not cancel or reinterpret a transfer already finalized or awaiting external confirmation.
- No foreground-resume refresh: the fresh read before `initiate` and Core's `finalize` rejection already cover a freeze from another device.

## Tests and acceptance

One focused test per behavior, no matrices:

- Service: freeze and unfreeze send the encoded path and body; the unfreeze OTP reply's `otpCode` is dropped.
- Controller: unfreeze `403` stops the flow and shows the support path; `409` re-reads the account status and sends no second POST.
- Selectors: a frozen Core Flex account keeps its balance on Home and never falls back to the User wallet; transaction history still loads for it.
- Guard: a frozen Boc Flex account sends no transfer `initiate`.
- Home: a frozen Flex card shows the frozen label and banner, and the banner's button opens unfreeze for that account number.
- A staged device check should freeze and unfreeze a disposable customer-owned account, verify Core status after each step, check the Home card and transfer block, and confirm a bank-frozen `403` is presented without another unfreeze attempt.

## Assumptions

- The Home wallet card represents Boc Flex when a Core Flex account exists; a separate User Service wallet is shown only when no unique Core Flex account exists.
- "Freeze account" applies to one owned Core account at a time. The Home treatment is shown only when the Core Boc Flex account is frozen.
- Core enforces debit rejection. Client checks prevent avoidable attempts and give clear feedback; they are not the security boundary.

## Global Constraints

- The Core Swagger (https://core-dev-api.centurysoftware.dev/api/v1/docs/) is the contract authority; the "Core contract and scope" and "How Core rejects debits" sections above summarize it.
- Never persist or log a transaction PIN or OTP code: not in a provider's state, a route argument, a log line or an analytics event. The caller holds it only for the one request.
- Tests are minimal and strictly necessary: one focused test per behavior named in the task, no status-code matrices, no theme or masked/unmasked permutations, no new fake infrastructure unless the task names it.
- Match the surrounding code: Riverpod `NotifierState`, `SessionScopedNotifier`, `CoreApiEndpoints` builders with `...Template` constants for capability registration, existing sheet widgets, comment density and naming.
- `FeatureCapability.freezeAccount` is `stagingOnly: true`.
- Each task ends with `flutter analyze` clean and the touched tests passing (`flutter test <files>`).

## Tasks

### Task 1: Flex account selectors for frozen accounts

Context: `CustomerBankAccountsData.activeFlexAccount` (`lib/module/core_banking/model/customer_bank_account_models.dart`) returns null when the single Flex account is frozen, so every reader treats a frozen customer as having no Boc Flex account.

Do:
- Add a `flexAccount` getter on `CustomerBankAccountsData`: the single Flex account (`productCode == kFlexProductCode`) in any status, null when absent or ambiguous. Keep `activeFlexAccount` for spending and define it in terms of `flexAccount`.
- Change `resolveFlexBalance` (`lib/module/core_banking/model/flex_balance.dart`) to use `flexAccount`, so a frozen Core Flex account keeps its balance and the User Service wallet is never used when a Core Flex account exists. Expose the account status on `FlexBalance` (e.g. an `isFrozen` flag) for Task 5's card. Update its doc comment.
- Move these display/history readers to `flexAccount`: `home_screen.dart` transactions section and pull-to-refresh history; `send/screens/transaction_flow_screens.dart` transaction history; `core_banking/screens/bank_account_detail_screen.dart` `_accountNumber`; `refreshFlexTransactionHistoryProvider` in `core_banking/provider/core_account_activity_providers.dart`; `_refresh` in `savings/provider/savings_plan_action_provider.dart`.
- Leave `activeFlexAccount` in the amount steps of `interbank_transfer_screen.dart` and `bill_payment_screen.dart` (Task 6 guards them).

Tests (one each): a frozen Core Flex account resolves to its Core balance and not the User wallet; `flexAccount` returns a frozen account while `activeFlexAccount` returns null.

### Task 2: Core freeze service

Do:
- Add to `CoreApiEndpoints` (`lib/app/core_api_endpoints.dart`), following the existing `bankAccount(...)` pattern: `bankAccountFreeze(n)` → `/me/bank-accounts/{n}/freeze`, `bankAccountUnfreezeOtp(n)` → `.../unfreeze/otp`, `bankAccountUnfreeze(n)` → `.../unfreeze`, each with a `...Template` constant using `{accountNumber}`, and add the templates wherever the other Core templates are listed.
- Add typed models in `lib/module/core_banking/model/`: `AccountFreezeResult` (`accountNumber`, `status` as the existing `CoreAccountStatus`, nullable `frozenBy` enum `customer`/`admin`/unknown, nullable `frozenAt`) and the unfreeze OTP reply (`otpSent`, nullable `otpExpiresAt`). Never parse or keep the staging-only `otpCode`.
- Add a typed outcome for the three writes: success (with the result), wrong credentials (`401`), bank-frozen (`403`), not found (`404`), conflict (`409`), and uncertain (network failure, timeout, or any other status). Model it in the style of the existing Core submission/rejection types (`core_submission_models.dart`).
- Add `freezeAccount(accountNumber, transactionPin)`, `sendUnfreezeOtp(accountNumber)` and `unfreezeAccount(accountNumber, transactionPin, otpCode)` to `CoreAccountService`. Body keys exactly `transactionPin` and `otpCode`; OTP send has no body. Before any write, refuse an `accountNumber` that is not exactly ten digits. Never retry a POST.
- Do not register the capability yet (Task 4 does).

Tests (one each): freeze and unfreeze send the encoded path and exact body; the OTP reply drops `otpCode`; a `403` maps to bank-frozen.

### Task 3: Account freeze controller

Depends on Task 2's service and outcome types.

Do:
- Add an account-scoped controller (Riverpod family keyed by account number, in `lib/module/core_banking/provider/`) with states: idle, sendingOtp, awaitingOtp (with `otpExpiresAt`), submitting, and error (with a safe message and kind). Only one mutation per account at a time: a second call while one is in flight is ignored.
- It never stores the PIN or OTP; methods take them as arguments for the one request.
- After a success, `409`, or uncertain outcome, refresh that account (`customerBankAccountsProvider.notifier.refreshAccount`, falling back to `load()` when the list is not loaded) and let the refreshed Core status decide what is shown. If that refresh fails, enter an error with "Account status could not be confirmed" and expose a refresh action. Never re-send the POST automatically.
- `401` on freeze → error "That PIN is not correct."; on unfreeze → "The PIN or code is not correct." and stay able to resend the code (calling `unfreeze/otp` again). `403` → bank-frozen state with "This account was frozen by the bank. Contact support to unfreeze it." `404` on freeze → reload the account list.
- Remember `frozenBy` from a freeze/unfreeze reply (and bank-frozen from a `403`) in memory for the session, readable by account number, so Task 5's banner can show "Contact support".
- Clear all of this on logout or user switch, the same way `SessionScopedNotifier` providers are cleared.

Tests (one each): an unfreeze `403` ends in the bank-frozen state; a `409` re-reads the account and sends no second POST.

### Task 4: Security Center freeze flow and capability

Depends on Tasks 1–3.

Do:
- Register `FeatureCapability.freezeAccount` in `lib/app/feature_capability.dart` with `stagingOnly: true` and operations: `POST` freeze, unfreeze/otp and unfreeze templates, `GET CoreApiEndpoints.bankAccounts`, and `GET` the single-account template (add a `bankAccountTemplate` if none exists). Add a short comment like the neighbours'.
- In `lib/module/account/screens/account_control_screens.dart`, remove `freezeAccount` from the placeholder assertion list and replace the disabled "Freeze account" toggle with a "Freeze an account" `SettingsTile` that opens a new account-freeze page when the capability is available (otherwise keep the "Not available yet" tag and no action).
- The page lists the customer's Core accounts (`customerBankAccountsProvider`) with product name, masked account number, and status. Active → "Freeze account"; frozen → "Request unfreeze"; closed/unknown → no action; bank-frozen (known from Task 3) → "Contact support" explanation. Register a route the way neighbouring account pages are registered.
- Freeze: a confirmation that outgoing money is blocked while balance and history stay visible, then `collectCoreTransactionPin` (`core_banking/screens/transaction_pin_sheet.dart`) with `confirmLabel: 'Freeze account'`, a loading state, and the controller's error copy re-shown in the PIN sheet on `401`.
- Unfreeze: send the OTP through the controller, collect the PIN with the same sheet (`confirmLabel: 'Continue'`), then the six-digit code. Reuse `TransferOtpSheet` if its callbacks fit the single unfreeze POST; otherwise add a small sheet in the same style with "Send a new code". Show the expiry when `otpExpiresAt` is present. Cancel closes without another write.
- On `bank_account_detail_screen.dart`, show a "Frozen" status label for a frozen account, keep history visible, and hide any outbound actions there.
- Export a function to open the unfreeze flow for a given account number from anywhere (Task 5's banner uses it).

Tests (one): from Security Center, freezing an active account collects the PIN and calls the controller with that account number.

### Task 5: Home frozen wallet card and banner

Depends on Task 1 (`FlexBalance` status), Task 3 (bank-frozen memory) and Task 4 (open-unfreeze function).

Do:
- Add a frozen variant to `BalanceCard` (`lib/module/component/cards.dart`): muted cool-blue tint, a thin frost-like edge or translucent accent, and a lock or snowflake icon with the visible label "Boc Flex account frozen". It must not cover amounts, the hide/eye control, copy controls or text, and must work in light and dark themes using existing theme tokens. Add the status to semantics. No frozen styling for the User Service wallet or unknown status.
- In `home_screen.dart`, pass the frozen state from `resolveFlexBalance` to the card, and directly below it show a compact banner: "Your Boc Flex account is frozen. Transfers and other outgoing payments are paused." with an "Unfreeze account" button that opens the unfreeze flow for that account number (sending the OTP only after the customer goes through). The banner stays until a refreshed Core read reports `active`. When the account is known bank-frozen, the button becomes "Contact support" and opens the app's existing support destination.

Tests (one): a frozen Flex account on Home shows the frozen label and the banner, and tapping "Unfreeze account" opens the unfreeze flow for that account number.

### Task 6: Frozen-source guards on outgoing payments

Depends on Task 1.

Context: transfer requests carry no source account; amount steps take their limit from `activeFlexAccount?.availableBalance`, which is null for a frozen account, so today the flow runs until Core rejects it at `finalize` (`403`, already mapped to `CoreRejection.transferRestricted`). Bill payment `403` means frozen and maps to `CoreRejection.accountRestricted`. Savings top-up (`POST /me/savings-plans/{planId}/fund`) and plan creation (`POST /me/savings-plans`) document no frozen rejection; the fund `403` means the plan is matured/liquidated/cancelled and must not be read as frozen. Liquidation pays into Boc Flex and stays allowed.

Do:
- Add one shared frozen-source check (in `lib/module/core_banking/`) that reports whether the Boc Flex account can be debited: allowed only when `flexAccount` exists and is `active`. A variant that first does a fresh `GET /me/bank-accounts/{accountNumber}` (via `refreshAccount`) treats a failed read as blocked.
- Transfer entry points on Home and Send: when frozen, show "Transfers paused while Boc Flex is frozen" instead of starting the flow.
- Before intrabank/interbank `initiate` in `core_transfer_attempt_provider.dart`, run the fresh check; if frozen, unknown, or unconfirmed, send no `initiate` and surface the paused message.
- Before bill payment submit, before savings plan top-up (`fund`) and before plan creation (`create`) in `savings_plan_action_provider.dart`, run the check and show an explanation instead of sending.
- When a transfer `finalize` or a bill payment returns `403`, reload `customerBankAccountsProvider` so a freeze from another device shows on Home.
- Do not cancel or change a transfer already finalized or awaiting confirmation. No foreground-resume refresh.

Tests (one each): a frozen Boc Flex account sends no transfer `initiate`; savings `fund` is not sent while frozen.

## Addendum: frozen savings accounts (17 October 2026)

Kenechukwu asked for the frozen UI in the Save section, including savings accounts frozen individually.

- Each savings product the customer holds (SmartSave, Fixed Deposit) has its own Core account in `GET /me/bank-accounts`, with its own `status`. `GET /me/savings-plans` groups plans by product and gives each group's `accountNumber`; `SavingsPlanDetail` also carries `accountNumber`. The freeze routes accept any owned account number, so the Security Center page already lets a customer freeze a savings account on its own.
- A freeze "stops any money leaving the account". For a frozen savings account that pauses plan withdrawal/liquidation (`POST /me/savings-plans/{planId}/liquidate` pays from the product account into Boc Flex). Core documents no frozen response for it; its `403` means the plan is matured/liquidated/cancelled. Top-ups and plan creation pay *into* the savings account and stay allowed (they are still blocked when Boc Flex itself is frozen, by Task 6).

### Task 7: Frozen account UI in the Save section

Context: Home already shows a frozen Boc Flex card variant and a banner (`_frozenBanner` in `lib/module/home/screens/home_screen.dart`), gated on `FeatureCapability.freezeAccount` and on bank-frozen memory (`accountFreezeMemoryProvider`), with `openUnfreezeFlow(context, ref, accountNumber)` (lib/module/core_banking/screens/account_freeze_flow.dart) and `AppRoutes.support`.

Do:
- Extract the Home banner into one reusable widget (e.g. `FrozenAccountBanner`, in `lib/module/component/` or `lib/module/core_banking/screens/`) taking the account number and its message. It keeps the existing rules: shown only while Core reports the account frozen; "Unfreeze account" calls `openUnfreezeFlow` only when `freezeAccount` is available and the account is not known bank-frozen; otherwise "Contact support" opens `AppRoutes.support`. Home uses it with its existing copy, unchanged.
- Save hub (`_saveHubScreen` in `lib/module/savings/screens/savings_screens.dart`): the Boc Flex tile (`FlexSavingsTile`, lib/module/component/savings_widgets.dart) and each other Core account tile (`_coreAccountTile`) show a visible "Frozen" label with a lock icon (text plus icon, in semantics) when that account's status is frozen. Below a frozen tile, show the banner. Flex copy: "Your Boc Flex account is frozen. Transfers and other outgoing payments are paused." Savings account copy: "Your {product name} account is frozen. Withdrawals are paused."
- Boc Flex Save page (`_flexScreen`): show the Flex banner when frozen.
- Product plans page (`_plansList` in `lib/module/savings/screens/savings_plan_screens.dart`): when the group's account (matched by `group.accountNumber` in the account list) is frozen, show the "Frozen" label on the product card and the savings banner below it.
- Plan detail (`_savingsPlanDetailScreen`): when the plan's product account (`SavingsPlanDetail.accountNumber`, else the group's) is frozen, show the savings banner. Balances, plan details, events and interest history stay visible.
- Use existing theme tokens; must read in light and dark.

Tests: none (bare-minimum tests rule, Kenechukwu 17 October 2026). Keep existing tests green.

### Task 8: Pause withdrawals from a frozen savings account

Depends on Task 7.

Do:
- Generalize the Task 6 fresh check (`lib/module/core_banking/provider/flex_source_check.dart`) so it can check any account number, not only Boc Flex, keeping the Boc Flex behaviour unchanged: active → allowed; frozen → frozen; closed/unknown status or a failed/unconfirmed read → unconfirmed. Unknown/absent account number → allowed (Core stays the authority).
- In `savings_plan_action_provider.dart`, before `liquidate` sends, run the check on the plan's product account. Frozen → do not send; fail with "This savings account is frozen. Withdrawals are paused." Unconfirmed → do not send; fail with "We could not confirm this account's status. Try again." The liquidate `403` mapping is unchanged (never read as frozen). `fund` and `create` keep only their Boc Flex check.
- On plan detail, when the product account is frozen, the "Withdraw" menu item shows that frozen message instead of opening the withdraw sheet.
- The action provider needs the product account number for `liquidate`: pass it from the screen (plan detail already has it) rather than adding a new fetch.

Tests (one): `liquidate` sends nothing and fails with the frozen message while the plan's product account is frozen.
