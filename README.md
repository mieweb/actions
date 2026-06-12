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
    uses: mieweb/actions/.github/workflows/ios-meteor.yml@v1
    secrets: inherit
    with:
      app_identifier: org.mieweb.os.dev
      meteor_server: https://app.example.com
```

That's the whole thing. Push, and TestFlight gets a build.

## Table of contents

| Topic | Type | Why use it |
|---|---|---|
| [`setup-meteor`](#setup-meteor--composite-action) | Composite action | Prepare a Meteor/Cordova build environment (Xcode, Node, Meteor, npm install) before building. |
| [`setup-expo`](#setup-expo--composite-action) | Composite action | Prepare an Expo build environment (Xcode, Node, JS deps) before `expo prebuild`. |
| [`ios`](#ios--composite-action) | Composite action | Sign, archive, and optionally upload an iOS app to TestFlight. Use directly for bare React Native or custom pipelines. |
| [`ios-meteor.yml`](#ios-meteoryml--reusable-workflow) | Reusable workflow | One-call end-to-end pipeline for Meteor/Cordova iOS apps. |
| [`ios-expo.yml`](#ios-expoyml--reusable-workflow) | Reusable workflow | One-call end-to-end pipeline for Expo iOS apps. |
| [Org-level secrets](#org-level-secrets-recommended) | Guidance | Where to store shared signing secrets so every repo inherits them. |
| [Important notes](#important-notes) | Guidance | Gotchas to know before calling the `ios` action directly. |

## Components

### `setup-meteor` — Composite action

Sets up the Meteor/Cordova build environment: checks out the repo, selects
Xcode, installs Node.js and Meteor, and runs `meteor npm install`.

```yaml
- uses: mieweb/actions/setup-meteor@v1
  with:
    xcode_path:   /Applications/Xcode_26.app  # optional, default
    node_version: "20"                       # optional, default
```

### `setup-expo` — Composite action

Sets up the Expo build environment: checks out the repo, selects Xcode,
installs Node.js, and installs the project's JS dependencies (npm, yarn, or
pnpm). Does **not** run `expo prebuild` — the workflow does that after the
optional pre-build hook.

```yaml
- uses: mieweb/actions/setup-expo@v1
  with:
    xcode_path:        /Applications/Xcode_26.app  # optional, default
    node_version:      "20"                        # optional, default
    package_manager:   npm                         # optional: npm | yarn | pnpm
    working_directory: .                           # optional: path to package.json
```

### `ios` — Composite action

Signs, archives, and optionally uploads an iOS app to TestFlight via Fastlane.
Supports two code-signing strategies.

| Mode | How it works | When to use |
|---|---|---|
| `match` | Fetches encrypted cert + profile from a shared git repo, decrypts with `match_password` | Multiple repos share one signing identity |
| `secrets` | Decodes a raw `.p12` cert + `.mobileprovision` from GitHub secrets, imports into a temporary keychain | Single repo, or you want to avoid a signing repo dependency |

```yaml
- uses: mieweb/actions/ios@v1
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

### `ios-meteor.yml` — Reusable workflow

Full pipeline for Meteor/Cordova iOS apps: setup → optional pre-build hook →
Meteor build → CocoaPods → Fastlane sign/archive → TestFlight upload.

#### Basic usage

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/ios-meteor.yml@v1
    secrets: inherit
    with:
      app_identifier: org.mieweb.os.dev
      meteor_server: https://app.example.com
```

#### With a pre-build hook (e.g. Firebase setup)

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/ios-meteor.yml@v1
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

`APPLE_TEAM_ID`, `MATCH_GIT_BASIC_AUTHORIZATION`, `MATCH_PASSWORD`,
`APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8_BASE64`

### `ios-expo.yml` — Reusable workflow

Full pipeline for Expo iOS apps: setup → optional pre-build hook → `expo
prebuild` → CocoaPods → Fastlane sign/archive → TestFlight upload.

For Expo apps only — the native `ios/` dir is regenerated each run from
`app.json` / `app.config.js`. The caller's project must have `expo` in its
dependencies. For bare React Native without `expo`, call the `ios` action
directly.

#### Basic usage

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/ios-expo.yml@v1
    secrets: inherit
    with:
      app_identifier: com.example.app
```

#### With yarn / pnpm or a monorepo subdirectory

```yaml
jobs:
  ios:
    uses: mieweb/actions/.github/workflows/ios-expo.yml@v1
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
    uses: mieweb/actions/.github/workflows/ios-expo.yml@v1
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

`APPLE_TEAM_ID`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`,
`APPLE_API_KEY_P8_BASE64`, plus the match-mode pair
(`MATCH_GIT_BASIC_AUTHORIZATION`, `MATCH_PASSWORD`) or the secrets-mode trio
(`IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`,
`IOS_PROVISIONING_PROFILE_BASE64`).

## Org-level secrets (recommended)

Set shared signing secrets at the **GitHub org level** so every repo inherits
them automatically. Repos can override with repo-level secrets when they need
a different cert or profile.

## Important notes

- **`match_readonly` should always be `true` in CI.** Only set to `false` for
  one-time local seeding of the match signing repo.
- **Xcode must be selected before calling the `ios` action directly.** The
  `ios-meteor.yml` / `ios-expo.yml` workflows and the `setup-meteor` /
  `setup-expo` actions handle this automatically.
- **The `.xcworkspace` must already exist.** Build your native project (e.g.
  `meteor build`, `expo prebuild`) before invoking the `ios` action directly.
