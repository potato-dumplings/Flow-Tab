#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_FILE="${ROOT_DIR}/FlowTab.xcodeproj/project.pbxproj"
RELEASE_SCRIPT="${ROOT_DIR}/scripts/release/release-dmg.sh"
RELEASE_INSTALL_SCRIPT="${ROOT_DIR}/scripts/release/release-install.sh"
RELEASE_BINARY_VERIFY_SCRIPT="${ROOT_DIR}/scripts/release/verify-release-binary.sh"
RELEASE_BINARY_CONTRACT_TEST="${ROOT_DIR}/scripts/release/test-release-binary-contract.sh"
SIGNING_SCRIPT="${ROOT_DIR}/scripts/release/sign-macos-bundle.sh"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/release/verify-release-distribution.sh"
PATH_BOUNDARIES_SCRIPT="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
RELEASE_SECURITY_SCRIPT="${ROOT_DIR}/scripts/release/release-security.sh"
SECURITY_BOUNDARY_TEST="${ROOT_DIR}/scripts/release/test-release-security-boundaries.sh"
DMG_MOUNT_LIFECYCLE_TEST="${ROOT_DIR}/scripts/release/test-dmg-mount-lifecycle.sh"

require_literal() {
  local file_path="$1"
  local value="$2"

  if ! /usr/bin/grep -F -q -- "${value}" "${file_path}"; then
    echo "Missing release distribution contract '${value}' in ${file_path}" >&2
    exit 1
  fi
}

reject_literal() {
  local file_path="$1"
  local value="$2"

  if /usr/bin/grep -F -q -- "${value}" "${file_path}"; then
    echo "Unexpected release distribution contract '${value}' in ${file_path}" >&2
    exit 1
  fi
}

require_literal "${PROJECT_FILE}" "ENABLE_HARDENED_RUNTIME = YES;"
require_literal "${PROJECT_FILE}" "DEPLOYMENT_POSTPROCESSING = YES;"
require_literal "${PROJECT_FILE}" "STRIP_INSTALLED_PRODUCT = YES;"
require_literal "${PROJECT_FILE}" 'STRIP_STYLE = "non-global";'
require_literal "${PROJECT_FILE}" "STRIP_SWIFT_SYMBOLS = YES;"
require_literal "${RELEASE_SCRIPT}" "Developer ID Application"
require_literal "${RELEASE_SCRIPT}" "FLOWTAB_NOTARY_KEYCHAIN_PROFILE"
require_literal "${RELEASE_SCRIPT}" "notarytool submit"
require_literal "${RELEASE_SCRIPT}" "--wait"
require_literal "${RELEASE_SCRIPT}" "stapler staple"
require_literal "${RELEASE_SCRIPT}" "stapler validate"
require_literal "${RELEASE_SCRIPT}" "--timestamp"
require_literal "${RELEASE_SCRIPT}" "sign-macos-bundle.sh"
require_literal "${RELEASE_SCRIPT}" "verify-release-distribution.sh"
require_literal "${RELEASE_SCRIPT}" "flowtab_prepare_direct_child_directory"
require_literal "${RELEASE_SCRIPT}" 'PACKAGE_BASENAME="FlowTab-${VERSION}"'
require_literal "${RELEASE_SCRIPT}" 'ASSET_BASENAME="${PACKAGE_BASENAME}.dmg"'
require_literal "${RELEASE_SCRIPT}" 'CHECKSUM_BASENAME="${PACKAGE_BASENAME}.sha256"'
require_literal "${RELEASE_SCRIPT}" "flowtab_require_release_artifact_layout"
require_literal "${RELEASE_SCRIPT}" "flowtab_require_release_checksum"
require_literal "${RELEASE_SCRIPT}" "flowtab_promote_release_artifact_directory"
require_literal "${RELEASE_SCRIPT}" 'CANDIDATE_BUILD_ROOT="$('
require_literal "${RELEASE_SCRIPT}" 'ROLLBACK_PARENT="$('
require_literal "${RELEASE_SCRIPT}" 'BUILD_DERIVED_DATA_PATH="${CANDIDATE_BUILD_ROOT}/DerivedData"'
require_literal "${RELEASE_SCRIPT}" 'flowtab_prepare_direct_child_directory "${DERIVED_DATA_PATH}" "release-symbols"'
require_literal "${RELEASE_SCRIPT}" 'SYMBOL_ARCHIVE_NAME="${PACKAGE_BASENAME}-${DMG_SHA256}"'
require_literal "${RELEASE_SCRIPT}" 'shasum -a 256 -c "${CHECKSUM_BASENAME}"'
require_literal "${RELEASE_SCRIPT}" "resolve_expected_release_team"
require_literal "${RELEASE_SCRIPT}" "flowtab_require_team_id"
require_literal "${RELEASE_SCRIPT}" 'Release directory: ${RESOLVED_RELEASE_VERSION_DIR}'
require_literal "${RELEASE_SCRIPT}" 'Release checksum: ${CHECKSUM_BASENAME}'
require_literal "${RELEASE_SCRIPT}" "--expected-team-id"
require_literal "${RELEASE_SCRIPT}" "--expected-bundle-id"
require_literal "${RELEASE_SCRIPT}" "--expected-entitlements"
require_literal "${RELEASE_SCRIPT}" '--dsym "${RELEASE_DSYM_PATH}"'
require_literal "${RELEASE_INSTALL_SCRIPT}" '--dsym "${RELEASE_DSYM_PATH}"'
require_literal "${RELEASE_BINARY_VERIFY_SCRIPT}" "LC_DYSYMTAB"
require_literal "${RELEASE_BINARY_VERIFY_SCRIPT}" "Release executable and dSYM UUIDs do not match."
require_literal "${RELEASE_BINARY_VERIFY_SCRIPT}" "Release dSYM has no DWARF debug info"
require_literal "${SIGNING_SCRIPT}" "--options runtime"
require_literal "${RELEASE_SECURITY_SCRIPT}" "Developer ID Application"
require_literal "${VERIFY_SCRIPT}" "context:primary-signature"
require_literal "${VERIFY_SCRIPT}" "hdiutil attach"
require_literal "${VERIFY_SCRIPT}" "dmg-mount-lifecycle.sh"
require_literal "${VERIFY_SCRIPT}" "flowtab_dmg_mount_finish"
require_literal "${VERIFY_SCRIPT}" "flowtab_bundle_tree_digest"
require_literal "${VERIFY_SCRIPT}" "flowtab_require_distribution_layout"
require_literal "${VERIFY_SCRIPT}" "flowtab_require_nested_code_identities"
require_literal "${PATH_BOUNDARIES_SCRIPT}" "flowtab_prepare_direct_child_directory"
require_literal "${RELEASE_SECURITY_SCRIPT}" "TeamIdentifier="
require_literal "${RELEASE_SECURITY_SCRIPT}" "flowtab_require_release_artifact_layout"
require_literal "${RELEASE_SECURITY_SCRIPT}" "flowtab_require_release_checksum"
require_literal "${RELEASE_SECURITY_SCRIPT}" "flowtab_promote_release_artifact_directory"

reject_literal "${RELEASE_SCRIPT}" "--target"
reject_literal "${RELEASE_SCRIPT}" "Uninstall Flow Tab.app"
reject_literal "${RELEASE_SCRIPT}" "uninstall-flowtab.js"
reject_literal "${RELEASE_SCRIPT}" ".dmg.sha256"
reject_literal "${VERIFY_SCRIPT}" "--expected-dmg-bundle"

if /usr/bin/grep -F -q -- "codesign --force --deep --sign" "${RELEASE_SCRIPT}" "${SIGNING_SCRIPT}"; then
  echo "Release signing must sign nested code explicitly before the outer bundle." >&2
  exit 1
fi

"${SECURITY_BOUNDARY_TEST}"
"${DMG_MOUNT_LIFECYCLE_TEST}"
"${RELEASE_BINARY_CONTRACT_TEST}"

echo "Release distribution contract requires atomically promoted canonical two-file install-only output, stripped symbols, usable matching dSYM data, Developer ID, hardened runtime, timestamping, notarization, and stapling."
