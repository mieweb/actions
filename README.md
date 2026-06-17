# actions

Reusable composite GitHub Actions and workflows for mieweb CI/CD pipelines.

📄 **Docs site:** https://mieweb.github.io/actions

Any developer in the mieweb org can call these from their caller workflow —
use `secrets: inherit` and pass the required inputs.

## Why use this (the pain it removes)

Shipping an iOS app from CI is deceptively hard. The build is the easy part —
the pain is everything around it. If you've ever set up iOS CI from scratch,
you've lost days to some of these:

- **Code signing is a black hole.** Certificates, provisioning profiles,
  keychains, the Apple Developer portal, `.p12` exports, `.mobileprovision`
  files, App Store Connect API keys — get one wrong and you get a cryptic
  `No signing certificate "iOS Distribution" found` after a 20-minute build.
- **Secrets are everywhere and copied everywhere.** Every repo re-pastes the
  same base64 cert, team ID, and API key into its own GitHub secrets. Rotate a
  cert and you're editing ten repos by hand.
- **Every project reinvents the same 150 lines of YAML.** Xcode selection,
  Node + Meteor/Expo setup, `pod install`, Fastlane, archive, export,
  TestFlight upload — copy-pasted between repos, then drifting out of sync the
  moment one of them gets a fix the others never receive.
- **It "works on my machine."** Local builds sign fine; CI fails because the
  runner has no keychain, no certs, and a different Xcode. Debugging means
  pushing commit after commit and waiting on a macOS runner each time.
- **Fastlane, Ruby, and CocoaPods are a setup tax.** Pinning Ruby versions,
  bundler caching, gem installs, Cordova pod quirks — all incidental work that
  has nothing to do with your app.

These actions absorb all of that. Signing is centralized (use `match` to share
one identity across repos, or `secrets` for a one-off), secrets live once at the
org level and are inherited, and the whole setup → build → sign → upload
pipeline is a single `uses:` line that every repo gets fixes for at once.

**Before** — every repo owns ~150 lines of fragile, drifting YAML and its own
copy of the signing secrets.

**After:**

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/build-ios-from-meteor.yml@v2
    secrets: inherit
    with:
      app_identifier: org.mieweb.os.dev
      meteor_server: https://app.example.com
```

That's the whole thing. Push, and TestFlight gets a build. Android works the
same way via [`build-android-from-meteor.yml`](#build-android-from-meteoryml--reusable-workflow),
or build both at once with [`build-mobile-from-meteor.yml`](#build-mobile-from-meteoryml--reusable-workflow).

## Required secrets

Store these at the **GitHub org level** so every repo inherits them via
`secrets: inherit` (see [Org-level secrets](#org-level-secrets-recommended)).
The four App Store Connect secrets are always required; the signing secrets
depend on which `signing_mode` you use.

| Secret | Required | Used by | Description |
|---|---|---|---|
| `APPLE_TEAM_ID` | **always** | all | Apple Developer Team ID |
| `APPLE_API_KEY_ID` | **always** | all | App Store Connect API Key ID |
| `APPLE_API_ISSUER_ID` | **always** | all | App Store Connect Issuer ID |
| `APPLE_API_KEY_P8_BASE64` | **always** | all | Base64-encoded App Store Connect API key (`.p8`) |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `match` mode | signing | Base64 `user:token` for the match signing repo |
| `MATCH_PASSWORD` | `match` mode | signing | Encryption passphrase for match-stored certs/profiles |
| `IOS_DIST_CERT_P12_BASE64` | `secrets` mode | signing | Base64-encoded distribution certificate (`.p12`) |
| `IOS_DIST_CERT_PASSWORD` | `secrets` mode | signing | Password for the `.p12` certificate |
| `IOS_PROVISIONING_PROFILE_BASE64` | `secrets` mode | signing | Base64-encoded provisioning profile (`.mobileprovision`) |

### Android secrets

For Android builds (the `build-android-from-meteor.yml` workflow and the
`build-sign-android` / `publish-android-to-play` actions):

| Secret | Required | Used by | Description |
|---|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | `direct-keystore` mode | signing | Base64-encoded keystore (`.jks` / `.keystore`) |
| `ANDROID_KEYSTORE_PASSWORD` | `direct-keystore` mode | signing | Keystore password |
| `ANDROID_KEY_ALIAS` | `direct-keystore` mode | signing | Signing key alias |
| `ANDROID_KEY_PASSWORD` | `direct-keystore` mode | signing | Signing key password |
| `GOOGLE_PLAY_JSON_KEY_BASE64` | publishing | publish | Base64-encoded Google Play service account JSON |
| `GOOGLE_SERVICES_BASE64` | optional | build | Base64-encoded `google-services.json` (Firebase) |

## Table of contents

| Topic | Type | Why use it |
|---|---|---|
| [Required secrets](#required-secrets) | Guidance | The secrets every pipeline needs, and which signing mode requires which. |
| [`prepare-meteor-cordova-env`](#prepare-meteor-cordova-env--composite-action) | Composite action | Prepare a Meteor/Cordova iOS build environment (Xcode, Node, Meteor, npm install) before building. |
| [`prepare-expo-env`](#prepare-expo-env--composite-action) | Composite action | Prepare an Expo build environment (Xcode, Node, JS deps) before `expo prebuild`. |
| [`prepare-android-env`](#prepare-android-env--composite-action) | Composite action | Prepare a Meteor/Cordova Android build environment (JDK, Node, Android SDK, Meteor) before building. |
| [`run-meteor-build`](#run-meteor-build--composite-action) | Composite action | Run `meteor build` for a platform with a configurable server URL. |
| [`sign-archive-upload-ios`](#sign-archive-upload-ios--composite-action) | Composite action | Sign, archive, and optionally upload an iOS app to TestFlight. |
| [`build-sign-android`](#build-sign-android--composite-action) | Composite action | Build and sign an Android AAB/APK (direct-keystore or fastlane). |
| [`publish-android-to-play`](#publish-android-to-play--composite-action) | Composite action | Upload a signed AAB to a Google Play track. |
| [`build-ios-from-meteor.yml`](#build-ios-from-meteoryml--reusable-workflow) | Reusable workflow | One-call end-to-end pipeline for Meteor/Cordova iOS apps. |
| [`build-ios-from-expo.yml`](#build-ios-from-expoyml--reusable-workflow) | Reusable workflow | One-call end-to-end pipeline for Expo iOS apps. |
| [`build-android-from-meteor.yml`](#build-android-from-meteoryml--reusable-workflow) | Reusable workflow | One-call end-to-end pipeline for Meteor/Cordova Android apps. |
| [`build-mobile-from-meteor.yml`](#build-mobile-from-meteoryml--reusable-workflow) | Reusable workflow | One-call pipeline that builds iOS and Android in parallel. |
| [Org-level secrets](#org-level-secrets-recommended) | Guidance | Where to store shared signing secrets so every repo inherits them. |
| [Important notes](#important-notes) | Guidance | Gotchas to know before calling the signing actions directly. |

## Components

### `prepare-meteor-cordova-env` — Composite action

Sets up the Meteor/Cordova build environment: checks out the repo, selects
Xcode, installs Node.js and Meteor, and runs `meteor npm install`.

```yaml
- uses: mieweb/actions/prepare-meteor-cordova-env@v2
  with:
    xcode_path:   /Applications/Xcode_26.app  # optional, default
    node_version: "20"                       # optional, default
```

### `prepare-expo-env` — Composite action

Sets up the Expo build environment: checks out the repo, selects Xcode,
installs Node.js, and installs the project's JS dependencies (npm, yarn, or
pnpm). Does **not** run `expo prebuild` — the workflow does that after the
optional pre-build hook.

```yaml
- uses: mieweb/actions/prepare-expo-env@v2
  with:
    xcode_path:        /Applications/Xcode_26.app  # optional, default
    node_version:      "20"                        # optional, default
    package_manager:   npm                         # optional: npm | yarn | pnpm
    working_directory: .                           # optional: path to package.json
```

### `prepare-android-env` — Composite action

Sets up the Meteor/Cordova **Android** build environment: checks out the repo,
installs the JDK, Node.js, the Android SDK (platform + build-tools), Gradle,
and Meteor, then runs `meteor npm install`. Runs on `ubuntu-latest`.

```yaml
- uses: mieweb/actions/prepare-android-env@v2
  with:
    java_version:        "17"      # optional, default
    node_version:        "20"      # optional, default
    android_api_level:   "34"      # optional, default
    android_build_tools: "35.0.0"  # optional, default
```

### `run-meteor-build` — Composite action

Runs `meteor build` for the given platform with a configurable DDP server URL
and output directory. Used by the reusable workflows between environment setup
and signing.

```yaml
- uses: mieweb/actions/run-meteor-build@v2
  with:
    platform:   android            # 'ios' or 'android'
    server:     https://app.example.com
    output_dir: ./android-build    # optional, default ./ios-build
```

### `sign-archive-upload-ios` — Composite action

Signs, archives, and optionally uploads an iOS app to TestFlight via Fastlane.
Supports two code-signing strategies.

| Mode | How it works | When to use |
|---|---|---|
| `match` | Fetches encrypted cert + profile from a shared git repo, decrypts with `match_password` | Multiple repos share one signing identity |
| `secrets` | Decodes a raw `.p12` cert + `.mobileprovision` from GitHub secrets, imports into a temporary keychain | Single repo, or you want to avoid a signing repo dependency |

```yaml
- uses: mieweb/actions/sign-archive-upload-ios@v2
  with:
    signing_mode: match
    app_identifier: org.mieweb.os.dev
    apple_team_id: ${{ secrets.APPLE_TEAM_ID }}
    match_git_basic_authorization: ${{ secrets.MATCH_GIT_BASIC_AUTHORIZATION }}
    match_password: ${{ secrets.MATCH_PASSWORD }}
    apple_api_key_id: ${{ secrets.APPLE_API_KEY_ID }}
    apple_api_issuer_id: ${{ secrets.APPLE_API_ISSUER_ID }}
    apple_api_key_p8_base64: ${{ secrets.APPLE_API_KEY_P8_BASE64 }}
```

#### Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `signing_mode` | | `match` | `match` or `secrets` |
| `app_identifier` | **yes** | — | Bundle ID |
| `apple_team_id` | **yes** | — | Apple Developer Team ID |
| `match_git_url` | if match | `https://github.com/mieweb/mobile-signing` | Match signing repo URL |
| `match_git_basic_authorization` | if match | — | Base64 `user:token` for the signing repo |
| `match_password` | if match | — | Encryption passphrase for match |
| `match_type` | | `appstore` | Match profile type |
| `match_readonly` | | `true` | Never create/renew certs in CI |
| `ios_cert_p12_base64` | if secrets | — | Base64 distribution cert (.p12) |
| `ios_cert_password` | if secrets | — | Password for the .p12 |
| `ios_prov_profile_base64` | if secrets | — | Base64 provisioning profile |
| `apple_api_key_id` | **yes** | — | App Store Connect API Key ID |
| `apple_api_issuer_id` | **yes** | — | App Store Connect Issuer ID |
| `apple_api_key_p8_base64` | **yes** | — | Base64 API key (.p8) |
| `workspace_path` | | auto-discovered | Path to `.xcworkspace` |
| `xcode_scheme` | | auto-discovered | Xcode scheme name |
| `run_pod_install` | | `false` | Run `pod install` before Fastlane (set `true` for Cordova) |
| `upload_to_testflight` | | `true` | Upload IPA to TestFlight. Set `false` to stop after producing a signed IPA (no upload). |
| `ruby_version` | | `3.4` | Ruby version for Fastlane |

### `build-sign-android` — Composite action

Builds and signs an Android app (AAB or APK) from a Cordova/Gradle project.
Supports two signing strategies — the Android mirror of the iOS
`match`/`secrets` split.

| Mode | How it works | When to use |
|---|---|---|
| `direct-keystore` | Decodes a keystore from a GitHub secret and signs via Gradle's injected signing properties | Single repo with its own keystore (recommended) |
| `fastlane` | Delegates to the bundled Fastlane `build_signed_bundle` lane | You already standardize on Fastlane for Android |

```yaml
- uses: mieweb/actions/build-sign-android@v2
  id: sign
  with:
    signing_method:    direct-keystore   # or 'fastlane'
    app_identifier:    com.bluehive.ozwell
    android_build_dir: android-build     # dir containing the Gradle project
    build_type:        bundle            # 'bundle' (AAB) or 'apk'
    keystore_base64:   ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
    keystore_password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
    key_alias:         ${{ secrets.ANDROID_KEY_ALIAS }}
    key_password:      ${{ secrets.ANDROID_KEY_PASSWORD }}
```

The signed artifact path is exposed as `steps.sign.outputs.signed_artifact_path`.

#### Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `signing_method` | | `direct-keystore` | `direct-keystore` or `fastlane` |
| `app_identifier` | **yes** | — | Android applicationId |
| `android_build_dir` | | `android-build` | Dir containing the Gradle project (auto-discovers `gradlew`) |
| `project_dir` | | auto-discovered | Explicit Gradle project root |
| `build_type` | | `bundle` | `bundle` (AAB) or `apk` |
| `google_services_base64` | | — | Base64 `google-services.json` written before build |
| `keystore_base64` | if direct-keystore | — | Base64 keystore |
| `keystore_password` | if direct-keystore | — | Keystore password |
| `key_alias` | if direct-keystore | — | Signing key alias |
| `key_password` | if direct-keystore | — | Signing key password |
| `ruby_version` | | `3.4` | Ruby version (fastlane mode) |

### `publish-android-to-play` — Composite action

Uploads a signed AAB to a Google Play track via Fastlane `supply`. Supports
staged rollouts for production.

```yaml
- uses: mieweb/actions/publish-android-to-play@v2
  with:
    signed_artifact_path: ${{ steps.sign.outputs.signed_artifact_path }}
    play_json_key_base64: ${{ secrets.GOOGLE_PLAY_JSON_KEY_BASE64 }}
    package_name:         com.bluehive.ozwell
    track:                internal          # internal | alpha | beta | production
    rollout_fraction:     ""                # e.g. '0.1' for a 10% staged rollout
```

#### Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `signed_artifact_path` | **yes** | — | Path to the signed `.aab` |
| `play_json_key_base64` | **yes** | — | Base64 Google Play service account JSON |
| `package_name` | **yes** | — | Android applicationId |
| `track` | | `internal` | `internal` \| `alpha` \| `beta` \| `production` |
| `rollout_fraction` | | — | Staged rollout fraction (empty = full release) |
| `release_status` | | `completed` | `completed` \| `draft` \| `halted` \| `inProgress` |

### `build-ios-from-meteor.yml` — Reusable workflow

Full pipeline for Meteor/Cordova iOS apps: setup → optional pre-build hook →
Meteor build → CocoaPods → Fastlane sign/archive → TestFlight upload.

#### Basic usage

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/build-ios-from-meteor.yml@v2
    secrets: inherit
    with:
      app_identifier: org.mieweb.os.dev
      meteor_server: https://app.example.com
```

#### With a pre-build hook (e.g. Firebase setup)

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/build-ios-from-meteor.yml@v2
    secrets: inherit
    with:
      app_identifier: org.mieweb.os.dev
      meteor_server: https://app.example.com
      pre_build_script: |
        bash scripts/setup-firebase.sh
```

The `pre_build_script` is inline bash that runs after the environment is set
up but before `meteor build`. Use it for any project-specific setup
(Firebase configs, environment files, asset generation, etc.).

#### Workflow inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `app_identifier` | **yes** | — | Bundle ID (e.g. `org.mieweb.os.dev`) |
| `meteor_server` | **yes** | — | Meteor DDP server URL |
| `xcode_path` | | `/Applications/Xcode_26.app` | Absolute path to Xcode.app |
| `node_version` | | `20` | Node.js version |
| `pre_build_script` | | — | Inline bash to run before `meteor build` |
| `signing_mode` | | `match` | `match` or `secrets` |
| `upload_to_testflight` | | `true` | Upload IPA to TestFlight |

#### Required secrets (org or repo level)

See [Required secrets](#required-secrets). Match mode (the default) needs the
four always-required secrets plus `MATCH_GIT_BASIC_AUTHORIZATION` and
`MATCH_PASSWORD`.

### `build-ios-from-expo.yml` — Reusable workflow

Full pipeline for Expo iOS apps: setup → optional pre-build hook → `expo
prebuild` → CocoaPods → Fastlane sign/archive → TestFlight upload.

For Expo apps only — the native `ios/` dir is regenerated each run from
`app.json` / `app.config.js`. The caller's project must have `expo` in its
dependencies. For bare React Native without `expo`, call the
`sign-archive-upload-ios` action directly.

#### Basic usage

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/build-ios-from-expo.yml@v2
    secrets: inherit
    with:
      app_identifier: com.example.app
```

#### With yarn / pnpm or a monorepo subdirectory

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/build-ios-from-expo.yml@v2
    secrets: inherit
    with:
      app_identifier:    com.example.app
      package_manager:   pnpm
      working_directory: apps/mobile
```

#### With a pre-build hook (e.g. Firebase setup)

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/build-ios-from-expo.yml@v2
    secrets: inherit
    with:
      app_identifier:   com.example.app
      pre_build_script: |
        bash scripts/setup-firebase.sh
```

The `pre_build_script` is inline bash that runs after JS deps are installed
but **before** `expo prebuild`, so the script can place files (e.g.
`GoogleService-Info.plist`) that the prebuild step picks up. The script's
working directory is `working_directory` (defaults to repo root).

#### Workflow inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `app_identifier` | **yes** | — | Bundle ID (must match `app.json` / Info.plist) |
| `xcode_path` | | `/Applications/Xcode_26.app` | Absolute path to Xcode.app |
| `node_version` | | `20` | Node.js version |
| `package_manager` | | `npm` | `npm` \| `yarn` \| `pnpm` |
| `working_directory` | | `.` | Path to the Expo project (where `package.json` lives) |
| `pre_build_script` | | — | Inline bash to run before `expo prebuild`, executed from `working_directory` |
| `signing_mode` | | `match` | `match` or `secrets` |
| `upload_to_testflight` | | `true` | Upload IPA to TestFlight |

#### Required secrets (org or repo level)

See [Required secrets](#required-secrets). The four always-required App Store
Connect secrets, plus either the `match`-mode pair or the `secrets`-mode trio
depending on your `signing_mode`.

### `build-android-from-meteor.yml` — Reusable workflow

Full pipeline for Meteor/Cordova Android apps: setup → optional pre-build hook
→ Meteor build → Gradle sign (AAB/APK) → optional Google Play upload. Runs on
`ubuntu-latest`.

#### Basic usage

```yaml
jobs:
  android:
    uses: mieweb/actions/.github/workflows/build-android-from-meteor.yml@v2
    secrets: inherit
    with:
      app_identifier: com.bluehive.ozwell
      meteor_server: https://app.example.com
```

#### Workflow inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `app_identifier` | **yes** | — | Android applicationId |
| `meteor_server` | **yes** | — | Meteor DDP server URL |
| `node_version` | | `20` | Node.js version |
| `java_version` | | `17` | JDK version |
| `android_api_level` | | `34` | Android SDK platform API level |
| `android_build_tools` | | `35.0.0` | Android SDK build-tools version |
| `pre_build_script` | | — | Inline bash to run before `meteor build` |
| `signing_method` | | `direct-keystore` | `direct-keystore` or `fastlane` |
| `build_type` | | `bundle` | `bundle` (AAB) or `apk` |
| `upload_to_play` | | `true` | Upload the signed AAB to Google Play |
| `play_track` | | `internal` | `internal` \| `alpha` \| `beta` \| `production` |
| `rollout_fraction` | | — | Staged rollout fraction (empty = full release) |

#### Required secrets (org or repo level)

See [Android secrets](#android-secrets). Direct-keystore signing needs the four
`ANDROID_*` secrets; publishing needs `GOOGLE_PLAY_JSON_KEY_BASE64`.

### `build-mobile-from-meteor.yml` — Reusable workflow

One-call pipeline that builds **iOS and Android in parallel** from a single
caller. Choose `platforms: ios | android | both`. This workflow is
channel-agnostic — the caller decides app identifiers, server, and Play track
per release channel and passes them in.

#### Basic usage

```yaml
jobs:
  mobile:
    uses: mieweb/actions/.github/workflows/build-mobile-from-meteor.yml@v2
    secrets: inherit
    with:
      platforms:              both
      meteor_server:          https://app.example.com
      ios_app_identifier:     com.bluehive.ai
      android_app_identifier: com.bluehive.ozwell
      play_track:             internal
```

#### Workflow inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `platforms` | | `both` | `ios` \| `android` \| `both` |
| `meteor_server` | **yes** | — | Meteor DDP server URL |
| `node_version` | | `20` | Node.js version |
| `pre_build_script` | | — | Inline bash to run before `meteor build` |
| `ios_app_identifier` | if building iOS | — | iOS bundle ID |
| `xcode_path` | | `/Applications/Xcode_26.app` | Absolute path to Xcode.app |
| `ios_signing_mode` | | `match` | iOS `match` or `secrets` |
| `upload_to_testflight` | | `true` | Upload IPA to TestFlight |
| `android_app_identifier` | if building Android | — | Android applicationId |
| `java_version` | | `17` | JDK version |
| `android_signing_method` | | `direct-keystore` | Android `direct-keystore` or `fastlane` |
| `android_build_type` | | `bundle` | `bundle` (AAB) or `apk` |
| `upload_to_play` | | `true` | Upload the signed AAB to Google Play |
| `play_track` | | `internal` | `internal` \| `alpha` \| `beta` \| `production` |
| `rollout_fraction` | | — | Android staged rollout fraction |

## Org-level secrets (recommended)

Set shared signing secrets at the **GitHub org level** so every repo inherits
them automatically. Repos can override with repo-level secrets when they need
a different cert or profile.

## Important notes

- **`match_readonly` should always be `true` in CI.** Only set to `false` for
  one-time local seeding of the match signing repo.
- **Xcode must be selected before calling the `sign-archive-upload-ios` action
  directly.** The `build-ios-from-meteor.yml` / `build-ios-from-expo.yml`
  workflows and the `prepare-meteor-cordova-env` / `prepare-expo-env` actions
  handle this automatically.
- **The `.xcworkspace` must already exist.** Build your native project (e.g.
  `meteor build`, `expo prebuild`) before invoking the
  `sign-archive-upload-ios` action directly.
- **Android builds run on Linux.** `build-android-from-meteor.yml` uses
  `ubuntu-latest`; the Gradle project is auto-discovered under the Meteor
  build output directory.
