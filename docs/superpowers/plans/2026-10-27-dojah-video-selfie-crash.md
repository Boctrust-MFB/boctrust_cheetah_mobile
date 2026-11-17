# Dojah Video-Selfie Crash Fix Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Android BVN liveness from crashing the app when the native Dojah SDK runs its video-selfie path.

**Architecture:** Two alternative fixes. Pick **one**: Option A or Option B. Both start with Task 0, and both end with Task Z. Option A keeps Android on the native SDK and removes video from the Dojah widget. Option B routes Android identity capture to the hosted WebView flow that iOS already uses.

**Tech Stack:** Flutter/Riverpod, `dojah_kyc_sdk_flutter` (local patched copy, Android only), `com.github.dojah-inc:sdk-kotlin:v0.4.2`, Dojah hosted flow (`identity.dojah.io`) in `DojahWebView`.

**Spec:** No separate spec. This plan argues from the crash investigation recorded below.

## Investigation (2026-10-27)

Crash on the Pixel 7 Pro (`2B161FDH30033N`) during BVN liveness:

```
IllegalArgumentException: Uri lacks 'file' scheme:
  at androidx.core.net.UriKt.toFile(Uri.kt:43)
  at com.dojah.kyc_sdk_kotlin.ui.main.fragment.datacollection.PreviewSelfieFragment.onViewCreated(PreviewSelfieFragment.kt:140)
```

A second crash followed about 1s later: `lateinit property dojahContainer has not been initialized` in `SplashActivity`. It is a side effect, not a separate bug. Android restarted the process and restored Dojah's activity without `DojahSdk` having been set up.

From the `sdk-kotlin` v0.4.2 bytecode:

- The SDK has two selfie types: `VerificationType.Selfie` (photo, key `selfie`) and `VerificationType.SelfieVideo` ("Video KYC", key `selfie-video`/`video`).
- The BVN page (`GovDataFragment`) has a **"Verify with" dropdown** (`spinnerVerifyWith`). It is filled from the widget page's `config.verificationMethods`. With one method it is prefilled; with more than one, the user picks. `EmptyFragment` also picks a type from `config.mode`.
- **Photo path is safe:** `FaceDetectionUtil.getSingleFrameImage` writes a cache file and returns `Uri.fromFile(...)`.
- **Video path always fails on Android 10+:**
  1. `CameraUtil.recordVideo` records to `MediaStore.Video.Media.INTERNAL_CONTENT_URI`. Third-party apps cannot insert there, so the recording fails.
  2. On `VideoRecordEvent.Finalize` it passes `getOutputResults().getOutputUri()` to the callback without checking `hasError()`. CameraX returns `Uri.EMPTY` for a failed recording.
  3. `PreviewSelfieFragment` calls `selfieUri.toFile()` → throws. Even a successful recording would produce a `content://` URI, and `toFile()` throws on that too.

**Why it started now:**

- None of our Dojah code changed since `bcf0acf` (2026-10-02, "run BVN liveness in the native Dojah SDK on Android"), apart from the icon swap in `6acebdb`.
- The SDK pin has been `v0.4.2` since `df72d2e` (2026-09-14).
- No device run of native liveness is recorded after `bcf0acf`.
- The staging selfie widget's `widget/pre-auth` response (`government-data`, `bvn`, `bvnAdvance`, `selfie: true`, `version: 1`) carries neither `verificationMethods` nor `mode`. The video choice therefore comes from the fuller widget config, the user's pick in "Verify with", or both. A Dojah dashboard change is likely, just as the Email step appeared on 2026-09-19 without an app change.

The SDK bug was always there. It became reachable when the flow went down the video branch.

## Execution: both options (decided 2026-10-27)

Kenechukwu chose to do both. Code tasks run in this order: **B1**, then **D1**. D1 replaces A2 Step 2 and B2 Step 3. A2 Step 1 is folded into B1 Step 3: the route doc comment records the video crash, and also says that the widget must offer only the photo selfie for as long as installed builds still run the native SDK. Kenechukwu does Task 0, A1, B2 Steps 1–2 (device and dashboard work) and sends the Task Z report.

### Task D1: Record the crash and both fixes

**Files:**
- Modify: `docs/verification/dojah-kyc.md` (append one section)

- [ ] **Step 1:** Append `## Native video selfie crash — 2026-10-27`. Include:
  - Both stack traces from the Investigation section.
  - The three-step cause.
  - Why it surfaced now: no app or SDK change since `bcf0acf`/`df72d2e`; the video branch was reached through the widget's "Verify with" methods.
  - Both fixes: Android identity moved to the hosted flow (B1, with the native path kept for a one-line return), and the dashboard change restricting the selfie widget to the photo selfie, which also protects installed builds.
  - A `### Pending device checks` list naming Task 0, A1 Steps 2–3 and B2 Steps 1–2 as not yet run.
- [ ] **Step 2:** Commit only that file.

```bash
git add docs/verification/dojah-kyc.md
git commit -m "docs(kyc): record the native video-selfie crash and its fixes"
```

## Global Constraints

- Do not modify the `sdk-kotlin` AAR or fork it. The patched Flutter plugin stays as described in `packages/dojah_kyc_sdk_flutter/BOCTRUST_PATCH.md`.
- `.env.stage` and `.env.prod` both use the same `DOJAH_SELFIE_WIDGET_ID` (`6aa553…`), so a dashboard change affects staging and production together.
- Device run command: `flutter run -d 2B161FDH30033N --dart-define-from-file=.env.stage`.
- Tests: barest minimum. Only update tests that already pin the behaviour being changed.
- The backend remains authoritative for verification results; a capture outcome is never a verdict.

## Review Focus

1. **A user on an older build after the fix (Option A only):** The dashboard fix protects every installed build. Option B protects only builds that include it. If you choose B, apply A as well until old builds age out.
2. **Video re-enabled later in the dashboard (Option A):** It brings the crash back with no app change. Task A2 records the rule so nobody re-enables video.
3. **BVN liveness in the Android WebView (Option B):** The reason Android moved back to native on Oct 2 was not written down beyond "does not depend on the embedded browser's face model". Task B2's device run must complete a liveness capture, not just open the page.
4. **Process death mid-capture (both):** The `SplashActivity`/`dojahContainer` crash happens whenever Android restores the SDK's activity in a fresh process. This plan does not fix it. Note it in the Dojah bug report (Task Z).
5. **Government-ID flow:** It stays on the WebView in both options. Confirm in Task B1's test that `KycOperation.governmentId` still maps to `DojahCaptureMode.webView`.

---

### Task 0: Confirm which branch the crashing session took

**Files:** none

- [ ] **Step 1:** On the Pixel 7 Pro, start BVN verification. On the SDK's BVN page, note whether a "Verify with" dropdown appears and which options it lists.
- [ ] **Step 2:** If it is there, choose the photo **Selfie** option and complete capture. Expected: preview shows and no crash. Then repeat with **Video KYC**. Expected: crash in `PreviewSelfieFragment` (confirm with `adb logcat -d -b crash | tail -40`).
- [ ] **Step 3:** In the Dojah dashboard, open the selfie widget (`DOJAH_SELFIE_WIDGET_ID`) and record what its BVN/selfie step offers as verification methods and liveness mode. Note any change history the dashboard shows.

Expected outcome: photo works and video crashes. If photo also crashes, stop and return to investigation; neither option below covers that case.

---

## Option A: Remove video from the Dojah widget (keep native SDK)

### Task A1: Restrict the selfie widget to photo selfie

**Files:** none (Dojah dashboard)

- [ ] **Step 1:** In the Dojah dashboard, set the selfie widget's BVN/selfie step to offer only the photo selfie (remove "Video KYC"/video liveness from its verification methods and mode).
- [ ] **Step 2:** Run the device command. Start BVN verification. Expected: the "Verify with" dropdown is absent or prefilled with Selfie and has no video option.
- [ ] **Step 3:** Complete a capture with sandbox data. Expected: selfie preview, submission, the SDK closes, and our capture screen reports its outcome. `adb logcat -d -b crash` shows no new entry.

### Task A2: Record the constraint

**Files:**
- Modify: `lib/module/kyc/service/dojah_platform_route.dart` (doc comment on `DojahPlatformRoute`)
- Modify: `docs/verification/dojah-kyc.md` (new section)

- [ ] **Step 1:** Add to the `DojahPlatformRoute` doc comment, after the `No stepNumber` paragraph: the native SDK's video selfie crashes the host process (it records to `MediaStore.Video.Media.INTERNAL_CONTENT_URI`, ignores the failed `Finalize`, then calls `toFile()` on an empty URI in `PreviewSelfieFragment`). The selfie widget must therefore offer only the photo selfie.
- [ ] **Step 2:** Append `## Native video selfie crash — 2026-10-27` to `docs/verification/dojah-kyc.md`. Include the stack trace, the three-step cause from the Investigation section, the dashboard change made in Task A1 with what the widget offered before, and the device result from A1 Step 3.
- [ ] **Step 3:** Verify: `flutter analyze` → no issues.
- [ ] **Step 4:** Commit.

```bash
git add lib/module/kyc/service/dojah_platform_route.dart docs/verification/dojah-kyc.md
git commit -m "docs(kyc): keep the Dojah selfie widget off the native video path"
```

---

## Option B: Route Android BVN liveness to the WebView

### Task B1: Android identity uses the hosted flow

**Files:**
- Modify: `lib/module/kyc/service/dojah_platform_route.dart` (`chooseDojahPlatformRoute`, `DojahPlatformRoute` doc comment)
- Test: `test/dojah_platform_route_test.dart`

**Interfaces:**
- Unchanged: `chooseDojahPlatformRoute({required bool isWeb, required bool isAndroid, required bool isIOS}) -> DojahPlatformRoute`, `dojahCaptureMode(DojahPlatformRoute, KycOperation) -> DojahCaptureMode`.

Decision: change only the route choice. Keep `DojahPlatformRoute.androidNativeIdentity`, `DojahCaptureMode.nativeSdk` and `_launchNative` in `dojah_capture_screen.dart` in place, so the change can be flipped back with one line once Dojah fixes `recordVideo`. The doc comment must say this path is parked and why.

- [ ] **Step 1: Update the Android test**

Rename it to `'Android uses the embedded browser for every operation'` and replace the comment with one naming the video-selfie crash. Assertions:

```dart
final route = chooseDojahPlatformRoute(isWeb: false, isAndroid: true, isIOS: false);
expect(route, DojahPlatformRoute.webView);
expect(dojahCaptureMode(route, KycOperation.identity), DojahCaptureMode.webView);
expect(dojahCaptureMode(route, KycOperation.governmentId), DojahCaptureMode.webView);
```

- [ ] **Step 2:** Run `flutter test test/dojah_platform_route_test.dart`. Expected: the Android test FAILS (route is `androidNativeIdentity`).
- [ ] **Step 3:** In `chooseDojahPlatformRoute`, return `DojahPlatformRoute.webView` when `isAndroid`. Rewrite the `DojahPlatformRoute` doc comment: both platforms use the hosted flow. Android left the native SDK because of the document-page `No stepNumber` crash and the video-selfie `toFile()` crash (one sentence each, with the class names). `androidNativeIdentity` is kept, unused, for returning to the SDK once Dojah ships a fix.
- [ ] **Step 4:** Run `flutter test test/dojah_platform_route_test.dart` → PASS, then `flutter analyze` → no issues.
- [ ] **Step 5:** Commit.

```bash
git add lib/module/kyc/service/dojah_platform_route.dart test/dojah_platform_route_test.dart
git commit -m "fix(kyc): run Android BVN liveness in the hosted Dojah flow"
```

### Task B2: Device check and record

**Files:**
- Modify: `docs/verification/dojah-kyc.md` (new section)

- [ ] **Step 1:** Run the device command. Start BVN verification. Expected: our camera permission prompt, then `identity.dojah.io` in `DojahWebView` with the BVN and email prefilled.
- [ ] **Step 2:** Complete a liveness capture with sandbox data, including the face/liveness step. Expected: capture completes, the page posts `connect.account.success` or redirects, and the screen closes with an outcome. If the face step does not work in the WebView, stop and report; choose Option A instead.
- [ ] **Step 3:** Append `## Android back to the hosted flow — 2026-10-27` to `docs/verification/dojah-kyc.md`. Include the stack trace, the cause from the Investigation section, the route change, and the device result from Step 2.
- [ ] **Step 4:** Commit.

```bash
git add docs/verification/dojah-kyc.md
git commit -m "docs(kyc): record the native video-selfie crash and the move to the hosted flow"
```

---

### Task Z: Report to Dojah (either option)

**Files:** none

- [ ] **Step 1:** Draft a bug report for Dojah against `sdk-kotlin` v0.4.2 for Kenechukwu to send. Cover:
  - `CameraUtil.Companion.recordVideo` uses `MediaStore.Video.Media.INTERNAL_CONTENT_URI`.
  - The `Finalize` consumer ignores `hasError()`.
  - `PreviewSelfieFragment.onViewCreated` calls `toFile()` on a possibly empty or `content://` URI.
  - `SplashActivity` reads `DojahSdk.dojahContainer` before it is set after process death.
  - Include both stack traces and the device (Pixel 7 Pro, `targetSdk` 36). Kenechukwu sends it; do not send it from the session.
