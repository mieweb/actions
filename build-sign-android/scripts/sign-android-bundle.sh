#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# sign-android-bundle.sh — Direct-keystore Android build & sign
#
# Decodes a keystore from a GitHub secret, builds a release AAB or APK via the
# project's Gradle wrapper using injected signing properties, verifies the
# signature, and exports the artifact path.
#
# Expected env vars (set by action.yml):
#   PROJECT_DIR         Path to the Gradle project root (contains gradlew)
#   BUILD_TYPE          'bundle' (AAB) or 'apk'
#   KEYSTORE_BASE64     Base64-encoded keystore (.jks / .keystore)
#   KEYSTORE_PASSWORD   Keystore password
#   KEY_ALIAS           Signing key alias
#   KEY_PASSWORD        Signing key password
#
# Exports to $GITHUB_OUTPUT:
#   artifact_path       Absolute path to the signed .aab/.apk
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Validate required inputs ────────────────────────────────────────────────
for var in PROJECT_DIR BUILD_TYPE KEYSTORE_BASE64 KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::Required env var $var is not set"
    exit 1
  fi
done

# ── Decode keystore (with guaranteed cleanup) ───────────────────────────────
KEYSTORE_PATH="${RUNNER_TEMP}/release.keystore"
cleanup() { rm -f "$KEYSTORE_PATH"; }
trap cleanup EXIT

echo "$KEYSTORE_BASE64" | base64 --decode > "$KEYSTORE_PATH"

# ── Pick the Gradle task and output glob ────────────────────────────────────
case "$BUILD_TYPE" in
  bundle)
    GRADLE_TASK="bundleRelease"
    ARTIFACT_GLOB="app/build/outputs/bundle/release/*.aab"
    ;;
  apk)
    GRADLE_TASK="assembleRelease"
    ARTIFACT_GLOB="app/build/outputs/apk/release/*.apk"
    ;;
  *)
    echo "::error::Unsupported build_type: $BUILD_TYPE (use 'bundle' or 'apk')"
    exit 1
    ;;
esac

# ── Build with injected signing config ──────────────────────────────────────
cd "$PROJECT_DIR"
chmod +x ./gradlew

./gradlew "$GRADLE_TASK" --no-daemon \
  -Pandroid.injected.signing.store.file="$KEYSTORE_PATH" \
  -Pandroid.injected.signing.store.password="$KEYSTORE_PASSWORD" \
  -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
  -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

# ── Locate the produced artifact ────────────────────────────────────────────
ARTIFACT_PATH=$(ls -1 ${ARTIFACT_GLOB} 2>/dev/null | head -1 || true)
if [[ -z "$ARTIFACT_PATH" ]]; then
  echo "::error::No artifact found matching ${ARTIFACT_GLOB} under ${PROJECT_DIR}"
  exit 1
fi
ARTIFACT_PATH="$(cd "$(dirname "$ARTIFACT_PATH")" && pwd)/$(basename "$ARTIFACT_PATH")"

# ── Verify the signature ────────────────────────────────────────────────────
if [[ "$BUILD_TYPE" == "apk" ]]; then
  # apksigner ships with the build-tools; resolve the newest one on the runner.
  APKSIGNER=$(find "${ANDROID_HOME:-$ANDROID_SDK_ROOT}/build-tools" -name apksigner 2>/dev/null | sort -V | tail -1)
  if [[ -n "$APKSIGNER" ]]; then
    "$APKSIGNER" verify --verbose "$ARTIFACT_PATH"
  else
    echo "::warning::apksigner not found — skipping APK signature verification"
  fi
else
  # AAB: jarsigner verifies the v1 (JAR) signature that Gradle applies.
  jarsigner -verify "$ARTIFACT_PATH" >/dev/null
  echo "AAB signature verified."
fi

echo "Signed Android artifact: $ARTIFACT_PATH"
echo "artifact_path=${ARTIFACT_PATH}" >> "$GITHUB_OUTPUT"
