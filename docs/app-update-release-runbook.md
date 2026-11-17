# App update release runbook

How to tell installed Cheetah apps that a new store release exists, and when
that update blocks the app. The app reads one Firebase Remote Config
parameter, checks the store itself, and only then shows anything.

## The parameter

Create one parameter in Firebase Remote Config:

- **Key:** `app_update_policy_v1`
- **Data type:** JSON (a JSON string value)
- **Conditions:** none. Use the default value only.

In-app default (used until a fetch succeeds):

```json
{"android":{"enabled":false},"ios":{"enabled":false}}
```

Full shape:

```json
{
  "android": { "enabled": true, "targetVersion": "1.1.0", "targetBuild": 12, "force": false },
  "ios": { "enabled": true, "targetVersion": "1.1.0", "appStoreId": "1234567890", "country": "ng", "force": false }
}
```

A platform entry is used only when every rule holds; anything else, including
a missing platform object, means disabled:

- `enabled` is `true`.
- `targetVersion` is exactly three dot-separated non-negative integers.
- `targetBuild` is a positive integer (Android).
- `force` is a boolean when present. It defaults to `false`.
- `appStoreId` is all digits (iOS).
- `country` is two lowercase letters (iOS).

There are no URLs in the policy. The Android store link is built from the
installed package name. The iOS link is the App Store lookup result's
`trackViewUrl`, accepted only for `https` on `apps.apple.com`.

## Version rules

Versions follow `pubspec.yaml` `version: x.y.z+build` (currently `1.0.0+1`).

- **Required** (full-screen gate): the target's first or middle number is
  higher than the installed one, for example `1.0.4` to `1.1.0`.
- **Optional** (one notification per target version): a last-number bump such
  as `1.0.0` to `1.0.1`, or an Android rebuild of the same version with a
  higher build number.
- **`force: true`** turns an optional update into a required one.
- **Already up to date:** on Android, the installed build is at least
  `targetBuild`; on iOS, the installed version is at least `targetVersion`.

On Android, `targetVersion` and `targetBuild` must match the released
`pubspec.yaml` `version` (`targetVersion` is `x.y.z`, `targetBuild` is
`build`). `targetVersion` decides severity; `targetBuild` is what Play
confirms.

Every store release raises the build number. iOS compares the marketing
version only, so every App Store release also needs a new `x.y.z`.

## Publish order

1. Publish the binary to the intended Play track or App Store territories.
2. Verify on a real device that the store offers it (checks below).
3. Publish the policy.

A middle-number release gates users as soon as its policy is published.
Publish it only after the store release is confirmed. Set `force: true` on a
last-number release only once forcing that update is approved.

Do not publish an enabled policy until both are true:

- A store release with a higher version is live on the intended track or
  territories.
- The installed base runs a binary that contains this feature.

## Android check

On an eligible device with a build installed from Play (not sideloaded),
confirm Play reports the target version code, for example by opening the
Play listing and seeing **Update**. The app asks Play for the available
release; if Play does not report a build at or above `targetBuild`, nothing
is shown.

## iOS check

```sh
curl 'https://itunes.apple.com/lookup?id=<appStoreId>&country=ng'
```

The single result must have the app's `bundleId` and the target `version`.
The lookup is CDN-cached and can lag a release by hours, so wait for it
before publishing the policy. Capture the real App Store ID and set
`appStoreId` before enabling iOS.

### Phased release

Avoid a required gate on iOS during phased availability: the lookup can
report the new version before every user can download it. Ship optional
(`force: false`, last-number bump) or wait until the phased release
completes.

## Rollback

Publish `enabled: false` (or `force: false` to drop a forced gate). Open apps
pick it up through real-time Remote Config and clear the gate. Apps that are
not running pick it up on their next launch.

## Behaviour notes

- If the store cannot be reached, the app keeps its previous decision; it
  never creates a gate from an uncertain check and never blocks startup.
- The app does not ask for notification permission for this. Users who have
  not granted it simply see no optional-update notification.
- Debug builds never check for updates.
