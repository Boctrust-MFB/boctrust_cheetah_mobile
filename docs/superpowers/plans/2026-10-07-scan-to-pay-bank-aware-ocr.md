# Scan to pay on-device OCR design

**Goal:** Extract a 10-digit account number and bank name locally from a camera or gallery image, match the bank to an available bank code, then run account name enquiry.

**Architecture:** Keep the current Flutter viewfinder and gallery picker. On each selected still image, recognize text on the device, then parse and match it in Dart. Send only the chosen account number and bank code to Core for the existing account lookup. Images and OCR text never go to an OCR backend.

**Current state:** `SnapToPayPage` already handles the camera, gallery, and permission fallback. `CoreOcrService` currently uploads a cropped image to `POST /me/snap-to-pay` and returns one digit run. `ScannedAccountResult` requires manual bank selection. The app already fetches `GET /me/interbank/banks` and supports BOCTRUST and interbank name enquiry.

## Customer flow

1. Frame both the bank name and account number. Take one photo or choose an image from the gallery. Show a preview with retake/change-image controls.
2. Recognize text from that still image on the device. Do not stream preview frames to OCR. Correct orientation and express all text boxes in normalized upright-image coordinates with a top-left origin, so number and bank lines can be associated consistently on Android and iOS.
3. Extract all plausible ten-digit numbers, preserving leading zeroes. Allow spaces or hyphens between digits, but reject fragments embedded in longer digit strings. If multiple distinct numbers remain, ask the customer to choose or edit.
4. Extract bank-name candidates from OCR lines. Compare them with the fetched bank list and the BOCTRUST internal option. Preselect a single strong match; show multiple plausible matches for selection. If none matches, offer the searchable full bank list. The customer can correct either field.
5. Show the valid number and proposed or selected bank for explicit customer confirmation. Run account name enquiry only after the customer taps Check account, including when both OCR matches are unique. Show the verified account name. Changing either field invalidates verification and ignores late replies.
6. Continue to the corresponding transfer form only after successful enquiry. The form retains its existing review, enquiry, and PIN authorization rules; it may repeat enquiry because the current route arguments carry only number and bank code.

## Implementation tasks

### 1. Add a device-only text recognition adapter

- Add `ScanTextRecognizer` under `lib/module/core_banking/service/`, with `recognize(String imagePath) -> Future<List<RecognizedLine>>`. Each line has text and a normalized top-left bounding box in upright-image coordinates. Keep recognition separate from candidate parsing so parsing can be tested without native code.
- Implement recognition on Android with a **bundled Latin-script ML Kit model**, and on iOS with **Apple Vision text recognition**, through a narrow Flutter platform channel. Bundling Android's model avoids a first-use download. Check the resolved Android minimum SDK before adding the dependency; the current Gradle file inherits Flutter's minimum. The iOS deployment target is 15.0. Add the new Swift file to Runner's explicit Xcode Sources list and convert Vision's bottom-left boxes to the shared top-left contract.
- Read the local camera/gallery file and return recognized lines only. Make no HTTP request. Handle unsupported platforms and initialization failures with a retry/manual-entry state; release recognizer resources after use.
- Verify that real text recognition works on Android and iOS devices with network disabled. Add adapter tests with a fake platform channel.

### 2. Preserve useful image content locally

- Update the viewfinder guide in `lib/module/core_banking/screens/snap_to_pay_page.dart` to frame both bank name and number. Replace the current 35%-height center crop, which can remove the bank name. Because images are never uploaded, capture at the highest available camera resolution and read gallery images at original size, passing the full oriented still image to local OCR. Add native still capture only if device tests show the camera plugin's maximum resolution is not legible enough.
- Keep gallery selection working when camera permission is denied. Do not retain a processed copy or OCR result beyond the active scan. Delete any temporary copy created by this feature on rescan or exit. Do not add image upload or base64 conversion.
- Test images with bank name above and below the number, rotation, and camera/gallery parity.

### 3. Parse numbers and match bank names in Dart

- Add a pure extractor in `lib/module/core_banking/service/` that receives recognized lines and returns distinct ten-digit account-number candidates and bank-name candidates. Use line positions as a ranking signal, never as permission to discard another plausible number silently. Preserve leading zeroes.
- Add a pure matcher that receives bank text and `scanToPayBanks(...)` and returns ordered `CommercialBank` candidates with `unique`, `ambiguous`, or `none` status. Normalize case, punctuation, whitespace, and common legal suffixes; use a small reviewed alias table. Map only to codes in the current bank list, except the existing BOCTRUST internal option. Similarity matches require user selection, and different codes remain separate choices.
- Test separated digits, leading zeroes, 11-digit strings, phone-number distractors, two account numbers, common aliases, OCR spelling errors, no match, duplicate-looking banks, and BOCTRUST.

### 4. Review candidates and run account lookup

- Update `ScannedAccountResult` and page state in `lib/module/core_banking/screens/snap_to_pay_page.dart` to show an editable number, proposed bank, alternative banks, full bank picker, and verified account name. Use explicit recognizing, reviewing, looking-up, verified, and error states.
- Use `boctrustNameEnquiry(number)` for BOCTRUST and `lookUpAccountName(ref, bankCode: ..., accountNumber: ...)` for other banks. Bind every lookup to the exact `(bankCode, number)` pair or a generation token. Clear verification on edit, rescan, or exit. Never start lookup while the number or bank is ambiguous.
- Keep the existing `onSend(route, number, bankCode)` handoff. Enable Continue only after a successful lookup for the current pair. A failed bank-list request offers Retry; a failed OCR attempt offers retake, gallery, or manual entry; a failed lookup offers correction and Retry.
- Widget tests: a unique bank is preselected but still waits for Check account; a lone unrelated ten-digit string sends no request without confirmation; multiple bank matches require selection; no bank match opens the picker; multiple numbers require correction; correct BOCTRUST/interbank endpoint; 404 and offline errors; stale reply after edit; no payment submission from Scan to pay.

### 5. Remove the remote OCR dependency and validate

- Stop calling `CoreOcrService.readNumber` from Scan to pay and `SnapNumberButton`; route both through local recognition and shared number extraction. Replace upload-specific tests when switching callers, so the focused suite passes at that step. Remove obsolete `POST /me/snap-to-pay` wiring from `lib/app/core_api_endpoints.dart` and the OCR service when no caller remains.
- Update `FeatureCapability.scanToPay` in `lib/app/feature_capability.dart`: it currently requires the remote OCR operation. Express availability through the local scanner and the Core operations needed for bank list/account enquiry, or split scanning availability from transfer availability if the registry cannot represent that accurately. Update capability tests.
- Run focused Flutter tests and `flutter analyze`, then device checks on Android and iOS with network disabled for extraction. Test printed slips and gallery screenshots, low light, rotation, no bank name, ambiguous banks, multiple numbers, denied camera permission, and slow/offline lookup. Confirm network logs show only bank-list and account-enquiry requests.
- Release behind the current Scan to pay availability gate. The app has no analytics pipeline, so success, correction, ambiguity, and latency are recorded from the device checks; any future metrics must exclude raw images, OCR text, account numbers, and account names.

## Constraints and decisions

- **Local-only extraction:** camera and gallery images, OCR text, and bank-name parsing stay on the phone. Core receives the account number and bank code only for recipient lookup.
- **No backend OCR dependency:** `/me/snap-to-pay` is removed from this flow; extraction needs no backend contract change.
- **Ambiguity:** never auto-select among multiple distinct ten-digit numbers or multiple plausible bank codes.
- **Offline behavior:** extraction and bank-text parsing work without connectivity. A bank list is still needed to map a code, and account name enquiry requires connectivity. Do not mark an account verified while offline.
- **Platform basis:** [Apple Vision](https://developer.apple.com/documentation/vision/recognizing-text-in-images) performs text recognition on-device; [Android ML Kit](https://developers.google.com/ml-kit/vision/text-recognition/v2/android) offers a bundled model.
- **Plan handoff:** `docs/` is Git-ignored; explicitly force-add the design and coding plan when committing planning artifacts for another checkout.
