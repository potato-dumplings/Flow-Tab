#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release/verify-release-distribution.sh <app-bundle> [signed-notarized-dmg]

Verifies Developer ID Application authority, Hardened Runtime, secure timestamp,
Gatekeeper acceptance, and optional signed/stapled DMG acceptance.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 64
fi

APP_PATH="$1"
DMG_PATH="${2:-}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Release app not found: ${APP_PATH}" >&2
  exit 66
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
APP_SIGNATURE_DETAILS="$(/usr/bin/codesign --display --verbose=4 "${APP_PATH}" 2>&1)"

if ! /usr/bin/grep -F -q "Authority=Developer ID Application:" <<< "${APP_SIGNATURE_DETAILS}"; then
  echo "Release app is not signed by a Developer ID Application identity: ${APP_PATH}" >&2
  exit 1
fi

if ! /usr/bin/grep -E -q 'flags=.*\(.*runtime.*\)' <<< "${APP_SIGNATURE_DETAILS}"; then
  echo "Release app signature does not enable Hardened Runtime: ${APP_PATH}" >&2
  exit 1
fi

if ! /usr/bin/grep -E -q '^Timestamp=.+' <<< "${APP_SIGNATURE_DETAILS}"; then
  echo "Release app signature has no secure timestamp: ${APP_PATH}" >&2
  exit 1
fi

/usr/sbin/spctl --assess --type execute --verbose=2 "${APP_PATH}"

if [[ -z "${DMG_PATH}" ]]; then
  echo "Verified Developer ID, Hardened Runtime, timestamp, and Gatekeeper acceptance for app bundle."
  exit 0
fi

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "Release DMG not found: ${DMG_PATH}" >&2
  exit 66
fi

/usr/bin/codesign --verify --strict --verbose=2 "${DMG_PATH}"
DMG_SIGNATURE_DETAILS="$(/usr/bin/codesign --display --verbose=4 "${DMG_PATH}" 2>&1)"

if ! /usr/bin/grep -F -q "Authority=Developer ID Application:" <<< "${DMG_SIGNATURE_DETAILS}"; then
  echo "Release DMG is not signed by a Developer ID Application identity." >&2
  exit 1
fi

if ! /usr/bin/grep -E -q '^Timestamp=.+' <<< "${DMG_SIGNATURE_DETAILS}"; then
  echo "Release DMG signature has no secure timestamp." >&2
  exit 1
fi

/usr/bin/hdiutil verify "${DMG_PATH}" >/dev/null
/usr/bin/xcrun stapler validate "${DMG_PATH}"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"

echo "Verified signed, notarized, stapled, and Gatekeeper-accepted release distribution."
