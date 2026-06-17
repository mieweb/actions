#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# import-signing.sh — Secrets-mode certificate & provisioning profile import
#
# Expected env vars (set by action.yml):
#   IOS_CERT_P12_BASE64       Base64-encoded distribution certificate (.p12)
#   IOS_CERT_PASSWORD          Password for the .p12 file
#   IOS_PROV_PROFILE_BASE64   Base64-encoded provisioning profile (.mobileprovision)
#
# Exports to $GITHUB_ENV:
#   KEYCHAIN_PATH   Path to the temporary keychain containing the imported cert
#   PROFILE_UUID    UUID of the installed provisioning profile
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Validate required inputs ────────────────────────────────────────────────
for var in IOS_CERT_P12_BASE64 IOS_CERT_PASSWORD IOS_PROV_PROFILE_BASE64; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::Required env var $var is not set"
    exit 1
  fi
done

# ── Create temporary keychain ───────────────────────────────────────────────
KEYCHAIN_PATH="${RUNNER_TEMP}/app-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# ── Import distribution certificate ────────────────────────────────────────
CERT_PATH="${RUNNER_TEMP}/certificate.p12"
echo "$IOS_CERT_P12_BASE64" | base64 --decode > "$CERT_PATH"

security import "$CERT_PATH" \
  -P "$IOS_CERT_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"

security set-key-partition-list \
  -S apple-tool:,apple: \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"

# Add the new keychain to the search list so xcodebuild can find it
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain

# ── Install provisioning profile ───────────────────────────────────────────
PROFILE_PATH="${RUNNER_TEMP}/profile.mobileprovision"
echo "$IOS_PROV_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"

mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles

PROFILE_UUID="$(
  security cms -D -i "$PROFILE_PATH" \
    | grep -A1 UUID \
    | grep string \
    | sed 's/.*<string>\(.*\)<\/string>/\1/'
)"

cp "$PROFILE_PATH" \
  ~/Library/MobileDevice/Provisioning\ Profiles/"${PROFILE_UUID}".mobileprovision

echo "Installed provisioning profile: ${PROFILE_UUID}"

# ── Export vars for downstream steps ────────────────────────────────────────
echo "KEYCHAIN_PATH=${KEYCHAIN_PATH}" >> "$GITHUB_ENV"
echo "PROFILE_UUID=${PROFILE_UUID}"   >> "$GITHUB_ENV"

# Clean up decoded cert from disk (profile copy is already in the standard dir)
rm -f "$CERT_PATH"
