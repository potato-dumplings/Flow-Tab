#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_FILE="${ROOT_DIR}/FlowTab.xcodeproj/project.pbxproj"
RELEASE_SCRIPT="${ROOT_DIR}/scripts/release/release-dmg.sh"
SIGNING_SCRIPT="${ROOT_DIR}/scripts/release/sign-macos-bundle.sh"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/release/verify-release-distribution.sh"

require_literal() {
  local file_path="$1"
  local value="$2"

  if ! /usr/bin/grep -F -q -- "${value}" "${file_path}"; then
    echo "Missing release distribution contract '${value}' in ${file_path}" >&2
    exit 1
  fi
}

require_literal "${PROJECT_FILE}" "ENABLE_HARDENED_RUNTIME = YES;"
require_literal "${RELEASE_SCRIPT}" "Developer ID Application"
require_literal "${RELEASE_SCRIPT}" "FLOWTAB_NOTARY_KEYCHAIN_PROFILE"
require_literal "${RELEASE_SCRIPT}" "notarytool submit"
require_literal "${RELEASE_SCRIPT}" "--wait"
require_literal "${RELEASE_SCRIPT}" "stapler staple"
require_literal "${RELEASE_SCRIPT}" "stapler validate"
require_literal "${RELEASE_SCRIPT}" "--timestamp"
require_literal "${RELEASE_SCRIPT}" "sign-macos-bundle.sh"
require_literal "${RELEASE_SCRIPT}" "verify-release-distribution.sh"
require_literal "${SIGNING_SCRIPT}" "--options runtime"
require_literal "${VERIFY_SCRIPT}" "Developer ID Application"
require_literal "${VERIFY_SCRIPT}" "context:primary-signature"

if /usr/bin/grep -F -q -- "codesign --force --deep --sign" "${RELEASE_SCRIPT}" "${SIGNING_SCRIPT}"; then
  echo "Release signing must sign nested code explicitly before the outer bundle." >&2
  exit 1
fi

echo "Release distribution contract requires Developer ID, hardened runtime, timestamping, notarization, and stapling."
