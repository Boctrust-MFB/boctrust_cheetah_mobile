# Test feedback remediation design

## Intent

Resolve seven tester reports in the Flutter app without misrepresenting transfer outcomes, weakening authentication, or revealing another customer's financial data. The reports cover Dojah liveness, intrabank transfer results, biometric enrollment, balance visibility, SmartSave targets, airtime/data numbers, and secret changes.

## Approach

Use focused corrections in each owning flow, with a regression check at the boundary that failed. Keep Core and Dojah authoritative for transaction and identity outcomes. Use the existing per-user `SharedPreferences` pattern for the local balance display preference. Client validation should give immediate feedback, with matching server enforcement for security rules.

The main alternative is a broad rewrite of the shared form, transfer, and authentication layers. That would touch unrelated flows and obscure which correction addressed each report. A second alternative is copy-only or UI-only changes; that would leave invalid requests and secret reuse possible. Focused changes fit the current architecture and can ship independently.

## Requirements and decisions

- Dojah: identify the native Android crash from a symbolized crash trace and device/build details before changing SDK routing or versions. Provider capture completion remains a capture outcome; backend KYC status remains the verdict.
- Transfers: a failed result must show a support usable identifier when one exists. If the acknowledgement has no display reference, never promise a "reference below". Keep receipt references distinct from intrabank re-query identifiers. Preserve the actual transfer state and avoid suggesting a retry before checking possible debit.
- Biometric enrollment: a wrong PIN or password must give an error and keep the user in the enrollment dialog. A truly expired session may still require sign-in. PIN/password should not be persisted unless server verification and device biometric confirmation both succeed.
- Balance visibility: after a user chooses hidden, the Home balance and recent transaction amounts remain masked through force close/reopen and logout/login on that device. A different signed-in user must not inherit the prior user's choice. First-use default is **hidden** as the privacy-safe proposal; product can choose another default explicitly.
- SmartSave: current client logic requires target **strictly greater** than the duration quote's opening deposit; ₦5,000.00 is invalid when opening deposit is ₦5,000.00, and ₦5,000.01 is valid. The product owner/Core team must confirm this is the intended contract before changing the acceptance boundary. Explain on the target step that the target must exceed the opening deposit, whose exact value depends on duration. Once duration is selected, show any quote-specific error at the target field or immediately beside its value, without forcing a blind backtrack.
- Airtime/data: allow only a Nigerian mobile number in the chosen input format. Proposed UI format is 11 digits beginning `0`; reject symbols, short/long values, and invalid prefixes. Confirm the Core biller contract before deciding whether to submit that local form or normalized `234` form. Other bill categories retain their own customer ID rules.
- Secret changes: reject `newPassword == currentPassword` and `newPin == currentPin` in the client before submission, with field-level feedback; the User Service must enforce the same rule for calls outside this app. Existing strength and confirmation checks remain in place.

## Boundaries

Do not include raw PINs, passwords, BVNs, selfies, or Dojah result payloads in diagnostic logs. Keep the seven fixes as separate reviewable changes. The Dojah fix remains contingent on reproducing the native failure; the savings boundary, phone serialization, and server-side secret rule require contract confirmation.
