# Savings Plan UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the SmartSave and Fixed Deposit confirm step, plan detail and deposit success sheet into a hierarchy where each screen leads with one main element and puts the supporting facts in groups below it. Today each of these screens is a flat grid of equal tiles.

**Architecture:** Add a separate savings widget library (`savings_plan_widgets.dart`) with a pure progress helper. The existing `part` screens and the top-up sheet compose it. Everything shown comes from Core fields that Core documents. The client derives only a display ratio for the progress bar. `SavingsPlan` gains the four documented fields the UI now shows.

**Tech Stack:** Flutter, Riverpod, `iconsax_plus`, existing `BocSpace`/`BocRadius`/`context.bocColors` tokens, `formatApiAmount`.

**Spec:** this plan replaces the earlier design note at the same path. Core contract: `SavingsPlanSummary` and `SavingsPlanEvent` in the Core API docs (`/api/v1/docs/`).

## Core facts this UI is built around

Taken from the staging create response for "Rent" (2026-10-14) and the Core docs:

- `POST /me/savings-plans` "funds it from BocFlex with the minimum amount for the product and tenor". The minimum lives in admin-only rate bands, so the app cannot know it before creating. Create "Rent" asked for target `4500.00` and came back with `principalAmount: "5000.00"`, so **a new plan can already be above its target**.
- The plan carries `startDate`, `saveFrequency` (`daily|weekly|monthly`, nullable), `recurringAmount` (nullable), `projectedInterestAtMaturity` (nullable, "Estimated interest at maturity"), `currentInterestRatePercent` (`"10.000"`), `accruedInterest`, `interestEarned`.
- Events come newest first. The `created` event has `amount: "0.00"`, and the initial funding arrives as a `top_up` event.
- `GET /me/bank-accounts` returns `availableBalance` as grouped strings (`"84,379.24"`), which the model already normalizes. `totalAvailableBalance` (`89`) is wrong and stays ignored.

## Global Constraints

- **Padi is out of scope.** Its wizard steps and its confirm step keep today's `BocSummaryGrid`. Flex screens are unchanged.
- Every plan amount shown on detail and in the success sheet goes through the hidden-balance preference (`homeBalanceHiddenProvider`, mask `₦ ••••••`).
- Money is formatted only from Core decimal strings with `formatApiAmount(value, currency: 'NGN')`. Never show a computed amount.
- No new packages, colours or fonts. SmartSave uses `smartSaveAccent`/`smartSaveContainer`, Fixed uses `fixedAccent`/`fixedContainer`, and navy text anchors both.
- Label/value rows stack the value under the label when `MediaQuery.textScalerOf(context).scale(1) > 1.3`, the same threshold `BocSummaryGrid` uses.
- Tests stay minimal: one test per behaviour, and existing tests are updated rather than duplicated.
- Figma doesn't block this work. The final visual check against Figma and the device check (Pixel 7 Pro, `flutter run -d 2B161FDH30033N --dart-define-from-file=.env.stage`) are done by Kenechukwu after Task 5.

## Review Focus

1. **Plan created above target** (Core minimum > target): detail says "Target reached" with a full bar and the true amounts. Pinned in Task 3.
2. **Balances hidden:** no amount and no progress bar, because the bar reveals the ratio. Pinned in Task 3.
3. **`created` event with `0.00`:** the row shows no amount. Pinned in Task 3.
4. **Auto-save off:** confirm says "Manual deposits" and explains the Flex funding. Pinned in Task 4.
5. **Success sheet with balances hidden:** neither the deposited amount nor the new balance shows. Pinned in Task 5.

---

### Task 1: Parse the plan fields the UI shows

**Files:**
- Modify: `lib/module/savings/model/savings_plan_models.dart` (`SavingsPlan`, ~78–155)
- Test: `test/core_savings_plan_test.dart`

**Interfaces:**
- Produces on `SavingsPlan`: `DateTime? startDate`, `SavingsFrequency? saveFrequency`, `String? recurringAmount` (Naira), `String? projectedInterest` (Naira). All are nullable and included in `props`.

- [ ] **Step 1: Write the failing test** `'a plan reads its schedule and projected interest'`. Pass `SavingsPlan.tryParse` the "Rent" create `data` object above, without its events. Assert `startDate == DateTime(2026, 10, 14)`, `saveFrequency == SavingsFrequency.daily`, `recurringAmount == '550.00'`, `projectedInterest == '110.96'`, `target == '4500.00'`, `principal == '5000.00'`.
- [ ] **Step 2: Run** `flutter test test/core_savings_plan_test.dart`. Expected: FAIL (getters not defined).
- [ ] **Step 3: Implement.** Use `coreNaira` for both amounts and `DateTime.tryParse(coreText(...) ?? '')` for the date. Read the frequency with `SavingsFrequency.values.asNameMap()[coreText(json['saveFrequency'])]`, because the wire values equal the enum names.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat(savings): read a plan's schedule and projected interest from Core`.

### Task 2: Savings plan presentation widgets

**Files:**
- Create: `lib/module/savings/screens/savings_plan_widgets.dart` (its own library, not a `part`; imports `app/theme.dart`, `app_flow/app_ui.dart`, `iconsax_plus`)
- Test: `test/savings_plan_widgets_test.dart`

**Interfaces:**
- Produces:
  - `typedef SavingsPlanProgress = ({double fraction, bool reached});`
  - `SavingsPlanProgress? savingsPlanProgress({String? principal, String? target})`: null when either value is null or unparseable, or when target ≤ 0. `fraction` is clamped to 0..1, and `reached` is `principal >= target`.
  - `class SavingsPlanHero extends StatelessWidget({required String status, required String amount, required Color accent, required Color container, String? rate, String? progressLabel, SavingsPlanProgress? progress})`: an accent-tinted container (`BocRadius.lg`) with a status chip, the amount in `BocMoneyText` (`semanticsLabel: 'Plan balance'`), the optional rate line, and a `LinearProgressIndicator` plus `progressLabel` when `progress != null`.
  - `class SavingsFactGroup extends StatelessWidget({required String title, required List<({String label, String value})> rows})`: a header (`Semantics(header: true)`) and a `surface` card of aligned rows with dividers. Renders `SizedBox.shrink()` when `rows` is empty.
  - `class SavingsActivityRow extends StatelessWidget({required IconData icon, required String label, String? date, String? amount})`: at least `BocSpace.minTouch` tall and wrapped in `MergeSemantics`.
  - `class SavingsCallout extends StatelessWidget({required IconData icon, required String title, required String body})`: on `infoContainer`.

- [ ] **Step 1: Write the failing test** `'progress is only for a usable target'`. Assert:
  - `('2500.00', '5000.00')` → `(fraction: 0.5, reached: false)`
  - `('5000.00', '4500.00')` → `(fraction: 1.0, reached: true)`
  - `('5000.00', '0.00')` → `null`
  - `(null, '4500.00')` → `null`
- [ ] **Step 2: Run** `flutter test test/savings_plan_widgets_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the helper and the four widgets. The widgets get no tests of their own; Tasks 3–5 exercise them through the screens.
- [ ] **Step 4: Run** the same command and `flutter analyze lib/module/savings`. Expected: PASS, no issues.
- [ ] **Step 5: Commit** `feat(savings): add plan hero, fact group, activity row and callout`.

### Task 3: Plan detail

**Files:**
- Modify: `lib/module/savings/screens/savings_plan_screens.dart` (detail `ListView` children, ~232–286), `lib/module/savings/screens/savings_screens.dart` (import the widgets library)
- Test: `test/savings_plans_ui_test.dart`

**Interfaces:**
- Consumes: Task 1 fields and all of Task 2.

Layout, top to bottom, for SmartSave and Fixed:
- **Hero:**
  - `status: plan.status.label`, `amount: _planMoney(plan.principal)`, `rate: '$rate% per annum'`, and the product accent and container colours.
  - Progress only when the type is SmartSave **and** balances are not hidden **and** `savingsPlanProgress(...)` is non-null. `progressLabel` is `'Target reached'` when `reached`, otherwise `'${_planMoney(principal)} of ${_planMoney(target)} target'`.
- **`SavingsFactGroup('Your plan')`:**
  - Target (SmartSave)
  - Auto-save: `'${_planMoney(recurringAmount)} ${frequency.label.toLowerCase()}'` when both are present; `'Manual deposits'` for SmartSave without them; omitted for Fixed
  - Started
  - Matures
  - Tenor (`'$days days'`)
- **`SavingsFactGroup('Interest')`:**
  - Interest so far (`accruedInterest`)
  - Interest earned (`interestEarned`)
  - Projected at maturity (`projectedInterest`)
- **Activity:** server order. Icons, with signs for money in and out:

  | Event | Icon | Sign |
  |---|---|---|
  | `topUp` | `add_circle` | `+` |
  | `interestCredit` | `percentage_circle` | `+` |
  | `withdrawal`, `maturityPayout`, `liquidation` | `export` | `−` |
  | `created` | `flag` | none |
  | `unknown` | `activity` | none |

  Leave the amount out when it is null or `'0.00'`. Leave the sign out when balances are hidden. Dates use the local `d MMM yyyy` format.
- The popup menu, capability gates, pull-to-refresh and the sticky Deposit footer stay as they are.

- [ ] **Step 1: Update and write the failing tests.**
  - Rename `'plan detail shows interest so far'` to `'a plan above its target says so'`. Use `principal: '5000.00'`, `target: '4500.00'`, `accruedInterest: '0.00'`, and events `[topUp 5000.00, created 0.00]`. Expect `'Target reached'`, one `LinearProgressIndicator`, `'+₦5,000.00'`, `'Interest so far'`, and `find.text('₦0.00')` once (interest only, not the created row).
  - In `'SmartSave lists server plans and opens one'`, change `'₦2,500.00'` to `'+₦2,500.00'`.
  - Add `'hidden balances hide the amounts and the progress'`, which uses the same above-target detail and overrides `homeBalanceHiddenProvider` with a `HomeBalanceHiddenNotifier` subclass whose `build()` returns `true`. Expect `find.byType(LinearProgressIndicator)` to find nothing and `find.textContaining('5,000')` to find nothing.
- [ ] **Step 2: Run** `flutter test test/savings_plans_ui_test.dart`. Expected: the three tests above FAIL.
- [ ] **Step 3: Implement** the layout above, replacing `BocSummaryGrid` and the `ListTile` loop on the detail screen.
- [ ] **Step 4: Run** `flutter test test/savings_plans_ui_test.dart` and `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(savings): lead plan detail with balance and progress`.

### Task 4: Confirm step (SmartSave and Fixed)

**Files:**
- Modify: `lib/module/savings/screens/savings_plan_screens.dart` (`case _WizardStep.confirm`, ~876–943)
- Test: `test/savings_plans_ui_test.dart`

**Interfaces:**
- Consumes: `SavingsFactGroup` and `SavingsCallout` from Task 2.

For `widget.type == SavingsProductType.padi`, return today's children unchanged. Otherwise:
- **Heading:** `_heading(theme, 'Review your goal', 'Check the details before you create it.')` for SmartSave, and `'Review your deposit'` for Fixed. The Fixed "Deposit name" field stays first.
- **SmartSave summary surface** (`smartSaveContainer`, `BocRadius.lg`): the goal name in `titleLarge`, then the target as `formatApiAmount(savingsPlanNaira(_draft.amount), currency: 'NGN')` in FH Oscar figures.
- **`SavingsFactGroup('Saving plan')`:**
  - Duration (or Term for Fixed): `'$months months'`
  - For SmartSave, either:
    - Auto-save: `'${formatted recurringAmount} ${frequency.label.toLowerCase()}'` when `_draft.autoSave`, or
    - `'Manual deposits'`
- **Funding:** `SavingsCallout(icon: IconsaxPlusLinear.wallet_2, title: 'Funded from Boc Flex Savings', body: …)`:
  - Body (SmartSave and Fixed): `"When you create it, we'll move the opening amount for this term from Boc Flex Savings."` (Whether the opening amount can exceed the target is pending backend clarification, so the copy does not claim it.)
- The Create and Edit actions, the failure message and the unconfirmed handling stay as they are.

- [ ] **Step 1: Write the failing test** `'the goal review explains manual saving and funding'`. Use `walkGoalWizard` (auto-save is off). Expect `'Review your goal'`, `'₦200,000.00'`, `'Manual deposits'`, `'Funded from Boc Flex Savings'`, and `find.textContaining('opening amount for this term')`.
- [ ] **Step 2: Run** `flutter test test/savings_plans_ui_test.dart`. Expected: the new test FAILS.
- [ ] **Step 3: Implement** the layout above.
- [ ] **Step 4: Run** `flutter test test/savings_plans_ui_test.dart` and `flutter analyze`. Expected: all pass, including `'creating a goal opens the new plan'` and `'a term Core does not offer keeps the draft'`.
- [ ] **Step 5: Commit** `feat(savings): review a goal's schedule and funding before creating it`.

### Task 5: Deposit success sheet

**Files:**
- Modify: `lib/module/savings/screens/savings_plan_top_up_sheet.dart`
- Test: `test/savings_plans_ui_test.dart`

**Interfaces:**
- Consumes: nothing new; reads `homeBalanceHiddenProvider`.

- In `_submit`, store the validated `koboToNaira(minorUnits)` in a new `String? _submitted` before calling `fund`.
- `done` phase:
  - `AppActionSheet(icon: IconsaxPlusLinear.tick_circle, title: 'Money added', subtitle: 'Added to ${widget.planName} from Boc Flex Savings')`.
  - Body:
    - `BocMoneyText(formatApiAmount(_submitted, currency: 'NGN'), hidden: hidden, semanticsLabel: 'Amount added')`
    - then, only when `result.principalAmount` is present, a row `'New plan balance'` with that amount, masked when hidden.
  - Footer stays a single `Done`. Unknown and failed phases are unchanged.

- [ ] **Step 1: Update and write the failing tests.**
  - Extend `'depositing into a plan sends the typed amount'` to also expect `'₦2,500.00'`, `'New plan balance'` and `'₦7,500.00'`.
  - Add `'a hidden balance stays hidden after a deposit'`, which repeats the deposit with the hidden override from Task 3 and expects `find.textContaining('7,500')` and `find.textContaining('2,500.00')` to find nothing.
- [ ] **Step 2: Run** `flutter test test/savings_plans_ui_test.dart`. Expected: both FAIL.
- [ ] **Step 3: Implement** the sheet changes above.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(savings): show the amount added apart from the new plan balance`.

### After Task 5 (Kenechukwu, on device)

On staging, create a SmartSave goal with a target below the opening amount and auto-save on, then deposit. Check on the device:
- the confirm and detail screens in light, dark and 2× text
- a long plan name
- hidden balances
- that closing the success sheet refreshes the plan

Compare against the project Figma before sign-off.
