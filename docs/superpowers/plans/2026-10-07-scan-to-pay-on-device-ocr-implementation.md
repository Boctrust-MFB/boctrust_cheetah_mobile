# Scan to Pay On-Device OCR Implementation Plan

> **For agentic workers:** Implement the checked tasks in order. Use the repository's test-first workflow and verify each task before moving on.

**Goal:** Read a 10-digit account number and bank name from a camera or gallery image entirely on-device, match the bank to a supported code, and perform account name enquiry before continuing to a transfer.

**Architecture:** Flutter owns the scan state and all parsing/matching. A narrow platform channel returns recognized text lines and boxes from bundled Android ML Kit and iOS Vision. Images are captured at the highest available resolution, read locally, and deleted when the scan ends. Only the selected account number and bank code leave the device through the existing Core bank-list and name-enquiry APIs; no image or OCR text is uploaded.

**Tech Stack:** Flutter/Dart, Riverpod, `camera`, `image_picker`, Android ML Kit Latin text recognition (bundled), iOS Vision, Flutter method channels, `flutter_test`.

**Spec:** [On-device OCR design](2026-10-07-scan-to-pay-bank-aware-ocr.md).

## Global constraints

- Camera and gallery images, OCR lines, and extracted bank text remain on-device. Do not send them through Dio, logs, analytics, or crash reports.
- Images are never uploaded, so capture and read them at full resolution: no crop, grayscale, re-encode, or downscale in Dart. Delete every image file this feature receives (camera capture or gallery copy) on retake, new image, exit, page disposal, and after Continue; the account-field button deletes its file as soon as recognition ends. Delete only app-owned cache copies, never a gallery original.
- Preserve leading zeroes. Send account enquiry only for a `^\d{10}$` number and a bank code selected from the current supported list, except the existing BOCTRUST internal route.
- Do not choose among multiple distinct ten-digit numbers or multiple plausible bank codes without user input.
- Show the extracted number and bank for explicit customer confirmation before the first account enquiry, even when both matches are unique. A successful enquiry for the confirmed `(bankCode, accountNumber)` pair is required before Continue. The downstream transfer screen keeps its own enquiry, review, and PIN checks.
- Android and iOS are the supported scanning platforms. Keep gallery available when camera permission is denied.
- Tests are targeted: each one proves a behavior that can go wrong (number boundaries, bank ambiguity, coordinate decoding, file deletion, lookup gating, stale replies). No test for unchanged behavior or for code that no longer exists. Fakes are limited to Riverpod provider overrides, callback parameters, and Flutter's standard mock method-channel handler.

## File map

| File | Responsibility |
| --- | --- |
| `lib/module/core_banking/model/scan_text_models.dart` | Recognized lines, boxes, extracted candidates, bank-match result types |
| `lib/module/core_banking/service/scan_candidate_extractor.dart` | Pure number and bank-text extraction from OCR lines |
| `lib/module/core_banking/service/scan_bank_matcher.dart` | Pure matching against current `CommercialBank` entries; the one audited alias table |
| `lib/module/core_banking/service/scan_text_recognizer.dart` | Dart interface, method-channel implementation, provider, typed failure |
| `lib/module/core_banking/service/scan_image_file.dart` | Owns the current scan image path and deletes it on replace/clear |
| `android/app/src/main/kotlin/com/boctrust/boctrust_savings_loan/MainActivity.kt` | Android channel registration and bundled ML Kit call |
| `android/app/build.gradle.kts` | Bundled Latin text-recognition dependency |
| `ios/Runner/ScanTextRecognizer.swift`, `ios/Runner/AppDelegate.swift`, `ios/Runner.xcodeproj/project.pbxproj` | iOS Vision implementation, implicit-engine channel registration, Runner target membership |
| `lib/module/core_banking/screens/snap_to_pay_page.dart` | Capture, preview, local OCR, review, lookup, and routing |
| `lib/module/core_banking/screens/snap_number_button.dart` | Existing account-field photo button uses local OCR |
| `lib/app/feature_capability.dart`, `lib/app/core_api_endpoints.dart` | Remove remote OCR requirement and endpoint |
| `pubspec.yaml` | Move `image` to `dev_dependencies` once only tests use it |
| `lib/module/send/screens/send_screens.dart`, `ios/Runner/Info.plist`, `README.md` | Stale QR copy, permission strings, and the integration-gap row |
| `test/scan_candidate_extractor_test.dart`, `test/scan_bank_matcher_test.dart`, `test/scan_text_recognizer_test.dart`, `test/scan_image_file_test.dart`, `test/snap_to_pay_test.dart`, `test/feature_capability_test.dart` | Targeted unit, channel, widget, and capability coverage |

## Review focus

- A ten-digit substring inside an 11+ digit run must not become an account number (Task 1 test).
- Two distinct account numbers must remain a choice even if one is closer to the bank name (Task 1 test).
- Bank names are found without relying on the word "bank" (OPay, Kuda, Moniepoint, GTBank) (Task 1 and 2 tests).
- Overlapping names resolve to the longest match (First City Monument Bank is not First Bank); two different banks on one receipt stay ambiguous (Task 2 test).
- Similar bank names with different codes must remain separate options; a misspelling is only a suggestion (Task 2 test).
- iOS registers the channel on the implicit engine, not a root view controller (Task 3 build and device check).
- Rotated images return the same upright reading order and boxes within tolerance on each platform (Task 3 device check).
- Every image file is deleted on retake, exit, and after Continue (Task 4 test and device check).
- A lone unrelated ten-digit string must not start account enquiry without customer confirmation (Task 5 test).
- An old lookup response must not verify edited account details (Task 5 test).
- Local OCR must work with network disabled, and network logs must show no image body (Task 6 device check).

---

### Task 1: Define OCR line data and extract account candidates

**Files:** Create `lib/module/core_banking/model/scan_text_models.dart`, `lib/module/core_banking/service/scan_candidate_extractor.dart`, `test/scan_candidate_extractor_test.dart`.

**Interfaces:** `RecognizedLine(text, box)` where `box` is a normalized top-left `(left, top, width, height)` rectangle in `[0,1]` after EXIF orientation has been applied; `(0,0)` is the upright image's top-left pixel and `(1,1)` its bottom-right. `ScanCandidates extractScanCandidates(List<RecognizedLine> lines)` returns:

- `accountNumbers`: distinct ten-digit `String`s in reading order (top, then left). Boxes are used only for this ordering; do not carry them into the result, since no caller reads them.
- `bankTextLines`: the text of **every** line with its digit runs removed, dropping lines that become empty. Do not filter on the word "bank"; many Nigerian banks and wallets (OPay, Kuda, Moniepoint, PalmPay, GTBank) never print it. The matcher decides what is a bank.

**Rules:**

- Within one OCR line, join adjacent digit groups separated only by spaces or hyphens. A joined run of exactly ten digits is a candidate; a run of 11 or more digits produces no candidate (no substrings).
- Letter confusion: inside a token that is otherwise digits, read `O`/`o` as `0` and `I`/`l`/`|` as `1`, only when the token has at most two such letters and the result is exactly ten digits. Other letters are never converted. The customer confirms the number in Task 5, so this raises recall without auto-sending a guess.
- Deduplicate exact values. Do not use OCR confidence or proximity to bank text as a hidden tie-breaker; position only orders the list.

- [ ] Write targeted tests:
  - `Acct: 0123 456-789` → `0123456789` (separators joined, leading zero kept).
  - `08012345678` (11 digits) and `2340123456789` (13 digits) → no candidate.
  - Two distinct numbers on separate lines → both returned in reading order; the same number on two lines → one.
  - `O123456789` → `0123456789`; `ABC1234567` → no candidate.
  - Lines `Moniepoint` and `0123456789 Access Bank` → `bankTextLines` contains `Moniepoint` and `Access Bank`.
- [ ] Run `flutter test --no-pub test/scan_candidate_extractor_test.dart`; expect failures because the interface is absent.
- [ ] Implement the extractor.
- [ ] Run the focused test; expect all cases to pass. Commit this self-contained model/extractor change.

### Task 2: Resolve bank-name text against supported banks

**Files:** Create `lib/module/core_banking/service/scan_bank_matcher.dart`, `test/scan_bank_matcher_test.dart`; read `lib/module/core_banking/model/interbank_models.dart` and `scanToPayBanks` in `snap_to_pay_page.dart`.

**Interfaces:** `BankMatch matchScanBanks(List<String> bankTextLines, List<CommercialBank> availableBanks)` returns `status` (`unique`, `ambiguous`, `none`) and ordered, code-distinct `List<CommercialBank> candidates`. `availableBanks` is the output of `scanToPayBanks(...)`, so BOCTRUST is present only when its transfers are available and fetched BOCTRUST rows are already dropped.

**Rules:**

- Normalize both sides: lowercase, punctuation to spaces, collapse whitespace, expand `mfb` to `microfinance bank`, drop trailing legal suffixes (`plc`, `ltd`, `limited`).
- **Exact match:** a bank's normalized name occurs as a whole-token sequence inside a normalized line (containment, not equality, because lines carry extra words such as `Access Bank Plc Lagos`). When several names match overlapping tokens in one line, keep only the longest span (`first city monument bank` beats `first bank`; `union bank of nigeria` beats `union bank`).
- **Alias match:** a whole-token alias from one reviewed `const` map in this file (e.g. `gtbank`/`gtco` → Guaranty Trust Bank, `fcmb`, `uba`, `boctrust`), mapped to a canonical name and resolved to a code only if that name is in `availableBanks`. Keep the map short and audit it against the live bank list.
- **Similarity suggestion:** a line whose tokens are within a small edit distance of a bank name (e.g. `Acess Bank`). Suggestions follow exact/alias hits in the candidate order and never make the status `unique`.
- **Status:** `unique` only when exact/alias hits across all lines resolve to exactly one code. Two or more codes from exact/alias hits (e.g. a receipt showing both sender and recipient banks) → `ambiguous`. Only suggestions → `ambiguous`. Nothing → `none`. Deduplicate by code, not display name.

- [ ] Write targeted tests:
  - `ACCESS BANK PLC.` → `unique` Access Bank (case, punctuation, suffix).
  - `GTBank` → `unique` via alias; `Abc MFB` ↔ `Abc Microfinance Bank` → `unique`.
  - `First City Monument Bank` with both First Bank and FCMB available → only FCMB.
  - Lines naming Access Bank and Zenith Bank → `ambiguous` with both.
  - `Acess Bank` → `ambiguous` suggestion, not `unique`.
  - Two rows with the same code → one candidate.
  - `BOCTRUST` with `boctrustBank` available → `unique` BOCTRUST.
  - A bank absent from the list, and no bank text → `none`.
- [ ] Run `flutter test --no-pub test/scan_bank_matcher_test.dart`; expect failure.
- [ ] Implement normalization, longest-span exact matching, the alias map, and suggestions.
- [ ] Run the focused test; expect pass. Commit the matcher.

### Task 3: Add the native on-device recognizer

**Files:** Create `lib/module/core_banking/service/scan_text_recognizer.dart`, `ios/Runner/ScanTextRecognizer.swift`, `test/scan_text_recognizer_test.dart`; modify `MainActivity.kt`, `android/app/build.gradle.kts`, `ios/Runner/AppDelegate.swift`, and `ios/Runner.xcodeproj/project.pbxproj`.

**Interfaces:** `abstract interface class ScanTextRecognizer { Future<List<RecognizedLine>> recognize(String imagePath); }`. `scanTextRecognizerProvider` supplies the channel-backed implementation. Channel `boctrust/scan_text`, method `recognizeImage`, argument `{path: String}`, result `List<{text,left,top,width,height}>` with normalized upright-image coordinates. Native errors become a typed `ScanRecognitionFailure` whose message never contains the image path.

- [ ] Write a Dart channel test using `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` (no fake platform class): two line maps decode to `RecognizedLine`s with the same box values; a line with a box outside `[0,1]` is dropped; a `PlatformException` becomes `ScanRecognitionFailure` without the path. Run `flutter test --no-pub test/scan_text_recognizer_test.dart`; expect failure.
- [ ] Add the channel-backed Dart adapter and provider. Reject unsupported platforms before calling the channel.
- [ ] **Android.** Add the bundled Latin artifact `com.google.mlkit:text-recognition` (bundled model, not the Play Services variant) to `android/app/build.gradle.kts`. Its floor is API 21; Flutter's default `minSdk` is higher, so confirm the resolved value in the build output and leave `minSdk = flutter.minSdkVersion`. Expect a few MB of APK growth per ABI; record it.
  - In `MainActivity` (a `FlutterFragmentActivity`), override `configureFlutterEngine` and register a `MethodChannel` on `flutterEngine.dartExecutor.binaryMessenger`.
  - Build the image with `InputImage.fromFilePath(context, Uri.fromFile(file))`; it decodes and applies EXIF rotation, so do not rotate again. Normalize each `Text.Line.boundingBox` against `inputImage.width`/`height`, which are the upright dimensions.
  - Decode and recognize on a background executor; reply on the main thread. Create the recognizer per request and `close()` it in `finally`.
  - Decode at full resolution. Only if a device check shows an out-of-memory failure, downsample inside the native decode to a 4000 px long edge.
- [ ] **iOS.** In `ScanTextRecognizer.swift`:
  - Read the file's orientation with `CGImageSourceCopyPropertiesAtIndex` (`kCGImagePropertyOrientation`, default `.up`) and pass it to `VNImageRequestHandler(url:orientation:options:)`. Vision then reports boxes relative to the upright image.
  - Use `VNRecognizeTextRequest` with `.accurate` and take `topCandidates(1)` per observation. Run off the main thread; reply on the main thread.
  - Convert each bottom-left `boundingBox` to the shared top-left contract with `top = 1 - (origin.y + height)`; keep `left`, `width`, `height`.
- [ ] **iOS registration.** The app uses a scene delegate and `FlutterImplicitEngineDelegate`; there is no `window.rootViewController` at launch. Register inside `didInitializeImplicitFlutterEngine(_:)` after `GeneratedPluginRegistrant.register(with:)`, using `engineBridge.pluginRegistry.registrar(forPlugin: "ScanTextRecognizer")` and its `messenger()`. Leave the notification delegate and background-isolate registrant untouched. Add `ScanTextRecognizer.swift` to `project.pbxproj` as a `PBXFileReference`, in the Runner group, and as a `PBXBuildFile` in Runner's Sources build phase (the project does not auto-include new Swift files).
- [ ] Run the Dart channel test and `flutter analyze`; expect pass. Build both native targets (`flutter build apk --debug`, `flutter build ios --debug --no-codesign`).
- [ ] Device check on each platform: photograph an asymmetric slip at 0°, 90°, 180°, and 270°. Expect the same upright line order and boxes within ±0.03 of the 0° result on that platform. Do not compare boxes across Android and iOS; their line segmentation differs. Repeat with airplane mode on. Commit the adapter and native implementations.

### Task 4: Capture at full resolution and route both photo entry points through local OCR

**Files:** Create `lib/module/core_banking/service/scan_image_file.dart`, `test/scan_image_file_test.dart`; modify `lib/module/core_banking/screens/snap_to_pay_page.dart`, `lib/module/core_banking/screens/snap_number_button.dart`, `test/snap_to_pay_test.dart`.

**Interfaces:** `ScanImageFile` holds the current image path: `replace(String path)` deletes the previous file, `clear()` deletes the current one, and both ignore a file that is already gone. Camera and gallery produce an `XFile` path; both call `ScanTextRecognizer.recognize(path)` and then `extractScanCandidates(lines)`. `SnapNumberButton` still emits only a selected valid `String` to its existing `onNumber` callback.

**Capture:**

- Camera: `ResolutionPreset.max`, `enableAudio: false`, with still capture via `takePicture()`. Remove `shrinkForSnap`/`compute` from this path.
- Gallery: `pickImage(source: ImageSource.gallery)` without `maxWidth` or `imageQuality`, so the original resolution is read and nothing is re-encoded.
- **Native capture gate:** after the Task 6 device checks, if the `camera` plugin's `max` still is too soft for small print at the framing distance (digits under roughly 20 px tall in the captured file, or repeated misreads that a native camera photo of the same slip does not have), add a `captureStill` method to the same channel. It uses CameraX `ImageCapture` at maximum resolution on Android and `AVCapturePhotoOutput` with the largest supported `maxPhotoDimensions` on iOS, and returns a local file path that follows the same deletion rules. Do not build this before the evidence exists.

- [ ] Replace the upload, size-limit, crop, and metadata tests in `test/snap_to_pay_test.dart` (they test code removed in Task 6) and the `_Core` adapter they need. Write targeted tests:
  - `scan_image_file_test.dart`: `replace` deletes the previous temp file, `clear` deletes the current one, and a missing file is ignored.
  - `SnapNumberButton`'s helper (e.g. `readAccountNumberFromFile(ref, path)` with `scanTextRecognizerProvider` overridden) deletes the file after both a successful read and a `ScanRecognitionFailure`.
  - The account-field chooser: with two numbers recognized, the sheet lists both and returns the tapped one.
  Keep the existing bank-list and result tests until Task 5 replaces them.
- [ ] Run the focused tests; expect failure against the current upload path.
- [ ] Snap to Pay page:
  - Replace the 35%-height crop and upload with a still-image preview of the full photo and **Retake** / **Choose another** actions.
  - Enlarge the viewfinder guide to most of the preview and change the copy to "Fit the bank name and account number inside the frame".
  - Add a **recognizing** overlay. On `ScanRecognitionFailure`, offer Retake, Choose a photo, and Enter number (manual entry opens the Task 5 review with an empty number field).
  - When no number is found, open the review with an empty editable number.
  - Guard repeat taps and disposal while recognition is active, and ignore a result that arrives after Retake or exit.
  - Route every new image through `ScanImageFile.replace` and call `clear()` on Retake, exit, `dispose`, and Continue.
- [ ] `SnapNumberButton`: use the same recognizer and extractor on the picked file (no `maxWidth`/`imageQuality`). With one number, emit it; with several, show the chooser sheet; with none, show the existing snackbar. Delete the file as soon as recognition ends. Keep its current camera permission and gallery behavior.
- [ ] Remove what this task replaces, in the same commit:
  - `snap_number_button.dart`: `readAccountNumber(BuildContext, WidgetRef, Uint8List)` (it called `coreOcrServiceProvider`), the `_accountNumber` regex (the extractor owns the ten-digit rule), the `compute(shrinkWholeForSnap, …)` call, and the `core_ocr_service.dart` import. Keep `package:flutter/foundation.dart` for `kIsWeb`.
  - `snap_to_pay_page.dart`: `_read(Uint8List)`, both `compute(shrinkForSnap…)`/`compute(shrinkWholeForSnap…)` calls, the `Uint8List`-based `_number` flow, the `// Captures are shrunk by shrinkForSnap…` comment, and the `core_ocr_service.dart` import. `readAccountNumber` is imported from `snap_number_button.dart` today; if the page no longer needs anything from that file, drop the import.
  - `test/snap_to_pay_test.dart`: the `_Core` adapter, the four upload/crop/metadata tests, and the imports only they used (`dart:convert`, `dart:typed_data`, `dio`, `app/network.dart`, `core_ocr_service.dart`, `package:image`).
  - At this point `CoreOcrService` has no caller in `lib/`; Task 6 deletes it.
- [ ] Run focused tests and `flutter analyze`; expect pass. Commit the local capture integration.

### Task 5: Implement bank choice, enquiry, and verified routing

**Files:** Modify `lib/module/core_banking/screens/snap_to_pay_page.dart`, `test/snap_to_pay_test.dart`; reuse `showBankPicker`/`BankSelectorTile`, `interbankBanksProvider`, `CoreTransferService.boctrustNameEnquiry`, `lookUpAccountName`, and `accountNameLookupOutcome`.

**Interfaces:** Keep `SnapToPayPage.onSend(String route, String number, String? bankCode)`. `ScannedAccountResult` receives the extracted numbers, the `BankMatch`, the available banks, and `Future<({String? name, String? error})> Function(CommercialBank bank, String number) onCheck`. The page implements `onCheck`: BOCTRUST → `accountNameLookupOutcome(await boctrustNameEnquiry(number))`; any other bank → `lookUpAccountName(ref, bankCode: bank.code, accountNumber: number)`. The result widget tracks the selected number, selected `CommercialBank`, a monotonically increasing lookup generation, and a verified name bound to the exact `(bank.code, number)` pair.

**States:** recognizing (page, Task 4), reviewing, looking-up, verified, and error.

- **Reviewing** shows:
  - an editable number field, prefilled when exactly one number was found, with chips to choose when several were found;
  - the bank, preselected only for `unique`, with chips for `ambiguous` candidates and `BankSelectorTile` for the full list;
  - **Check account**, enabled only for a `^\d{10}$` number and a selected bank.
- **Looking-up** disables editing actions except Scan again and shows progress.
- **Verified** shows the returned account name and enables Continue.
- **Error** shows the lookup message (404 → `kAccountNotFound`) with Retry, and leaves both fields editable.
- Every edit, rescan, and exit increments the generation and clears verification; a reply for an older generation is ignored.

- [ ] Write targeted widget tests against `ScannedAccountResult` with a `Completer`-backed `onCheck`:
  - A `unique` bank and single number are prefilled, `onCheck` is **not** called until Check account is tapped; after success the name shows and Continue calls `onSend` with the bank's route and code.
  - A lone ten-digit number with bank status `none` sends nothing until the customer picks a bank and taps Check account.
  - Two numbers: Check account stays disabled until one is chosen. An `ambiguous` match preselects nothing and shows both banks.
  - Editing the number while a lookup is pending, then completing the old `Completer` with a name, leaves Continue disabled.
  - A failed lookup shows its message, and Retry calls `onCheck` again.
- [ ] Write one page-level test with `coreTransferServiceProvider` overridden: checking a BOCTRUST pair calls `boctrustNameEnquiry`, and checking another bank calls `nameEnquiry` with that bank's code.
- [ ] Run `flutter test --no-pub test/snap_to_pay_test.dart`; expect failure.
- [ ] Replace the existing `'a scanned number routes only after the bank is selected'` test: Continue now also requires a successful check, and the first new test covers it. Keep `'the scan bank list offers BOCTRUST once…'`, `'a failed bank load can be retried'`, and `'no sendable bank explains why Continue is off'`, adjusting only the `ScannedAccountResult` constructor arguments.
- [ ] Implement the states and `onCheck` wiring. Rewrite the `ScannedAccountResult` doc comment, which still says a bank must be picked manually and "OCR never infers the receiving bank", to describe the proposed bank and the required check. Map BOCTRUST to `AppRoutes.sendBeneficiary` (bank code `null`) and other banks to `AppRoutes.sendOtherBank`. Keep the destination transfer form's own enquiry intact. A failed bank-list load still shows the existing Retry card, and BOCTRUST stays selectable.
- [ ] Run focused widget tests; expect pass. Commit the verified-recipient flow.

### Task 6: Retire remote OCR and verify privacy and availability

**Files:** Delete `lib/module/core_banking/service/core_ocr_service.dart`; modify `lib/app/core_api_endpoints.dart`, `lib/app/feature_capability.dart`, `lib/module/send/screens/send_screens.dart`, `ios/Runner/Info.plist`, `README.md`, `pubspec.yaml`, `test/snap_to_pay_test.dart`, and `test/feature_capability_test.dart`.

**Interfaces:** `FeatureCapability.scanToPay` stays `stagingOnly` and lists one Core operation the flow needs, `POST CoreApiEndpoints.interbankNameEnquiry`, instead of `POST /me/snap-to-pay`. `availabilityFor` only checks that every operation's backend is configured, and all scan operations are Core. One operation therefore expresses "Core reachable", and no composition rule is needed. Per-destination availability is already enforced by `scanToPayBanks` through `boctrustTransfers` and `interbankTransfers`.

- [ ] Update `test/feature_capability_test.dart` with one targeted case: `scanToPay` has no `/me/snap-to-pay` operation, is unavailable without Core, and is unavailable outside staging. Do not add a network-recorder test; once `CoreOcrService` is deleted, no upload code remains to test, and the device log check below covers it.
- [ ] Run `flutter test --no-pub test/feature_capability_test.dart`; expect failure.
- [ ] Delete the remote OCR code:
  - Delete `core_ocr_service.dart`, which removes `CoreOcrService`, `coreOcrServiceProvider`, `kSnapImageMaxBytes`, `shrinkForSnap`, and `shrinkWholeForSnap`.
  - Delete `CoreApiEndpoints.snapToPay` (`core_api_endpoints.dart:70`).
  - Replace the `scanToPay` requirement and its comment ("Reads an account number from a photo; the number only fills a field.") in `feature_capability.dart`.
  - `package:image` is then used only by `test/branding_assets_test.dart` and `test/platform_branding_config_test.dart`, so move `image` from `dependencies` to `dev_dependencies`.
- [ ] Update stale copy found in the current codebase:
  - `send_screens.dart` `_scanUnavailable()`: replace "Paying with a merchant QR code or payment code is not available yet." with account-scan wording, e.g. "Reading an account from a photo is not available right now." Keep the banned QR line in `test/transaction_availability_test.dart`; it guards against fake QR copy and still applies.
  - `Info.plist`: change `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` from "read account numbers" to "read the account number and bank name", and say the photo stays on the device.
  - `README.md:212`: rewrite the Scan to pay row. It currently describes a QR merchant flow with "no camera". It should say: on-device account and bank reading, staging-only, Core name enquiry required, no payment contract. Update the scan-to-pay mention at `README.md:225` to match.
- [ ] Final dead-code check. Each of these must return no matches in `lib/` or `test/` (plan docs excluded):
  ```bash
  grep -rnE "CoreOcrService|coreOcrServiceProvider|shrinkForSnap|shrinkWholeForSnap|kSnapImageMaxBytes|snapToPay\b|snap-to-pay|readNumber\(|merchant QR code or payment code" lib test
  ```
  Expect no output. `SnapToPayPage` and `snap_to_pay_page.dart` intentionally do not match the pattern. Then run `flutter analyze` and confirm there are no `unused_import`, `unused_element`, or `unused_field` warnings in the touched files. Also remove any helper, parameter, or model field added in Tasks 1–5 that ended up unused, such as a `ScanCandidates` or `BankMatch` field no widget reads.
- [ ] Run `flutter test --no-pub test/scan_candidate_extractor_test.dart test/scan_bank_matcher_test.dart test/scan_text_recognizer_test.dart test/scan_image_file_test.dart test/snap_to_pay_test.dart test/feature_capability_test.dart`, then `flutter analyze`, then `flutter test --no-pub`. Expect all to pass.
- [ ] Device checks on Android and iOS:
  - **Images and conditions:** camera and gallery images (printed slips and screenshots) with the bank name above or below the number, rotation, low light, no bank, similar banks, a receipt with two banks, two numbers, camera denial, and offline recognition.
  - **Legibility:** record whether `ResolutionPreset.max` reads small print reliably, and apply the Task 4 native capture gate if it does not.
  - **Lookup:** re-enable the network for lookup. Confirm a successful name appears and that a wrong or changed pair cannot Continue.
  - **File deletion:** confirm the app's cache directory holds no scan image after Retake, exit, and Continue.
  - **Network logs:** bank list and account enquiry may appear, but no image payload or OCR text leaves the app.
  - Record the device results and commit the cleanup.

## Handoff

The plan ends with a working, locally recognized scan from full-resolution images that are deleted after use, and a Core-verified recipient. The current transfer screens remain responsible for their own recipient confirmation, amount review, authorization, and submission. Native still capture is added only if the Task 6 device checks show the `camera` plugin's maximum resolution is not legible enough. The design and this plan live under Git-ignored `docs/`; when committing planning artifacts for handoff, explicitly add both with `git add -f` so another checkout receives them.
