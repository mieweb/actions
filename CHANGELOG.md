# Changelog

## v2.1.0

### Added

- `sign-archive-upload-ios` — new iOS signing mode `cert-api`: imports a raw
  `.p12` distribution certificate from a secret and downloads the App Store
  provisioning profile via the App Store Connect API key (Fastlane `sigh`,
  read-only). No provisioning-profile secret required. The existing API key is
  reused, so no new secrets are needed beyond the cert.
- `.github/workflows/build-mobile-from-meteor.yml` — now declares all signing
  secrets explicitly (every secret optional), so callers with channel-specific
  secret names can map them per channel (e.g.
  `ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_DEV_BASE64 }}`).
  Callers with conventional names can still use `secrets: inherit`.

### Changed

- `build-ios-from-meteor.yml` now forwards `IOS_DIST_CERT_P12_BASE64`,
  `IOS_DIST_CERT_PASSWORD`, and `IOS_PROVISIONING_PROFILE_BASE64` to the iOS
  action, enabling `secrets` and `cert-api` modes through the reusable workflow.
- `import-signing.sh` treats the provisioning profile as optional (cert-only
  import for `cert-api` mode).

### Fixed

- `publish-android-to-play` — a partial staged rollout with
  `release_status: completed` is now automatically coerced to `inProgress`,
  which Google Play requires (previously rejected the upload).

## v2.0.0

### Breaking changes

The composite actions and reusable workflows were renamed to verb-first,
descriptive names. Update any `uses:` references from `@v1` to `@v2` and the new
paths:

| Old (`@v1`) | New (`@v2`) |
|---|---|
| `setup-meteor` | `prepare-meteor-cordova-env` |
| `setup-expo` | `prepare-expo-env` |
| `meteor-build` | `run-meteor-build` |
| `ios` | `sign-archive-upload-ios` |
| `.github/workflows/ios-meteor.yml` | `.github/workflows/build-ios-from-meteor.yml` |
| `.github/workflows/ios-expo.yml` | `.github/workflows/build-ios-from-expo.yml` |

### Added — Android support

- `prepare-android-env` — composite action: JDK, Node, Android SDK, Gradle, Meteor.
- `build-sign-android` — composite action: build + sign AAB/APK with dual
  signing (`direct-keystore` or `fastlane`), mirroring the iOS `match`/`secrets`
  split.
- `publish-android-to-play` — composite action: upload a signed AAB to a Google
  Play track via Fastlane `supply`, with staged-rollout support.
- `.github/workflows/build-android-from-meteor.yml` — reusable workflow:
  end-to-end Meteor/Cordova Android build, sign, and publish.
- `.github/workflows/build-mobile-from-meteor.yml` — reusable workflow:
  channel-agnostic orchestrator that builds iOS and Android in parallel.

## v1.0.0

- Initial release: iOS-only composite actions (`setup-meteor`, `setup-expo`,
  `meteor-build`, `ios`) and reusable workflows (`ios-meteor.yml`,
  `ios-expo.yml`).
