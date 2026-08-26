#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PATH_BOUNDARIES_PATH="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
RELEASE_SECURITY_PATH="${ROOT_DIR}/scripts/release/release-security.sh"
RELEASE_SCRIPT="${ROOT_DIR}/scripts/release/release-dmg.sh"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/release/verify-release-distribution.sh"
INSTALL_SCRIPT="${ROOT_DIR}/scripts/testing/install-ui-test-app.sh"
mkdir -p "${ROOT_DIR}/.build-local"
TEST_ROOT="$(/usr/bin/mktemp -d "${ROOT_DIR}/.build-local/release-security-test.XXXXXX")"

cleanup() {
  /bin/rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

fail() {
  echo "$1" >&2
  exit 1
}

assert_rejected_with() {
  local expected="$1"
  shift
  local output=""

  if output="$("$@" 2>&1)"; then
    fail "Command unexpectedly succeeded: $*"
  fi
  if [[ "${output}" != *"${expected}"* ]]; then
    fail "Command did not report '${expected}': $*"
  fi
}

assert_rejected_with \
  "Unknown argument: --target" \
  "${RELEASE_SCRIPT}" --version 1.0 --target '../../../../Documents/flowtab-security-canary'

assert_rejected_with \
  "Unsupported release version" \
  /usr/bin/env \
  GITHUB_REF_TYPE=tag \
  GITHUB_REF_NAME=flowtab-v1.0 \
  "${RELEASE_SCRIPT}" --version '../../../../Documents/flowtab-security-canary'

assert_rejected_with \
  "Unsupported UI test app install path" \
  "${INSTALL_SCRIPT}" --install-path '/tmp/Flow Tab UITest.app'

assert_rejected_with \
  "--expected-team-id is required" \
  "${VERIFY_SCRIPT}" "${TEST_ROOT}/Unsigned.app"

[[ -f "${PATH_BOUNDARIES_PATH}" ]] || fail "Missing shared path-boundary helper."
[[ -f "${RELEASE_SECURITY_PATH}" ]] || fail "Missing release-security helper."

# shellcheck source=/dev/null
source "${PATH_BOUNDARIES_PATH}"
# shellcheck source=/dev/null
source "${RELEASE_SECURITY_PATH}"

for version in v1.0 v1.2.3 v1.2.3-beta.1; do
  [[ "$(flowtab_require_release_version "${version}")" == "${version}" ]] \
    || fail "Supported release version was not preserved: ${version}"
done

for version in '' v1 v1.0/../../outside v1.0+metadata 'v1.0 beta'; do
  if flowtab_require_release_version "${version}" >/dev/null 2>&1; then
    fail "Unsafe release version was accepted: ${version}"
  fi
done

DIRECTORY_BOUNDARY="${TEST_ROOT}/directory-boundary"
OUTSIDE_DIRECTORY="${TEST_ROOT}/outside-directory"
mkdir -p "${DIRECTORY_BOUNDARY}" "${OUTSIDE_DIRECTORY}"
ln -s "${OUTSIDE_DIRECTORY}" "${DIRECTORY_BOUNDARY}/linked-child"
if flowtab_prepare_direct_child_directory "${DIRECTORY_BOUNDARY}" linked-child >/dev/null 2>&1; then
  fail "Symbolic-link directory boundary was accepted."
fi
ln -s "${OUTSIDE_DIRECTORY}" "${DIRECTORY_BOUNDARY}/linked-output"
if flowtab_resolve_direct_child_path "${DIRECTORY_BOUNDARY}" linked-output >/dev/null 2>&1; then
  fail "Symbolic-link output path was accepted."
fi
[[ "$(flowtab_prepare_direct_child_directory "${DIRECTORY_BOUNDARY}" owned-child)" == "${DIRECTORY_BOUNDARY}/owned-child" ]] \
  || fail "Owned child directory did not resolve inside its explicit boundary."

USER_HOME_FIXTURE="${TEST_ROOT}/user-home"
for install_path in \
  "${USER_HOME_FIXTURE}/Applications/Flow Tab UITest.app" \
  "${USER_HOME_FIXTURE}/Applications/Flow Tab.app" \
  '/Applications/Flow Tab UITest.app' \
  '/Applications/Flow Tab.app'
do
  [[ "$(flowtab_resolve_ui_test_install_path "${USER_HOME_FIXTURE}" "${install_path}")" == "${install_path}" ]] \
    || fail "Supported install path was not preserved: ${install_path}"
done

[[ "$(flowtab_resolve_ui_test_install_path "${USER_HOME_FIXTURE}" '~/Applications/Flow Tab UITest.app')" == "${USER_HOME_FIXTURE}/Applications/Flow Tab UITest.app" ]] \
  || fail "Home-relative UI test app path did not resolve against the explicit user-home boundary."

for install_path in \
  '/' \
  "${USER_HOME_FIXTURE}" \
  "${USER_HOME_FIXTURE}/Applications/../Documents/Flow Tab UITest.app" \
  '/Applications/Safari.app' \
  '/tmp/Flow Tab UITest.app'
do
  if flowtab_resolve_ui_test_install_path "${USER_HOME_FIXTURE}" "${install_path}" >/dev/null 2>&1; then
    fail "Unsafe install path was accepted: ${install_path}"
  fi
done

VALID_SIGNATURE_DETAILS=$'Executable=/Applications/Flow Tab.app/Contents/MacOS/FlowTab\nIdentifier=io.github.potato-dumplings.flowtab\nAuthority=Developer ID Application: Flow Tab Developer (TEAM123456)\nTeamIdentifier=TEAM123456\nTimestamp=Aug 12, 2026 at 12:00:00\nCodeDirectory v=20500 size=123 flags=0x10000(runtime) hashes=1+7 location=embedded'

flowtab_require_developer_id_signature_details \
  "${VALID_SIGNATURE_DETAILS}" \
  TEAM123456 \
  "test app"
flowtab_require_codesign_identifier \
  "${VALID_SIGNATURE_DETAILS}" \
  io.github.potato-dumplings.flowtab \
  "test app"

if flowtab_require_developer_id_signature_details "${VALID_SIGNATURE_DETAILS}" OTHERTEAM1 "test app" >/dev/null 2>&1; then
  fail "Signature details accepted the wrong Team ID."
fi
if flowtab_require_team_id 'team123456' >/dev/null 2>&1; then
  fail "Malformed Team ID was accepted."
fi

if flowtab_require_codesign_identifier "${VALID_SIGNATURE_DETAILS}" com.example.substitute "test app" >/dev/null 2>&1; then
  fail "Signature details accepted the wrong signing identifier."
fi

FIXTURE_APP="${TEST_ROOT}/Flow Tab.app"
FIXTURE_COPY="${TEST_ROOT}/Flow Tab Copy.app"
mkdir -p "${FIXTURE_APP}/Contents/MacOS" "${FIXTURE_APP}/Contents/Resources"
/usr/bin/plutil -create xml1 "${FIXTURE_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.github.potato-dumplings.flowtab' \
  -c 'Add :CFBundleExecutable string FlowTab' \
  "${FIXTURE_APP}/Contents/Info.plist" >/dev/null
printf 'fixture executable\n' > "${FIXTURE_APP}/Contents/MacOS/FlowTab"
printf 'fixture resource\n' > "${FIXTURE_APP}/Contents/Resources/value.txt"

flowtab_require_bundle_metadata \
  "${FIXTURE_APP}" \
  io.github.potato-dumplings.flowtab \
  FlowTab

/usr/bin/ditto "${FIXTURE_APP}" "${FIXTURE_COPY}"
[[ "$(flowtab_bundle_tree_digest "${FIXTURE_APP}")" == "$(flowtab_bundle_tree_digest "${FIXTURE_COPY}")" ]] \
  || fail "Identical bundle trees produced different digests."

printf 'changed resource\n' > "${FIXTURE_COPY}/Contents/Resources/value.txt"
[[ "$(flowtab_bundle_tree_digest "${FIXTURE_APP}")" != "$(flowtab_bundle_tree_digest "${FIXTURE_COPY}")" ]] \
  || fail "Changed bundle content was not detected by the tree digest."

EXPECTED_ENTITLEMENTS="${TEST_ROOT}/expected-entitlements.plist"
ACTUAL_ENTITLEMENTS="${TEST_ROOT}/actual-entitlements.plist"
cp "${ROOT_DIR}/FlowTab/Resources/FlowTab.entitlements" "${EXPECTED_ENTITLEMENTS}"
cp "${EXPECTED_ENTITLEMENTS}" "${ACTUAL_ENTITLEMENTS}"
flowtab_require_matching_plists "${EXPECTED_ENTITLEMENTS}" "${ACTUAL_ENTITLEMENTS}" "test entitlements"
/usr/libexec/PlistBuddy -c 'Add :com.example.unexpected bool true' "${ACTUAL_ENTITLEMENTS}"
if flowtab_require_matching_plists "${EXPECTED_ENTITLEMENTS}" "${ACTUAL_ENTITLEMENTS}" "test entitlements" >/dev/null 2>&1; then
  fail "Mismatched entitlements were accepted."
fi

SIGNED_FIXTURE_APP="${TEST_ROOT}/Signed Flow Tab.app"
SIGNED_FIXTURE_ENTITLEMENTS="${TEST_ROOT}/signed-fixture-entitlements.plist"
mkdir -p "${SIGNED_FIXTURE_APP}/Contents/MacOS"
/usr/bin/plutil -create xml1 "${SIGNED_FIXTURE_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.github.potato-dumplings.flowtab' \
  -c 'Add :CFBundleExecutable string FlowTab' \
  "${SIGNED_FIXTURE_APP}/Contents/Info.plist" >/dev/null
cp /usr/bin/true "${SIGNED_FIXTURE_APP}/Contents/MacOS/FlowTab"
/usr/bin/codesign \
  --force \
  --options runtime \
  --entitlements "${EXPECTED_ENTITLEMENTS}" \
  --sign - \
  "${SIGNED_FIXTURE_APP}" >/dev/null 2>&1
/usr/bin/codesign \
  --display \
  --entitlements "${SIGNED_FIXTURE_ENTITLEMENTS}" \
  --xml \
  "${SIGNED_FIXTURE_APP}" >/dev/null 2>&1
flowtab_require_matching_plists \
  "${EXPECTED_ENTITLEMENTS}" \
  "${SIGNED_FIXTURE_ENTITLEMENTS}" \
  "extracted fixture entitlements"
assert_rejected_with \
  "is not signed by a Developer ID Application identity" \
  "${VERIFY_SCRIPT}" \
  --expected-team-id TEAM123456 \
  --expected-bundle-id io.github.potato-dumplings.flowtab \
  --expected-executable FlowTab \
  --expected-entitlements "${EXPECTED_ENTITLEMENTS}" \
  "${SIGNED_FIXTURE_APP}"

DMG_LAYOUT="${TEST_ROOT}/dmg-layout"
mkdir -p "${DMG_LAYOUT}/Flow Tab.app"
ln -s /Applications "${DMG_LAYOUT}/Applications"
flowtab_require_distribution_layout \
  "${DMG_LAYOUT}" \
  "Flow Tab.app"
touch "${DMG_LAYOUT}/unexpected.txt"
if flowtab_require_distribution_layout "${DMG_LAYOUT}" "Flow Tab.app" >/dev/null 2>&1; then
  fail "Unexpected DMG content was accepted."
fi

RELEASE_LAYOUT="${TEST_ROOT}/release-layout"
mkdir -p "${RELEASE_LAYOUT}"
printf 'fixture disk image\n' > "${RELEASE_LAYOUT}/FlowTab-v1.2.3.dmg"
RELEASE_LAYOUT_DIGEST="$(
  LC_ALL=C /usr/bin/shasum -a 256 "${RELEASE_LAYOUT}/FlowTab-v1.2.3.dmg" \
    | /usr/bin/awk '{print $1}'
)"
printf '%s  %s\n' \
  "${RELEASE_LAYOUT_DIGEST}" \
  'FlowTab-v1.2.3.dmg' \
  > "${RELEASE_LAYOUT}/FlowTab-v1.2.3.sha256"
flowtab_require_release_artifact_layout \
  "${RELEASE_LAYOUT}" \
  "FlowTab-v1.2.3.dmg" \
  "FlowTab-v1.2.3.sha256"
flowtab_require_release_checksum \
  "${RELEASE_LAYOUT}" \
  "FlowTab-v1.2.3.dmg" \
  "FlowTab-v1.2.3.sha256"
touch "${RELEASE_LAYOUT}/FlowTab-v1.2.3.dmg.sha256"
if flowtab_require_release_artifact_layout \
  "${RELEASE_LAYOUT}" \
  "FlowTab-v1.2.3.dmg" \
  "FlowTab-v1.2.3.sha256" >/dev/null 2>&1; then
  fail "Release artifact layout accepted a third output file."
fi
/bin/rm -f "${RELEASE_LAYOUT}/FlowTab-v1.2.3.dmg.sha256"

PROMOTION_RELEASE_PARENT="${TEST_ROOT}/promotion-release"
PROMOTION_ROLLBACK_PARENT="${TEST_ROOT}/promotion-rollback"
PROMOTION_CANDIDATE="${TEST_ROOT}/promotion-candidate"
PROMOTION_FINAL="${PROMOTION_RELEASE_PARENT}/FlowTab-v1.2.3"
mkdir -p \
  "${PROMOTION_RELEASE_PARENT}" \
  "${PROMOTION_ROLLBACK_PARENT}" \
  "${PROMOTION_CANDIDATE}" \
  "${PROMOTION_FINAL}"
printf 'preceding release\n' > "${PROMOTION_FINAL}/legacy-marker.txt"
printf 'verified candidate\n' > "${PROMOTION_CANDIDATE}/FlowTab-v1.2.3.dmg"
PROMOTION_DIGEST="$(
  LC_ALL=C /usr/bin/shasum -a 256 "${PROMOTION_CANDIDATE}/FlowTab-v1.2.3.dmg" \
    | /usr/bin/awk '{print $1}'
)"
printf '%s  %s\n' \
  "${PROMOTION_DIGEST}" \
  'FlowTab-v1.2.3.dmg' \
  > "${PROMOTION_CANDIDATE}/FlowTab-v1.2.3.sha256"

flowtab_promote_release_artifact_directory \
  "${PROMOTION_CANDIDATE}" \
  "${PROMOTION_RELEASE_PARENT}" \
  'FlowTab-v1.2.3' \
  "${PROMOTION_ROLLBACK_PARENT}" \
  'FlowTab-v1.2.3.dmg' \
  'FlowTab-v1.2.3.sha256'
[[ ! -e "${PROMOTION_CANDIDATE}" ]] \
  || fail "Verified release candidate remained outside the canonical release path."
[[ -f "${FLOWTAB_RELEASE_ROLLBACK_PATH}/release-directory/legacy-marker.txt" ]] \
  || fail "Preceding release directory was not preserved for rollback."
flowtab_require_release_artifact_layout \
  "${PROMOTION_FINAL}" \
  'FlowTab-v1.2.3.dmg' \
  'FlowTab-v1.2.3.sha256'
flowtab_require_release_checksum \
  "${PROMOTION_FINAL}" \
  'FlowTab-v1.2.3.dmg' \
  'FlowTab-v1.2.3.sha256'

FAILED_PROMOTION_CANDIDATE="${TEST_ROOT}/failed-promotion-candidate"
FAILED_PROMOTION_FINAL="${PROMOTION_RELEASE_PARENT}/FlowTab-v2.0.0"
mkdir -p "${FAILED_PROMOTION_CANDIDATE}" "${FAILED_PROMOTION_FINAL}"
printf 'preceding release remains\n' > "${FAILED_PROMOTION_FINAL}/legacy-marker.txt"
printf 'invalid candidate\n' > "${FAILED_PROMOTION_CANDIDATE}/FlowTab-v2.0.0.dmg"
printf '%064d  %s\n' 0 'FlowTab-v2.0.0.dmg' \
  > "${FAILED_PROMOTION_CANDIDATE}/FlowTab-v2.0.0.sha256"
if flowtab_promote_release_artifact_directory \
  "${FAILED_PROMOTION_CANDIDATE}" \
  "${PROMOTION_RELEASE_PARENT}" \
  'FlowTab-v2.0.0' \
  "${PROMOTION_ROLLBACK_PARENT}" \
  'FlowTab-v2.0.0.dmg' \
  'FlowTab-v2.0.0.sha256' >/dev/null 2>&1; then
  fail "Release promotion accepted an invalid candidate checksum."
fi
[[ -f "${FAILED_PROMOTION_FINAL}/legacy-marker.txt" ]] \
  || fail "Failed release promotion changed the preceding release directory."
[[ -d "${FAILED_PROMOTION_CANDIDATE}" ]] \
  || fail "Failed release promotion removed its private candidate directory."

echo "Release security boundaries reject path traversal, pin distribution identity, and atomically promote install-only canonical package layouts."
