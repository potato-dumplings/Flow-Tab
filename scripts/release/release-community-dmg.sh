#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_BUNDLE_NAME="Flow Tab.app"
APP_BUNDLE_ID="io.github.potato-dumplings.flowtab"
APP_EXECUTABLE_NAME="FlowTab"
APP_ENTITLEMENTS_PATH="${ROOT_DIR}/FlowTab/Resources/FlowTab.entitlements"
INFO_PLIST_PATH="${ROOT_DIR}/FlowTab/Resources/Info.plist"
SPARKLE_FEED_URL="$(
  /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${INFO_PLIST_PATH}"
)"
SPARKLE_PUBLIC_KEY="$(
  /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${INFO_PLIST_PATH}"
)"
PATH_BOUNDARIES_PATH="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
RELEASE_SECURITY_PATH="${ROOT_DIR}/scripts/release/release-security.sh"
DMG_MOUNT_LIFECYCLE_PATH="${ROOT_DIR}/scripts/release/lib/dmg-mount-lifecycle.sh"
SIGN_BUNDLE_PATH="${ROOT_DIR}/scripts/release/sign-macos-bundle.sh"
RELEASE_BINARY_VERIFY_PATH="${ROOT_DIR}/scripts/release/verify-release-binary.sh"
IDENTITY_AUDIT_PATH="${ROOT_DIR}/.agents/skills/flowtab-engineering/scripts/release_identity_audit.py"
CERTIFICATE_TEAM_PATH="${ROOT_DIR}/scripts/release/certificate-team-id.py"

# shellcheck source=/dev/null
source "${PATH_BOUNDARIES_PATH}"
# shellcheck source=/dev/null
source "${RELEASE_SECURITY_PATH}"

usage() {
  cat <<'EOF'
Usage: scripts/release/release-community-dmg.sh \
  --version <v-version> \
  --baseline-dmg <previous-public-dmg> \
  [--skip-build]

Builds a universal Community Build signed with the Apple Development
certificate whose certificate OU matches the previous public release.
EOF
}

VERSION=""
BASELINE_DMG=""
SKIP_BUILD="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 64; }
      VERSION="$2"
      shift 2
      ;;
    --baseline-dmg)
      [[ $# -ge 2 ]] || { echo "Missing value for --baseline-dmg" >&2; exit 64; }
      BASELINE_DMG="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

VERSION="$(flowtab_require_release_version "${VERSION}")"
if [[ ! -f "${BASELINE_DMG}" || -L "${BASELINE_DMG}" ]]; then
  echo "Community distribution requires a regular baseline DMG." >&2
  exit 66
fi
BASELINE_DMG="$(cd "$(dirname "${BASELINE_DMG}")" && pwd -P)/$(basename "${BASELINE_DMG}")"

PACKAGE_BASENAME="FlowTab-${VERSION}"
ASSET_BASENAME="${PACKAGE_BASENAME}.dmg"
CHECKSUM_BASENAME="${PACKAGE_BASENAME}.sha256"
VOLUME_NAME="${PACKAGE_BASENAME}"
RELEASE_DIR="$(flowtab_prepare_direct_child_directory "${ROOT_DIR}" "release")"
RELEASE_VERSION_DIR="$(flowtab_resolve_direct_child_path "${RELEASE_DIR}" "${PACKAGE_BASENAME}")"
BUILD_ROOT="$(flowtab_prepare_direct_child_directory "${ROOT_DIR}" ".build-local")"
PACKAGING_PARENT="$(flowtab_prepare_direct_child_directory "${BUILD_ROOT}" "release-packaging")"
ROLLBACK_PARENT="$(flowtab_prepare_direct_child_directory "${BUILD_ROOT}" "release-rollback")"
CANDIDATE_ROOT="$(/usr/bin/mktemp -d "${PACKAGING_PARENT%/}/${PACKAGE_BASENAME}-community.XXXXXX")"
CANDIDATE_OUTPUT="$(flowtab_prepare_direct_child_directory "${CANDIDATE_ROOT}" "final-output")"
OUTPUT_DMG="$(flowtab_resolve_direct_child_path "${CANDIDATE_OUTPUT}" "${ASSET_BASENAME}")"
OUTPUT_CHECKSUM="$(flowtab_resolve_direct_child_path "${CANDIDATE_OUTPUT}" "${CHECKSUM_BASENAME}")"
BASELINE_APP="${CANDIDATE_ROOT}/baseline/${APP_BUNDLE_NAME}"
STAGING_DIR="${CANDIDATE_ROOT}/dmg-staging"
STAGED_APP="${STAGING_DIR}/${APP_BUNDLE_NAME}"
RW_DMG="${CANDIDATE_ROOT}/temporary.rw.dmg"
SYMBOL_TEMP=""

cleanup() {
  /bin/rm -rf "${CANDIDATE_ROOT}"
  if [[ -n "${SYMBOL_TEMP}" ]]; then
    /bin/rm -rf "${SYMBOL_TEMP}"
  fi
}
trap cleanup EXIT

copy_app_from_dmg() (
  set -euo pipefail
  local dmg_path="$1"
  local destination="$2"
  local mount_root
  local attach_output

  # shellcheck source=/dev/null
  source "${DMG_MOUNT_LIFECYCLE_PATH}"
  mount_root="$(/usr/bin/mktemp -d "${CANDIDATE_ROOT%/}/baseline-mount.XXXXXX")"
  flowtab_dmg_mount_prepare "${mount_root}"
  flowtab_dmg_mount_will_attach
  attach_output="$(
    /usr/bin/hdiutil attach "${dmg_path}" \
      -readonly -nobrowse -mountpoint "${mount_root}"
  )"
  flowtab_dmg_mount_record_attach "${attach_output}"
  if [[ ! -d "${mount_root}/${APP_BUNDLE_NAME}" ]]; then
    echo "Baseline app is missing from the public DMG." >&2
    exit 66
  fi
  /bin/mkdir -p "$(dirname "${destination}")"
  /usr/bin/ditto "${mount_root}/${APP_BUNDLE_NAME}" "${destination}"
  flowtab_dmg_mount_finish
)

codesign_details() {
  /usr/bin/codesign -dv --verbose=4 "$1" 2>&1
}

team_id_for_app() {
  codesign_details "$1" \
    | /usr/bin/sed -n 's/^TeamIdentifier=//p' \
    | /usr/bin/head -n 1
}

bundle_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

resolve_apple_development_identity() {
  local expected_team="$1"
  local identities
  local line
  local fingerprint
  local identity
  local certificate_team

  identities="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
  while IFS= read -r line; do
    fingerprint="${line#*) }"
    fingerprint="${fingerprint%% *}"
    identity="${line#*\"}"
    identity="${identity%%\"*}"
    [[ "${fingerprint}" =~ ^[0-9A-Fa-f]{40}$ ]] || continue
    [[ "${identity}" == Apple\ Development:* ]] || continue
    if certificate_team="$(
      /usr/bin/python3 "${CERTIFICATE_TEAM_PATH}" \
        --fingerprint "${fingerprint}" 2>/dev/null
    )" && [[ "${certificate_team}" == "${expected_team}" ]]; then
      printf '%s' "${fingerprint}"
      return 0
    fi
  done <<< "${identities}"
  return 1
}

verify_nested_code() {
  local app_path="$1"
  local code_path
  while IFS= read -r -d '' code_path; do
    /usr/bin/codesign --verify --strict --verbose=2 "${code_path}"
  done < <(
    /usr/bin/find "${app_path}/Contents" -depth -type d \
      \( -name '*.app' -o -name '*.appex' -o -name '*.bundle' \
        -o -name '*.framework' -o -name '*.plugin' -o -name '*.xpc' \) \
      -print0
  )
  /usr/bin/codesign --verify --deep --strict --verbose=2 "${app_path}"
}

require_sparkle_configuration() {
  local app_path="$1"
  local info_plist="${app_path}/Contents/Info.plist"
  local key
  local expected
  local actual
  shift
  while [[ $# -ge 2 ]]; do
    key="$1"
    expected="$2"
    actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${info_plist}")"
    if [[ "${actual}" != "${expected}" ]]; then
      echo "Sparkle Info.plist value mismatch for ${key}." >&2
      return 1
    fi
    shift 2
  done
}

verify_candidate_dmg() (
  set -euo pipefail
  local mount_root
  local attach_output
  local mounted_app
  local staged_digest
  local mounted_digest
  local gatekeeper_status=0
  local gatekeeper_output=""

  # shellcheck source=/dev/null
  source "${DMG_MOUNT_LIFECYCLE_PATH}"
  mount_root="$(/usr/bin/mktemp -d "${CANDIDATE_ROOT%/}/candidate-mount.XXXXXX")"
  flowtab_dmg_mount_prepare "${mount_root}"
  flowtab_dmg_mount_will_attach
  attach_output="$(
    /usr/bin/hdiutil attach "${OUTPUT_DMG}" \
      -readonly -nobrowse -mountpoint "${mount_root}"
  )"
  flowtab_dmg_mount_record_attach "${attach_output}"
  flowtab_require_distribution_layout "${mount_root}" "${APP_BUNDLE_NAME}"
  mounted_app="${mount_root}/${APP_BUNDLE_NAME}"
  verify_nested_code "${mounted_app}"
  staged_digest="$(flowtab_bundle_tree_digest "${STAGED_APP}")"
  mounted_digest="$(flowtab_bundle_tree_digest "${mounted_app}")"
  if [[ "${staged_digest}" != "${mounted_digest}" ]]; then
    echo "Mounted Community app differs from the verified staged app." >&2
    exit 1
  fi

  /usr/bin/python3 "${IDENTITY_AUDIT_PATH}" \
    --baseline-app "${BASELINE_APP}" \
    --candidate-app "${mounted_app}" \
    --authority-kind apple-development \
    --expected-bundle-id "${APP_BUNDLE_ID}" \
    --expected-version "${VERSION#v}" \
    --expected-team-id "${BASELINE_TEAM}" \
    --required-architectures arm64,x86_64

  set +e
  gatekeeper_output="$(
    /usr/sbin/spctl --assess --type execute --verbose=4 "${mounted_app}" 2>&1
  )"
  gatekeeper_status=$?
  set -e
  printf '%s\n' "${gatekeeper_status}" > "${CANDIDATE_ROOT}/gatekeeper-status"
  printf '%s\n' "${gatekeeper_output}" > "${CANDIDATE_ROOT}/gatekeeper-output"
  flowtab_dmg_mount_finish
)

echo "[1/8] Verify and import the previous public Community baseline"
/usr/bin/hdiutil verify "${BASELINE_DMG}" >/dev/null
copy_app_from_dmg "${BASELINE_DMG}" "${BASELINE_APP}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${BASELINE_APP}"
BASELINE_TEAM="$(team_id_for_app "${BASELINE_APP}")"
BASELINE_BUNDLE_ID="$(bundle_value "${BASELINE_APP}" CFBundleIdentifier)"
BASELINE_BUILD="$(bundle_value "${BASELINE_APP}" CFBundleVersion)"
if [[ ! "${BASELINE_TEAM}" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Baseline TeamIdentifier is unavailable." >&2
  exit 1
fi
if [[ "${BASELINE_BUNDLE_ID}" != "${APP_BUNDLE_ID}" ]]; then
  echo "Baseline Bundle ID does not match FlowTab." >&2
  exit 1
fi
if [[ ! "${BASELINE_BUILD}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Baseline build number is not a positive integer." >&2
  exit 1
fi
if ! SIGNING_IDENTITY="$(resolve_apple_development_identity "${BASELINE_TEAM}")"; then
  echo "No Apple Development certificate has the baseline TeamIdentifier." >&2
  exit 1
fi

echo "[2/8] Build the universal Release candidate"
if [[ "${SKIP_BUILD}" == "true" ]]; then
  BUILD_DERIVED_DATA="${BUILD_ROOT}"
else
  BUILD_DERIVED_DATA="${CANDIDATE_ROOT}/DerivedData"
  (
    cd "${ROOT_DIR}"
    xcodebuild \
      -project FlowTab.xcodeproj \
      -scheme FlowTab \
      -configuration Release \
      -derivedDataPath "${BUILD_DERIVED_DATA}" \
      CODE_SIGNING_ALLOWED=NO \
      ONLY_ACTIVE_ARCH=NO \
      'ARCHS=arm64 x86_64' \
      build
  )
fi
RELEASE_APP="${BUILD_DERIVED_DATA}/Build/Products/Release/${APP_BUNDLE_NAME}"
RELEASE_DSYM="${BUILD_DERIVED_DATA}/Build/Products/Release/${APP_BUNDLE_NAME}.dSYM"
if [[ ! -d "${RELEASE_APP}" ]]; then
  echo "Release app is missing: ${RELEASE_APP}" >&2
  exit 66
fi
"${RELEASE_BINARY_VERIFY_PATH}" --dsym "${RELEASE_DSYM}" "${RELEASE_APP}"

echo "[3/8] Sign nested Sparkle code from the inside out"
/bin/mkdir -p "${STAGING_DIR}"
/usr/bin/ditto "${RELEASE_APP}" "${STAGED_APP}"
"${SIGN_BUNDLE_PATH}" \
  --identity "${SIGNING_IDENTITY}" \
  --entitlements "${APP_ENTITLEMENTS_PATH}" \
  "${STAGED_APP}"
verify_nested_code "${STAGED_APP}"
require_sparkle_configuration "${STAGED_APP}" \
  SUFeedURL "${SPARKLE_FEED_URL}" \
  SUPublicEDKey "${SPARKLE_PUBLIC_KEY}" \
  SUEnableAutomaticChecks true \
  SUScheduledCheckInterval 86400 \
  SUAutomaticallyUpdate false \
  SUAllowsAutomaticUpdates false \
  SURequireSignedFeed true \
  SUVerifyUpdateBeforeExtraction true
CANDIDATE_TEAM="$(team_id_for_app "${STAGED_APP}")"
CANDIDATE_BUILD="$(bundle_value "${STAGED_APP}" CFBundleVersion)"
CANDIDATE_VERSION="$(bundle_value "${STAGED_APP}" CFBundleShortVersionString)"
if [[ "${CANDIDATE_TEAM}" != "${BASELINE_TEAM}" ]]; then
  echo "Candidate TeamIdentifier differs from the public baseline." >&2
  exit 1
fi
if [[ "${CANDIDATE_VERSION}" != "${VERSION#v}" ]]; then
  echo "Candidate display version differs from the release version." >&2
  exit 1
fi
if [[ ! "${CANDIDATE_BUILD}" =~ ^[1-9][0-9]*$ ]] \
  || (( CANDIDATE_BUILD <= BASELINE_BUILD )); then
  echo "Candidate build number must exceed the public baseline build." >&2
  exit 1
fi
/bin/ln -s /Applications "${STAGING_DIR}/Applications"

echo "[4/8] Create and sign the universal Community disk image"
/usr/bin/hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov -format UDRW "${RW_DMG}" >/dev/null
/usr/bin/hdiutil convert \
  "${RW_DMG}" -format UDZO -imagekey zlib-level=9 \
  -o "${OUTPUT_DMG}" >/dev/null
/usr/bin/codesign --force --sign "${SIGNING_IDENTITY}" "${OUTPUT_DMG}"
/usr/bin/codesign --verify --strict --verbose=2 "${OUTPUT_DMG}"

echo "[5/8] Audit mounted identity, layout, architectures, and Gatekeeper"
verify_candidate_dmg

echo "[6/8] Write and verify SHA-256"
DMG_SHA256="$(LC_ALL=C /usr/bin/shasum -a 256 "${OUTPUT_DMG}" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s  %s\n' "${DMG_SHA256}" "${ASSET_BASENAME}" > "${OUTPUT_CHECKSUM}"
(
  cd "${CANDIDATE_OUTPUT}"
  LC_ALL=C /usr/bin/shasum -a 256 -c "${CHECKSUM_BASENAME}"
)
flowtab_require_release_artifact_layout \
  "${CANDIDATE_OUTPUT}" "${ASSET_BASENAME}" "${CHECKSUM_BASENAME}"
flowtab_require_release_checksum \
  "${CANDIDATE_OUTPUT}" "${ASSET_BASENAME}" "${CHECKSUM_BASENAME}"

echo "[7/8] Archive matching private symbols"
SYMBOL_PARENT="$(flowtab_prepare_direct_child_directory "${BUILD_ROOT}" "release-symbols")"
SYMBOL_NAME="${PACKAGE_BASENAME}-${DMG_SHA256}"
SYMBOL_PATH="$(flowtab_resolve_direct_child_path "${SYMBOL_PARENT}" "${SYMBOL_NAME}")"
if [[ ! -d "${SYMBOL_PATH}" ]]; then
  SYMBOL_TEMP="$(/usr/bin/mktemp -d "${SYMBOL_PARENT%/}/.${PACKAGE_BASENAME}-symbols.XXXXXX")"
  /usr/bin/ditto "${RELEASE_DSYM}" "${SYMBOL_TEMP}/${APP_BUNDLE_NAME}.dSYM"
  "${RELEASE_BINARY_VERIFY_PATH}" \
    --dsym "${SYMBOL_TEMP}/${APP_BUNDLE_NAME}.dSYM" "${STAGED_APP}"
  /bin/mv "${SYMBOL_TEMP}" "${SYMBOL_PATH}"
  SYMBOL_TEMP=""
fi

echo "[8/8] Promote the verified release directory"
flowtab_promote_release_artifact_directory \
  "${CANDIDATE_OUTPUT}" "${RELEASE_DIR}" "${PACKAGE_BASENAME}" \
  "${ROLLBACK_PARENT}" "${ASSET_BASENAME}" "${CHECKSUM_BASENAME}"
FINAL_DMG="${RELEASE_VERSION_DIR}/${ASSET_BASENAME}"
FINAL_CHECKSUM="${RELEASE_VERSION_DIR}/${CHECKSUM_BASENAME}"
GATEKEEPER_STATUS="$(<"${CANDIDATE_ROOT}/gatekeeper-status")"
GATEKEEPER_OUTPUT="$(<"${CANDIDATE_ROOT}/gatekeeper-output")"

cleanup
trap - EXIT

echo "Done: ${FINAL_DMG}"
echo "Checksum: ${FINAL_CHECKSUM}"
echo "Distribution: Community Build"
echo "Signing: Apple Development"
echo "TeamIdentifier: ${BASELINE_TEAM}"
echo "Architectures: arm64 x86_64"
echo "Notarization: unnotarized"
echo "Gatekeeper exit status: ${GATEKEEPER_STATUS}"
echo "Gatekeeper readback: ${GATEKEEPER_OUTPUT:-<empty>}"
