#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_INSTALL_SCRIPT="${ROOT_DIR}/scripts/release/release-install.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_literal() {
  local value="$1"

  /usr/bin/grep -F -q -- "${value}" "${RELEASE_INSTALL_SCRIPT}" \
    || fail "missing release-install contract: ${value}"
}

reject_literal() {
  local value="$1"

  if /usr/bin/grep -F -q -- "${value}" "${RELEASE_INSTALL_SCRIPT}"; then
    fail "unexpected release-install contract: ${value}"
  fi
}

/bin/bash -n "${RELEASE_INSTALL_SCRIPT}"

require_literal 'RELEASE_INSTALL_PARENT="$('
require_literal 'ATTEMPT_ROOT="$(/usr/bin/mktemp -d'
require_literal 'DERIVED_DATA_PATH="${ATTEMPT_ROOT}/DerivedData"'
require_literal 'PACKAGE_CACHE_PATH="${ATTEMPT_ROOT}/SourcePackages"'
require_literal 'STAGED_APP_PATH="${STAGING_DIR}/${APP_BUNDLE_NAME}"'
require_literal '-resolvePackageDependencies'
require_literal '-clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"'
require_literal '/bin/rm -rf "${ATTEMPT_ROOT}"'
reject_literal 'DERIVED_DATA_PATH="${ROOT_DIR}/.build-local"'

PACKAGE_BOUNDARY_COUNT="$(
  /usr/bin/grep -F -c \
    -- '-clonedSourcePackagesDirPath "${PACKAGE_CACHE_PATH}"' \
    "${RELEASE_INSTALL_SCRIPT}"
)"
[[ "${PACKAGE_BOUNDARY_COUNT}" -eq 2 ]] \
  || fail "dependency resolution and build must share the isolated package boundary"

/usr/bin/awk '
  /echo .*Resolve clean Swift package dependencies/ {
    dependency_resolution = NR
  }
  /^[[:space:]]*"\$\{RELEASE_BINARY_VERIFY_PATH\}"[[:space:]]*\\/ {
    binary_verification = NR
  }
  /^[[:space:]]*"\$\{SIGN_BUNDLE_PATH\}"[[:space:]]*\\/ {
    candidate_signing = NR
  }
  /^[[:space:]]*reset_tcc_permission "Accessibility"/ {
    permission_reset = NR
  }
  /^[[:space:]]*\/bin\/rm -rf "\$\{INSTALL_PATH\}"/ {
    installed_app_removal = NR
  }
  END {
    valid = dependency_resolution > 0
    valid = valid && dependency_resolution < binary_verification
    valid = valid && binary_verification < candidate_signing
    valid = valid && candidate_signing < permission_reset
    valid = valid && permission_reset < installed_app_removal
    exit valid ? 0 : 1
  }
' "${RELEASE_INSTALL_SCRIPT}" \
  || fail "build and signed-candidate validation must precede permission reset and app replacement"

echo "Release install contract isolates SwiftPM artifacts and validates the signed candidate before destructive system changes."
