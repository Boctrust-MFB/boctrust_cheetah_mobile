# Code Cleanup Implementation Plan

> **For agentic workers:** Execute with `superpowers:subagent-driven-development` (fresh implementer + task reviewer per task, final whole-branch review). Steps use checkbox syntax for tracking.

**Goal:** Remove confirmed app-dead code and assets, fix inconsistent PIN/OTP response handling, and consolidate duplicated logic without changing user-visible behavior, Core API routes, or money movement.

**Architecture:** Keep flow-specific state and wording in the existing providers and sheets. Extract only shared policy (check-response consistency, biometric outcome mapping), shared presentation (transaction summary, KYC status block), and shared plumbing (Dio construction, recovery-flow data) used by two or more call sites.

**Tech Stack:** Flutter, Dart, Riverpod.

**Spec:** Scope comes from the 2026-10-23 codebase review (findings below). Core API docs settle any contract question.

## Global Constraints

- Preserve the existing Core API routes, request bodies, phase names, and money movement behavior.
- Never retain PIN or OTP values in provider state.
- Preserve password-specific and PIN-specific biometric fallback wording.
- Keep error messages and buttons specific to each confirmation sheet and flow.
- **Tests: none** unless stated in a task. Only Task 3 adds one test (it guards a money/security boundary). When a task deletes app-dead code, delete the tests that only exercise it. No matrices, no UI-only tests, no new fakes.
- `flutter analyze --no-pub` must stay clean after every task.

## Review Findings (2026-10-23)

Baseline: `flutter analyze --no-pub` reports no issues; there are no TODOs, stray `print`s or commented-out code. Only `lib/utils/form_helpers.dart` is unreachable from `lib/main.dart`; every pubspec dependency is used.

| # | Finding | Evidence | Task |
|---|---------|----------|------|
| F1 | `validateAndSave` is test-only | Only `test/widget_test.dart` references it | 2 |
| F2 | Dead validators/utils | Unused in `lib`: `billCustomerReference`, `merchantCode`, `formatPhoneWithDashes`, `normalizePhoneNumber`, `notificationDateGroup`. Test-only: `nigerianPhone`, `optionalName`, `bankAccountNumber`, `nairaAmountRange`, `conditionalOtherText`, `fileUploadRequired` | 2 |
| F3 | Dead `ProcessProvider` | `lib/app/services.dart:383`, no callers | 2 |
| F4 | Dead `Env.paystackPublicKey` | `lib/app/services.dart`, no reads | 2 |
| F5 | Legacy colour aliases unused | 33 top-level `k*` constants in `lib/app/colors.dart` (`kPrimaryColor`, `kBlueColor`, `kCardLight`, `kBoxRadius`, …) and `BocColors.{blueDeep, darkCard, darkInk, darkLine, darkPaper, darkSoft, ink, line, purple}` have no references | 2 |
| F6 | Limit-update PIN check misses one contradiction | `transaction_limit_update_provider.dart` `_verify` lacks the transfer rule "PIN reply leaves OTP pending although initiation did not require one", so the limit change proceeds to finalize when it should stop. It also skips the `initiation.supported` (liveness) guard the transfer path applies | 3 |
| F7 | Biometric outcome mapping duplicated | `_resultFor` in `biometric_transfer_provider.dart:550` and `biometric_login_provider.dart:~493`; `BiometricOperationResult` lives in the login provider but is used by both. (The providers as a whole differ about 40%; do **not** merge them) | 4 |
| F8 | Transaction summary block duplicated | `biometric_approval_sheet.dart:102` ≈ `transaction_pin_sheet.dart:112` | 5 |
| F9 | Password/PIN recovery duplicated | `PasswordRecoveryFlowData` ≡ `PinRecoveryFlowData` field-for-field (`auth_flow_models.dart:~170–260`); `PasswordRecoveryNotifier.start` ≈ `PinRecoveryNotifier.start` (`recovery_providers.dart:35` vs `:194`), differing only in the enrollment wipe and the forgot endpoint | 6 |
| F10 | Dio construction duplicated | `dioProvider` (`network.dart:13`) and `coreDioProvider` (`core_network.dart:18`) repeat BaseOptions and interceptor wiring | 7 |
| F11 | KYC status block duplicated | `kyc_screens.dart:672` (identity) ≈ `:1100` (government ID): refresh action, failure card, success card | 8 |
| F12 | Hand-rolled stale-request guards | `int _generation` reimplemented in `core_transfer_attempt_provider.dart`, `transaction_limit_update_provider.dart`, `core_paged_rows.dart`, `savings_access_gate.dart`, plus `_operationId` in `recovery_providers.dart`, although `StaleResultGuard` (`services.dart`) exists and 9 providers use it | 9 (optional) |
| F13 | Unused font weights bundled | No `w200`/`w300` anywhere; the only `w900` is the Plus Jakarta "TEST MODE" label (`forms.dart:335`), which renders as 800 because no 900 file is bundled. Unused: `PlusJakartaSans-ExtraLight/Light.ttf` (~190 KB) and `FHOscarTest-Light/Black.otf` (~124 KB) | 1 |
| F14 | Trial-licence fonts | `FHOscarTest-*.otf` look like FH Oscar *trial* builds. Confirm a commercial licence and swap in the licensed files before release | Decision |
| F15 | Large onboarding GIFs | `assets/img/onboarding/{save,goals,pay}.gif` add ~7.8 MB (600×600) to every install | Decision |
| F16 | Uncommitted asset deletions | `cheetah_monochrome.svg`, `assets/img/img.png`, `.gitkeep`s, `design/onboarding_previews/*`, and the `assets/png/` pubspec entry are deleted in the working tree; nothing references them | 1 |
| F17 | `app_ui.dart` mega-library | About 20 component files are `part`s of `lib/module/app_flow/app_ui.dart`, and screens are `extension … on FlowPageState` parts. This couples every widget to one library and one state class, and private names leak across it | Deferred |
| F18 | `services.dart` grab-bag | `Env`, `AppBootstrap`, `ServiceResponse`, `NotifierState`, `StaleResultGuard` in one file imported by 106 files | Deferred |
| F19 | Very long build methods | `_savingsPlanDetailScreen` (~247 lines), `showContactVerificationSheet` (~300), `HomeScreenParts._homeScreen` (~235), `_accountScreen` (~205), `cards.dart:95` build (~260) | Deferred |

---

### Task 1: Assets and fonts

**Files:**
- Modify: `pubspec.yaml`, `lib/module/component/forms.dart`
- Delete: `assets/font/PlusJakartaSans-ExtraLight.ttf`, `assets/font/PlusJakartaSans-Light.ttf`, `assets/font/FHOscarTest-Light.otf`, `assets/font/FHOscarTest-Black.otf`

- [ ] Commit the existing working-tree asset deletions (F16) as their own commit. Run `rg -n "cheetah_monochrome|onboarding_previews|img\.png|assets/png" --glob '!build/**'` first and confirm it returns nothing.
- [ ] Change `FontWeight.w900` to `w800` at `forms.dart:335`. Nothing visible changes, because it already renders at 800.
- [ ] Remove the four unused font files and their pubspec entries. First run `rg -n "w200|w300|w900|FontWeight\.(light|extraLight|black)" lib` and confirm it returns nothing.
- [ ] Run `flutter analyze --no-pub` and the existing `test/branding_assets_test.dart` / `test/in_app_branding_test.dart`. If those tests list font files, update them.

### Task 2: Remove app-dead code

**Files:**
- Delete: `lib/utils/form_helpers.dart`
- Modify: `lib/utils/validators.dart`, `lib/utils/utils.dart`, `lib/app/services.dart`, `lib/app/colors.dart`, `test/widget_test.dart`, `test/auth_input_phone_test.dart`

- [ ] Delete `form_helpers.dart` and its import/test in `widget_test.dart` (F1).
- [ ] Delete the F2 validators/utils and the assertions that only exercise them. If `nigerianPhone` is the only phone validator `auth_input_phone_test.dart` covers, delete that assertion. Leave validators that `lib` uses.
- [ ] Delete `ProcessProvider` (F3) and `Env.paystackPublicKey` (F4). Also remove `PAYSTACK_PUBLIC_KEY` from `.env.*` examples if it is listed there.
- [ ] Delete the F5 colour aliases and unused `BocColors` members. Keep every constant that `BocSemanticColors` or the theme still reads.
- [ ] Verify with `rg -n "validateAndSave|form_helpers|ProcessProvider|paystackPublicKey" lib test` (expect no hits) and `flutter analyze --no-pub`.

### Task 3: Share PIN/OTP response consistency checks (F6)

**Files:**
- Modify: `lib/module/core_banking/model/core_check_progress.dart`
- Modify: `lib/module/core_banking/provider/core_transfer_attempt_provider.dart`
- Modify: `lib/module/account/provider/transaction_limit_update_provider.dart`
- Modify: `test/transaction_limit_update_provider_test.dart`

**Interfaces:**
- Add `bool coreCheckProgressContradicts({required CoreTransferCheck step, required CoreTransferInitiation initiation, required CoreCheckProgress? progress})` to `core_check_progress.dart`. It carries the five transfer rules exactly as written in `core_transfer_attempt_provider.dart` `_verify`. A null `progress` keeps the current empty-pending-set behavior, and the "OTP no longer pending" rule applies only when `progress != null`.
- Both `_verify` paths call it. Each provider keeps its own phases, rejection, and copy.

- [ ] Add **one** test to the limit-update provider tests: the initiation requires only PIN, and a successful PIN reply leaves OTP pending. Assert that the change stops and `finalizeLimitUpdate` is never called. (This guards a security boundary.)
- [ ] Extract the helper and use it in both providers.
- [ ] Add the `!initiation.supported` guard to the limit `_verify`, failing with the provider's existing "couldn't confirm this change's security checks" copy.
- [ ] Run `test/core_transfer_attempt_provider_test.dart` and `test/transaction_limit_update_provider_test.dart`.

### Task 4: Consolidate biometric outcome mapping (F7)

**Files:**
- Create: `lib/helper/biometric_operation_result.dart`
- Modify: `lib/module/onboarding/provider/biometric_login_provider.dart`
- Modify: `lib/module/core_banking/provider/biometric_transfer_provider.dart`

**Interfaces:**
- Move `BiometricOperationResult` into the helper and add `BiometricOperationResult biometricOperationResultFor(BiometricAuthOutcome outcome, {required String fallbackCredential})`.
- `fallbackCredential` is `'password'` for login and `'PIN'` for transfers, so each flow keeps its exact copy. Diff the two existing switches first; any wording that differs beyond the credential noun becomes a parameter, never a silent change.
- Re-export `BiometricOperationResult` from `biometric_login_provider.dart` so existing imports keep working.

- [ ] Replace both `_resultFor` switches with the shared mapper.
- [ ] Tests: none new. Run the existing biometric provider tests (`biometric_transfer_provider_test.dart`, `remembered_biometric_profile_test.dart`, `cold_launch_auth_test.dart`) unchanged.

### Task 5: Share transaction-summary rendering (F8)

**Files:**
- Create: `lib/module/core_banking/screens/transaction_summary_details.dart`
- Modify: `lib/module/core_banking/screens/transaction_pin_sheet.dart`, `lib/module/core_banking/screens/biometric_approval_sheet.dart`

- [ ] Create a widget that renders `TransactionSummary.amountDisplay` and its label/value rows. Titles, subtitles, actions, PIN input and errors stay in each sheet.
- [ ] Replace both duplicated blocks.
- [ ] Tests: none new. Run `transaction_pin_sheet_test.dart` and `core_transfer_pin_ui_test.dart` unchanged.

### Task 6: Merge password/PIN recovery duplication (F9)

**Files:**
- Modify: `lib/module/onboarding/model/auth_flow_models.dart`, `lib/module/onboarding/provider/recovery_providers.dart`, and the screens that name either data type

- [ ] Replace `PasswordRecoveryFlowData`/`PinRecoveryFlowData` with a single `RecoveryFlowData`. Use typedefs for the old names if they reduce churn, and drop them if callers update cleanly.
- [ ] Move the shared `start` body (identifier normalisation, validation, channel check, loading state, operation-id guard, response handling, test-OTP hint) into one private helper. Pass in the per-flow parts: the enrollment-retirement callback (`forgetEnrollment(onlyForIdentifier:)` vs `biometricApprovalProvider.wipe()`), the forgot call (`forgotPassword` vs `forgotPin`), and the `TestOtpFlow` value. Keep both notifiers and providers public as they are now.
- [ ] Do the same for any further identical verify/reset blocks you find in the file. Leave blocks that differ by more than parameters.
- [ ] Tests: none new. Run the existing auth/recovery tests (`biometric_login_storage_test.dart`, `logout_private_state_test.dart`, `back_stack_test.dart`).

### Task 7: Share Dio construction (F10)

**Files:**
- Modify: `lib/app/network.dart`, `lib/app/core_network.dart`

- [ ] Add `Dio buildApiDio(String baseUrl, AuthInterceptor auth)` (in `network.dart`). It sets the shared BaseOptions and timeouts, then adds `[auth, LoggingInterceptor(includeSensitiveData: Env.isStaging), ActivityInterceptor()]`. Each provider builds its own `AuthInterceptor`, so Core keeps `isPublicOperation: (_, _) => false` and `expireSessionOnRemote401: false`.
- [ ] Tests: none new. Run `core_network_test.dart` and `logging_redaction_test.dart`.

### Task 8: Share the KYC verification status block (F11)

**Files:**
- Modify: `lib/module/kyc/screens/kyc_screens.dart` (and `lib/module/component/kyc_widgets.dart` if the block belongs there)

- [ ] Extract the refresh action, failure card and success card that `kyc_screens.dart:672` and `:1100` repeat into one private method. It takes the success title and message (`Identity verified` / `Document verified`) and stays inside the existing `KycScreens` extension.
- [ ] Tests: none new. Run `kyc_identity_flow_test.dart` and `kyc_government_id_flow_test.dart`.

### Task 9 (optional): Adopt `StaleResultGuard` (F12)

Only where the substitution is mechanical. `core_transfer_attempt_provider` and `transaction_limit_update_provider` move money or limits and also invalidate on session events, so leave them unless the reviewer agrees the semantics match exactly.

- [ ] Replace `_operationId` in `recovery_providers.dart` and `_generation` in `core_paged_rows.dart` with `StaleResultGuard` if each one's bump points map to `beginRequest`/`trackDisposal`.
- [ ] Tests: none new. Run the touched providers' existing tests.

### Final verification

- [ ] `dart format --output=none --set-exit-if-changed lib test`
- [ ] `flutter analyze --no-pub`
- [ ] `flutter test --no-pub` (full suite)
- [ ] `git diff --check`, and review the whole-branch diff to confirm only the cleanup scope changed
- [ ] Device check by Kenechukwu on the Pixel 7 Pro (`flutter run -d 2B161FDH30033N --dart-define-from-file=.env.stage`): login with biometrics, a transfer with PIN, a transfer with biometric approval, a limit change, password and PIN recovery, the KYC status screens, and the staging TEST MODE banner

---

## Decisions for Kenechukwu (not scheduled)

- **F14 Fonts licence:** Confirm FH Oscar is licensed for production and replace the `FHOscarTest-*` trial files with the licensed ones before release. Renaming the asset paths only touches `pubspec.yaml`.
- **F15 Onboarding animation size:** Converting the three GIFs to animated WebP (Flutter decodes it natively, typically 60–80% smaller) or a short Lottie would cut most of the ~7.8 MB. This changes how the art looks and needs a visual sign-off.

## Deferred structural work (separate plans if wanted)

- **F17 Break up `app_ui.dart`:** Convert `component/*.dart` parts into standalone libraries with explicit imports, and screen extensions on `FlowPageState` into widgets that take what they need. This is high churn (most screens), so do it one module at a time in its own plan.
- **F18 Split `services.dart`:** `env.dart` (`Env`, `stagingModeProvider`, URL helpers), `notifier_state.dart` (`ServiceResponse`, `NotifierState`, `ApiMeta`), `stale_result_guard.dart`. Keep `services.dart` as a re-export barrel so the 106 importers don't change.
- **F19 Long build methods:** Split the listed methods into private widgets when those screens are next touched for features. This doesn't need its own pass.
