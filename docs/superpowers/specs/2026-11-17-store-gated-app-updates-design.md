# Store-gated app updates: proposed design

## Intent

Tell users about an installable app update. A routine update may appear as a dismissible local notification. A required update blocks use of the app and takes the user to its store listing. Neither appears merely because Firebase configuration was published; the target release must be available to that user from the relevant store.

## Decisions for this plan

- Firebase Remote Config controls the update policy, separately for Android and iOS. Each platform names a target release. Versions follow `x.y.z+build`: a higher middle number (`1.x.0`, or a higher first number) is a major update and is **required**; a higher last number (`1.0.x`) is a minor update and is **optional**. A `force` flag in the config can make a minor update required.
- Android policy carries both the target version (for severity) and the target build number (what Play reports and confirms). iOS compares dotted numeric marketing versions. Invalid, missing, or inconsistent configuration disables the prompt.
- The app reads the installed version at runtime, fetches and activates Remote Config on launch and on return from the background, then verifies store availability before deciding. Checks are asynchronous and do not hold the splash screen.
- On Android, Google Play's in-app update availability and available version code are authoritative for Play-installed builds. On iOS, Apple's lookup response for the configured App Store app ID and the country configured in the policy (not the device locale) supplies the published version and listing URL. A missing or ambiguous result cannot authorize a required gate.
- A required update uses a full-screen, non-dismissible app-level gate above every route, including logged-out routes. It offers **Update** and **Retry**. Retry rechecks the store and installed version. Returning from the store rechecks automatically. The gate disappears after a qualifying install or Remote Config rollback; rollback reaches running apps through real-time Remote Config updates. It does not rely on an Android immediate-update flow.
- An optional update is the first client of a shared, feature-agnostic local-notification flow that other features will reuse: keyed notifications (a stable key replaces the previous post), a tap-action registry independent of route/inbox navigation (actions may run before sign-in), and a once-per-key ledger in `SharedPreferences`. The update notification's tap action opens the verified store listing. Dismissal is handled by the operating system. Show at most once per target release on a device, recorded only after the post succeeds with notifications enabled. If permission is off or the plugin is unavailable, skip it without asking for permission and retry at a later check.
- If Firebase is unavailable, store verification fails, the app is installed from a non-Play source on Android, or a store listing is absent in the selected iOS country, the app remains usable and retries on a later launch or foreground entry. Previously cached Remote Config can propose a policy, but it still needs a fresh store check before a required gate. Once a gate is showing, an inconclusive recheck (network or store error) keeps it; only a conclusive result (installed at or above target, policy no longer requiring, or store reporting not available) clears it.
- The release process publishes the binary to the intended store track/territories, verifies availability on a real eligible device, and only then publishes Remote Config. Client store verification remains mandatory because rollout and territory availability can differ per user.

## Scope and limitations

This design covers Android and iOS. It adds no push campaign, background polling, account-specific rule, or web/desktop update path. Apple's public lookup result establishes the published listing version in a country, but it cannot prove that every individual Apple account or device can install it; the app therefore treats lookup failures and mismatches as unknown and never blocks on them. Store availability can change after a check, so Retry remains available on the gate.

## Approaches considered

1. Remote Config alone: simplest, but can force a user before store rollout reaches them. Rejected.
2. Store version alone: proves availability, but cannot let the release team force a minor update or switch prompting off. Rejected.
3. Remote Config policy plus per-platform store confirmation: chosen because both severity and installability must be true before a prompt appears.

## Acceptance

- Config ahead of the store produces no notification or gate.
- Optional target available in the store produces one dismissible local notification per target; tapping it opens the verified listing.
- A major target (or a forced minor target) available in the store produces a persistent required gate on launch and resume; notification permission does not affect it.
- Store lookup failures, unsupported installation sources, malformed configuration, and Firebase failure never create a required gate.
- Updating the installed app or disabling the policy or clearing `force` removes the gate on the next check.
