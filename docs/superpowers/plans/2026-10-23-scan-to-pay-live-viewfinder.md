# Scan to Pay Live Viewfinder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scan to Pay reads the account number straight from the live camera viewfinder and opens the existing review once a number holds steady, so the customer no longer has to take a photo first.

**Architecture:** `SnapToPayPage` streams preview frames (`CameraController.startImageStream`) at a throttled rate to a new `recognizeFrame` method on the existing `boctrust/scan_text` channel. Vision (iOS) and ML Kit (Android) read the raw frame bytes and return lines in the same `RecognizedLine` contract as photos. A pure-Dart `ScanFrameStabilizer` accepts a number only after it repeats across frames; then the stream stops, the preview pauses, and the existing `ScannedAccountResult` review opens. The shutter and gallery buttons stay as fallbacks and use the existing photo path unchanged.

**Tech Stack:** Flutter, `camera` 0.12.1 (`camera_avfoundation` 0.10.3+1, `camera_android_camerax` 0.7.5+1), Apple Vision, ML Kit `text-recognition` 16.0.1, Riverpod.

**Spec:** The live-scanning proposal in the 2026-10-23 session (summarised under Goal and Architecture). It replaces one rule in `docs/superpowers/plans/2026-10-07-scan-to-pay-bank-aware-ocr.md`: "Do not stream preview frames to OCR." Every other rule in that design still holds.

## Global Constraints

- Frames and recognized text never leave the phone: no HTTP request, no logging of frame bytes, recognized text or account numbers.
- A live read never sends or checks anything by itself. It only opens `ScannedAccountResult`, where the customer still taps **Check account** and then **Continue**.
- Throttle: at most one frame in flight, and at least **300 ms** between the starts of two frame reads.
- Stability rule: a number is accepted when it appears in **3 of the last 5** read frames.
- Live controller resolution: `ResolutionPreset.veryHigh` (1080p). Frame format: `ImageFormatGroup.bgra8888` on iOS, `ImageFormatGroup.nv21` on Android.
- Rotation sent to native code is `CameraDescription.sensorOrientation` (the page is portrait-only).
- Native failure messages must never contain frame data or paths: use fixed messages only, as the existing `recognizeImage` does.
- Tests: the barest minimum. Only the stabilizer gets a test, because it is the guard against acting on a misread account number. No UI tests and no new fake infrastructure.
- Copy: the frame caption reads `Point at the account number and bank name`. While a candidate is forming it reads `Hold steady…`.

## Review Focus

1. **Flickering digits:** OCR reads `0123456789` in two frames and `0123456780` in two others. Neither should be accepted until one reaches 3 of 5. This is covered by the stabilizer test in Task 2.
2. **Shutter tapped while streaming:** `takePicture` during an active image stream fails on some Android devices. Stop the stream before capturing and restart it on Retake (Task 3).
3. **App backgrounded mid-stream:** the existing lifecycle code disposes the camera on `inactive`. The stream must not restart while a review sheet is open, and a reply that arrives late after Scan again must be dropped (`_scan` generation check, Task 3).
4. **Android rows wider than the image:** an NV21 plane whose `bytesPerRow` is larger than `width` must be repacked natively before ML Kit reads it, or the frame comes out skewed into garbage (Task 1).
5. **Native method missing:** an older build without `recognizeFrame` (`MissingPluginException`) must silently turn live scanning off for the session and leave the shutter working (Tasks 1 and 3).

---

### Task 1: `recognizeFrame` on the scan channel

**Files:**
- Modify: `lib/module/core_banking/model/scan_text_models.dart`: add `ScanFrameFormat` and `ScanFrame`
- Modify: `lib/module/core_banking/service/scan_text_recognizer.dart`: add `recognizeFrame` to the interface and the channel implementation
- Modify: `ios/Runner/ScanTextRecognizer.swift`: handle `recognizeFrame`
- Modify: `android/app/src/main/kotlin/com/boctrust/boctrust_savings_loan/MainActivity.kt`: handle `recognizeFrame`
- Modify: `test/snap_to_pay_test.dart:35`: add `recognizeFrame` to the `_Recognizer` fake (throw `UnimplementedError`)

**Interfaces:**
- Produces:
  - `enum ScanFrameFormat { nv21, bgra8888 }`
  - `class ScanFrame { const ScanFrame({required Uint8List bytes, required int width, required int height, required int bytesPerRow, required int rotation, required ScanFrameFormat format}); }`. Width and height are the raw sensor frame; rotation is 0/90/180/270.
  - `ScanTextRecognizer.recognizeFrame(ScanFrame frame) → Future<List<RecognizedLine>>`. Boxes use the existing `ScanTextBox` contract on the **upright** frame.
  - Channel call: `recognizeFrame` with map `{bytes, width, height, bytesPerRow, rotation, format: 'nv21' | 'bgra8888'}`.
  - Errors: `PlatformException` or `TypeError` → `ScanRecognitionFailure(ScanRecognitionFailure.unreadable)`; `MissingPluginException` or an unsupported platform → `ScanRecognitionFailure('Scanning is not available on this device.')`. These mirror `recognize`.

- [ ] **Step 1: Add `ScanFrameFormat` and `ScanFrame` to `scan_text_models.dart`.** Use plain final fields. Leave out `Equatable`, because frames are never compared.
- [ ] **Step 2: Add `recognizeFrame` to `ScanTextRecognizer` and `ChannelScanTextRecognizer`.** Reuse `_decodeLine` and the same exception mapping as `recognize`. Pull the platform check and the `try`/`on` mapping into one private helper that both methods call.
- [ ] **Step 3: Add the iOS handler in `ScanTextRecognizer.swift`.**
  - Switch on `call.method` for `"recognizeImage"` and `"recognizeFrame"`.
  - For a frame, build a `CVPixelBuffer` (`kCVPixelFormatType_32BGRA`, width × height) and copy the bytes row by row, honouring `bytesPerRow` on both sides.
  - Run `VNImageRequestHandler(cvPixelBuffer:orientation:)` with the rotation mapped as 0→`.up`, 90→`.right`, 180→`.down`, 270→`.left`.
  - Set `recognitionLevel = .accurate` and `usesLanguageCorrection = false`.
  - Run frames on a dedicated serial `DispatchQueue(label: "boctrust.scan_text.frames", qos: .userInitiated)`.
  - Reuse the existing box conversion: move it out of `recognizeLines(at:)` into a `lines(from: [VNRecognizedTextObservation])` helper.
  - Failures send `FlutterError(code: "recognition_failed", message: "Text recognition failed.", details: nil)`.
- [ ] **Step 4: Add the Android handler in `MainActivity.kt`.**
  - Branch on `call.method`.
  - For a frame, if `bytesPerRow > width`, repack into a tight NV21 buffer of `width * height * 3 / 2` bytes: copy `height` Y rows, then `height / 2` interleaved VU rows, each `width` bytes from a stride of `bytesPerRow`.
  - Call `InputImage.fromByteArray(buffer, width, height, rotation, InputImage.IMAGE_FORMAT_NV21)`.
  - ML Kit reports boxes on the rotated image, so normalise by the **rotated** size: swap width and height when rotation is 90 or 270.
  - Keep one `TextRecognition.getClient(...)` for frames as an activity field, created lazily and closed in `onDestroy`, so it isn't rebuilt three times a second.
  - Run frames on `scanExecutor`. Pull the line-mapping loop out into a helper shared with `recognizeLines`.
  - Errors return `result.error("recognition_failed", e.javaClass.simpleName, null)`.
- [ ] **Step 5: Update the `_Recognizer` fake in `test/snap_to_pay_test.dart`.** Add `recognizeFrame` throwing `UnimplementedError`.
- [ ] **Step 6: Verify.**
  - Run `flutter analyze`. Expected: `No issues found!`
  - Run `flutter test test/snap_to_pay_test.dart test/scan_text_recognizer_test.dart`. Expected: all pass.
  - Run `flutter build ios --debug --no-codesign` and `flutter build apk --debug`. Expected: both build.
- [ ] **Step 7: Commit.**

```bash
git add lib/module/core_banking/model/scan_text_models.dart lib/module/core_banking/service/scan_text_recognizer.dart ios/Runner/ScanTextRecognizer.swift android/app/src/main/kotlin/com/boctrust/boctrust_savings_loan/MainActivity.kt test/snap_to_pay_test.dart
git commit -m "Read Scan to Pay preview frames on the device"
```

### Task 2: `ScanFrameStabilizer`

**Files:**
- Create: `lib/module/core_banking/service/scan_frame_stabilizer.dart`
- Test: `test/scan_frame_stabilizer_test.dart`

**Interfaces:**
- Consumes: `ScanCandidates` from `scan_text_models.dart`.
- Produces:
  - `class ScanFrameStabilizer { ScanFrameStabilizer({this.window = 5, this.required = 3}); ScanCandidates? add(ScanCandidates frame); bool get forming; void reset(); }`
  - `add` records one read frame and returns `null` until at least one number is stable. It then returns `ScanCandidates` with:
    - `accountNumbers`: the stable numbers in the order they were first seen;
    - `bankTextLines`: the lines from every frame in the window, with duplicates dropped and order kept.
  - `forming` is true when any number appears in the window but none is stable yet. It drives the `Hold steady…` caption.

- [ ] **Step 1: Write the failing test.**

```dart
test('a number is accepted only after 3 of the last 5 frames agree', () {
  final s = ScanFrameStabilizer();
  ScanCandidates f(List<String> n) =>
      ScanCandidates(accountNumbers: n, bankTextLines: const ['GTBank']);
  expect(s.add(f(['0123456789'])), isNull);
  expect(s.add(f(['0123456780'])), isNull);
  expect(s.add(f(['0123456789'])), isNull);
  expect(s.add(f(['0123456780'])), isNull);
  expect(s.forming, isTrue);
  final accepted = s.add(f(['0123456789']));
  expect(accepted?.accountNumbers, ['0123456789']);
  expect(accepted?.bankTextLines, ['GTBank']);
});
```

- [ ] **Step 2: Run `flutter test test/scan_frame_stabilizer_test.dart`.** Expected: FAIL, because `ScanFrameStabilizer` is not defined.
- [ ] **Step 3: Implement `ScanFrameStabilizer`.** Keep a `Queue<ScanCandidates>` capped at `window`. Count each number at most once per frame.
- [ ] **Step 4: Run `flutter test test/scan_frame_stabilizer_test.dart`.** Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add lib/module/core_banking/service/scan_frame_stabilizer.dart test/scan_frame_stabilizer_test.dart
git commit -m "Accept a live-scanned number only once it holds steady"
```

### Task 3: Live scanning on `SnapToPayPage`

**Files:**
- Modify: `lib/module/core_banking/screens/snap_to_pay_page.dart`

**Interfaces:**
- Consumes: `ScanFrame`, `ScanFrameFormat` and `ScanTextRecognizer.recognizeFrame` (Task 1); `ScanFrameStabilizer` (Task 2); the existing `extractScanCandidates` and `ScannedAccountResult`.
- Produces: no new public API.

- [ ] **Step 1: Configure the controller in `_startCamera`.**
  - Use `ResolutionPreset.veryHigh` with `imageFormatGroup: _isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888`.
  - Replace the "every pixel" comment: live frames are read at 1080p, and gallery photos are still read at full size.
  - Once the controller is ready, call `_startLive()`, but only when no review is open (`_candidates == null && _problem == null && _image.path == null`).
- [ ] **Step 2: Add the live state and `_startLive()`.**
  - New state fields:
    - `ScanFrameStabilizer _stabilizer`;
    - `bool _liveOff`, set for the session after a `MissingPluginException`-style "not available" failure;
    - `bool _frameBusy`;
    - `DateTime _lastFrame`;
    - `bool _forming`.
  - `_startLive()` resets the stabilizer and calls `camera.startImageStream(_onFrame)` when `!_liveOff && !camera.value.isStreamingImages`.
- [ ] **Step 3: Implement `_onFrame(CameraImage image)`.**
  - Skip the frame when any of these is true: `_frameBusy`, less than 300 ms since `_lastFrame`, `_recognizing`, or a review is open.
  - Otherwise build a `ScanFrame` from `image.planes.first`: its `bytes` and `bytesPerRow`, the image's `width` and `height`, the camera's `description.sensorOrientation`, and the platform's format.
  - Capture `final scan = _scan` and await `recognizeFrame`.
  - Pass the result through `extractScanCandidates`, then `_stabilizer.add`.
  - Drop the result if `!mounted || scan != _scan`.
  - Swallow `ScanRecognitionFailure.unreadable` and keep going. On the "not available" failure, set `_liveOff` and stop the stream.
  - On an accepted result, call `_stopLive()`, then `camera.pausePreview()`, then `HapticFeedback.mediumImpact()`, then `setState(() => _candidates = accepted)`.
  - Otherwise update `_forming` only when its value changes, so the page doesn't rebuild on every frame.
- [ ] **Step 4: Add `_stopLive()`.** It calls `stopImageStream()` when `camera.value.isStreamingImages`, inside a `try` that ignores `CameraException`.
- [ ] **Step 5: Wire the existing actions.**
  - `_capture` awaits `_stopLive()` before `takePicture()`, and calls `_startLive()` again if the capture fails.
  - `_pickFromGallery` awaits `_stopLive()` once a photo is chosen.
  - `_retake` resumes the preview if it is paused and calls `_startLive()`.
  - `_enterNumber` calls `_stopLive()`.
  - `_exit` and `dispose` need no change, because disposing the controller ends the stream. The `inactive` branch of `didChangeAppLifecycleState` likewise needs nothing, and `resumed` already goes through `_startCamera`, which honours the review-open check from Step 1.
- [ ] **Step 6: Render a live result.**
  - In `build`, when `photo == null && _candidates != null`, keep the paused `_viewfinder()` behind it and show `_result(candidates)` at the bottom in the same scrollable `Align` that photo results use.
  - Leave out the Retake / Choose another row: `ScannedAccountResult` already has **Scan again**, which calls `_retake`.
  - Hide `_controls()` while a live result shows.
- [ ] **Step 7: Update the copy.** The viewfinder caption becomes `Point at the account number and bank name`, or `Hold steady…` while `_forming`. The shutter keeps its `Take photo` label.
- [ ] **Step 8: Verify.**
  - Run `dart format lib/module/core_banking/screens/snap_to_pay_page.dart && flutter analyze`. Expected: `No issues found!`
  - Run `flutter test test/snap_to_pay_test.dart test/scan_frame_stabilizer_test.dart`. Expected: all pass.
- [ ] **Step 9: Commit.**

```bash
git add lib/module/core_banking/screens/snap_to_pay_page.dart
git commit -m "Read the account number live from the Scan to Pay viewfinder"
```

### Task 4: Device check

Kenechukwu runs this on real devices; the simulator has no camera.

- [ ] **Step 1: iPhone 14 Pro Max over USB.** Run `flutter run -d 00008120-000C205A2604201E --dart-define-from-file=.env.stage`.
- [ ] **Step 2: Pixel 7 Pro.** Run `flutter run -d 2B161FDH30033N --dart-define-from-file=.env.stage`.
- [ ] **Step 3: On each device, go to Send → Scan to pay and check:**
  - a printed account slip opens the review within about 2 s, with the right number and the bank preselected;
  - a screen showing two different numbers offers both as chips;
  - Scan again resumes the live preview;
  - the shutter and gallery still work;
  - backgrounding and returning to the app restarts scanning;
  - the phone doesn't get noticeably warm after 60 s of scanning.
