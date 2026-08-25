#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/.build-local"
APP_BUNDLE_NAME="Flow Tab.app"
APP_BUNDLE_ID="io.github.potato-dumplings.flowtab"
APP_EXECUTABLE_NAME="FlowTab"
RELEASE_APP_PATH=""
RELEASE_DSYM_PATH=""
RELEASE_DIR="${ROOT_DIR}/release"
PROJECT_PREFIX="flowtab"
RELEASE_BINARY_VERIFY_PATH="${ROOT_DIR}/scripts/release/verify-release-binary.sh"
RELEASE_DISTRIBUTION_CONTRACT_PATH="${ROOT_DIR}/scripts/release/test-release-distribution-contract.sh"
RELEASE_DISTRIBUTION_VERIFY_PATH="${ROOT_DIR}/scripts/release/verify-release-distribution.sh"
COMMUNITY_RELEASE_PATH="${ROOT_DIR}/scripts/release/release-community-dmg.sh"
SIGN_BUNDLE_PATH="${ROOT_DIR}/scripts/release/sign-macos-bundle.sh"
PATH_BOUNDARIES_PATH="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
RELEASE_SECURITY_PATH="${ROOT_DIR}/scripts/release/release-security.sh"
APP_ENTITLEMENTS_PATH="${ROOT_DIR}/FlowTab/Resources/FlowTab.entitlements"
LOCAL_SIGNING_CONFIG_PATH="${ROOT_DIR}/xcconfigs/LocalSigning.xcconfig"
DEVELOPMENT_TEAM="${FLOWTAB_DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY="${FLOWTAB_CODE_SIGN_IDENTITY:-Developer ID Application}"
NOTARY_KEYCHAIN_PROFILE="${FLOWTAB_NOTARY_KEYCHAIN_PROFILE:-}"
RESOLVED_CODE_SIGN_IDENTITY=""

# shellcheck source=/dev/null
source "${PATH_BOUNDARIES_PATH}"
# shellcheck source=/dev/null
source "${RELEASE_SECURITY_PATH}"

usage() {
  cat <<'EOF'
Usage: ./scripts/release/release-dmg.sh \
  [--version <version>] \
  [--distribution <developer-id|community>] \
  [--baseline-dmg <previous-public-dmg>] \
  [--skip-build]

Options:
  --version <version>  Override release version (supports 1.2.3, v1.2.3, or flowtab-v1.2.3).
  --distribution       Select Developer ID or Community distribution. Defaults to developer-id.
  --baseline-dmg       Required previous public DMG for Community signature continuity.
  --skip-build         Reuse existing Release app without rebuilding.
  -h, --help           Show this help message.

Environment:
  FLOWTAB_DEVELOPMENT_TEAM          Pinned release Team ID; falls back to xcconfigs/LocalSigning.xcconfig.
  FLOWTAB_CODE_SIGN_IDENTITY        Optional identity; defaults to "Developer ID Application".
  FLOWTAB_NOTARY_KEYCHAIN_PROFILE   Required notarytool keychain profile name.

The pinned release Team ID must be present in one of the supported configuration sources.

Release version resolution:
- Prefer --version when provided.
- Otherwise read the current release tag from GITHUB_REF_NAME or tags pointing at HEAD.
- Supported tag forms: flowtab-v<version> (preferred) and v<version>.
- MARKETING_VERSION is validated against the resolved release version, but is not used as the release source.
EOF
}

detect_local_development_team() {
  if [[ ! -f "${LOCAL_SIGNING_CONFIG_PATH}" ]]; then
    return 0
  fi

  awk '
    /^[[:space:]]*(#|\/\/)/ {
      next
    }
    /^[[:space:]]*FLOWTAB_DEVELOPMENT_TEAM[[:space:]]*=/ {
      value = $0
      sub(/^[^=]*=/, "", value)
      sub(/[[:space:]]*\/\/.*$/, "", value)
      sub(/[[:space:]]+$/, "", value)
      sub(/^[[:space:]]+/, "", value)
      if (value != "" && value != "YOUR_TEAM_ID") {
        print value
      }
      exit
    }
  ' "${LOCAL_SIGNING_CONFIG_PATH}"
}

resolve_code_sign_identity() {
  local requested="$1"
  local team="$2"
  local identities
  local line
  local identity

  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  while IFS= read -r line; do
    identity="${line#*\"}"
    identity="${identity%\"*}"

    if [[ "${identity}" == "${line}" ]]; then
      continue
    fi

    if [[ -n "${team}" && "${identity}" != *"(${team})" ]]; then
      continue
    fi

    if [[ "${identity}" != Developer\ ID\ Application:* ]]; then
      continue
    fi

    if [[ -n "${requested}" && "${requested}" != "Developer ID Application" && "${identity}" != "${requested}" ]]; then
      continue
    fi

    printf '%s' "${identity}"
    return 0
  done <<< "${identities}"

  return 1
}

resolve_release_signing_identity() {
  local identity_team_id=""

  if RESOLVED_CODE_SIGN_IDENTITY="$(resolve_code_sign_identity "${CODE_SIGN_IDENTITY}" "${DEVELOPMENT_TEAM}")"; then
    identity_team_id="$(flowtab_extract_team_id_from_identity "${RESOLVED_CODE_SIGN_IDENTITY}")"
    if [[ "${DEVELOPMENT_TEAM}" != "${identity_team_id}" ]]; then
      echo "Resolved distribution identity does not match the configured Team ID." >&2
      exit 1
    fi
    echo "Developer ID Application identity resolved."
    return 0
  fi

  echo "Could not resolve the required Developer ID Application identity for release distribution." >&2
  echo "Install the distribution certificate or set FLOWTAB_CODE_SIGN_IDENTITY to its exact identity name." >&2
  exit 1
}

resolve_expected_release_team() {
  if [[ -z "${DEVELOPMENT_TEAM}" ]]; then
    DEVELOPMENT_TEAM="$(detect_local_development_team)"
  fi
  if [[ -z "${DEVELOPMENT_TEAM}" ]]; then
    echo "A pinned release Team ID is required." >&2
    echo "Set FLOWTAB_DEVELOPMENT_TEAM or configure xcconfigs/LocalSigning.xcconfig." >&2
    exit 1
  fi
  DEVELOPMENT_TEAM="$(flowtab_require_team_id "${DEVELOPMENT_TEAM}")"
}

require_notary_profile() {
  if [[ -z "${NOTARY_KEYCHAIN_PROFILE}" ]]; then
    echo "FLOWTAB_NOTARY_KEYCHAIN_PROFILE is required for public release notarization." >&2
    echo "Create it with: xcrun notarytool store-credentials <profile>" >&2
    exit 1
  fi
}

validate_notary_credentials() {
  if ! /usr/bin/xcrun notarytool history --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" >/dev/null; then
    echo "The configured notarytool keychain profile could not authenticate." >&2
    exit 1
  fi
}

normalize_version() {
  local raw="$1"

  if [[ "${raw}" == "${PROJECT_PREFIX}-v"* ]]; then
    echo "${raw#${PROJECT_PREFIX}-}"
    return 0
  fi

  if [[ "${raw}" == v* ]]; then
    echo "${raw}"
    return 0
  fi

  echo "v${raw}"
}

release_version_from_ref() {
  local raw="$1"

  if [[ "${raw}" == "${PROJECT_PREFIX}-v"* ]]; then
    normalize_version "${raw}"
    return 0
  fi

  if [[ "${raw}" == v* ]]; then
    normalize_version "${raw}"
    return 0
  fi

  return 1
}

detect_version_from_github_ref() {
  local ref_name="${GITHUB_REF_NAME:-}"
  local ref_type="${GITHUB_REF_TYPE:-}"

  if [[ "${ref_type}" != "tag" || -z "${ref_name}" ]]; then
    return 0
  fi

  if ! release_version_from_ref "${ref_name}"; then
    echo "Unsupported release tag: ${ref_name}" >&2
    echo "Use ${PROJECT_PREFIX}-v<version> or v<version>." >&2
    return 1
  fi
}

detect_version_from_head_tags() {
  local tag=""
  local normalized=""
  local unique_versions=()

  while IFS= read -r tag; do
    [[ -z "${tag}" ]] && continue
    if ! normalized="$(release_version_from_ref "${tag}")"; then
      continue
    fi
    if [[ " ${unique_versions[*]} " != *" ${normalized} "* ]]; then
      unique_versions+=("${normalized}")
    fi
  done < <(git tag --points-at HEAD 2>/dev/null || true)

  case "${#unique_versions[@]}" in
    0)
      return 0
      ;;
    1)
      echo "${unique_versions[0]}"
      ;;
    *)
      echo "Multiple release tags point at HEAD: ${unique_versions[*]}" >&2
      echo "Pass --version explicitly or keep a single release tag on the release commit." >&2
      return 1
      ;;
  esac
}

detect_app_marketing_version() {
  local release_config_id=""

  release_config_id="$(
    awk '
      /Build configuration list for PBXNativeTarget "FlowTab"/ {
        in_config_list = 1
        next
      }
      in_config_list && /\);/ {
        in_config_list = 0
      }
      in_config_list && /\/\* Release \*\// {
        print $1
        exit
      }
    ' "${ROOT_DIR}/FlowTab.xcodeproj/project.pbxproj"
  )"

  [[ -z "${release_config_id}" ]] && return 0

  awk -v release_config_id="${release_config_id}" '
    $0 ~ "^[[:space:]]*" release_config_id " /\\* Release \\*/ = \\{" {
      in_release_config = 1
      next
    }
    in_release_config && /MARKETING_VERSION = / {
      split($0, parts, "= ")
      gsub(/[ ;]/, "", parts[2])
      print parts[2]
      exit
    }
    in_release_config && /^[[:space:]]*};/ {
      in_release_config = 0
    }
  ' "${ROOT_DIR}/FlowTab.xcodeproj/project.pbxproj"
}

VERSION=""
SKIP_BUILD="false"
DISTRIBUTION="developer-id"
BASELINE_DMG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --version" >&2
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD="true"
      shift
      ;;
    --distribution)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --distribution" >&2
        exit 1
      fi
      DISTRIBUTION="$2"
      shift 2
      ;;
    --baseline-dmg)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --baseline-dmg" >&2
        exit 1
      fi
      BASELINE_DMG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "${DISTRIBUTION}" in
  developer-id|community)
    ;;
  *)
    echo "Unsupported distribution: ${DISTRIBUTION}" >&2
    exit 1
    ;;
esac

TAG_VERSION=""
if ! TAG_VERSION="$(detect_version_from_github_ref)"; then
  exit 1
fi

if [[ -z "${TAG_VERSION}" ]]; then
  if ! TAG_VERSION="$(detect_version_from_head_tags)"; then
    exit 1
  fi
fi

if [[ -n "${VERSION}" ]]; then
  VERSION="$(normalize_version "${VERSION}")"
  VERSION="$(flowtab_require_release_version "${VERSION}")"
  if [[ -n "${TAG_VERSION}" && "${TAG_VERSION}" != "${VERSION}" ]]; then
    echo "--version (${VERSION}) does not match the current release tag (${TAG_VERSION})." >&2
    exit 1
  fi
else
  VERSION="${TAG_VERSION}"
fi

if [[ -z "${VERSION}" ]]; then
  echo "Release version is required." >&2
  echo "Pass --version or run the script on a release tag (${PROJECT_PREFIX}-v<version> / v<version>)." >&2
  exit 1
fi
VERSION="$(flowtab_require_release_version "${VERSION}")"

APP_MARKETING_VERSION="$(detect_app_marketing_version)"
if [[ -n "${APP_MARKETING_VERSION}" && "${APP_MARKETING_VERSION}" != "${VERSION#v}" ]]; then
  echo "FlowTab MARKETING_VERSION (${APP_MARKETING_VERSION}) does not match release version (${VERSION#v})." >&2
  echo "Update the app display version before packaging this release." >&2
  exit 1
fi

if [[ "${DISTRIBUTION}" == "community" ]]; then
  if [[ -z "${BASELINE_DMG}" ]]; then
    echo "--baseline-dmg is required for Community distribution." >&2
    exit 1
  fi
  COMMUNITY_ARGUMENTS=(
    --version "${VERSION}"
    --baseline-dmg "${BASELINE_DMG}"
  )
  if [[ "${SKIP_BUILD}" == "true" ]]; then
    COMMUNITY_ARGUMENTS+=(--skip-build)
  fi
  exec "${COMMUNITY_RELEASE_PATH}" "${COMMUNITY_ARGUMENTS[@]}"
fi
if [[ -n "${BASELINE_DMG}" ]]; then
  echo "--baseline-dmg is only valid for Community distribution." >&2
  exit 1
fi

RELEASE_TAG="${PROJECT_PREFIX}-${VERSION}"
PACKAGE_BASENAME="FlowTab-${VERSION}"
resolve_expected_release_team

RELEASE_DIR="$(flowtab_prepare_direct_child_directory "${ROOT_DIR}" "release")"
RESOLVED_RELEASE_VERSION_DIR="$(
  flowtab_resolve_direct_child_path "${RELEASE_DIR}" "${PACKAGE_BASENAME}"
)"
if [[ -e "${RESOLVED_RELEASE_VERSION_DIR}" \
  && ! -d "${RESOLVED_RELEASE_VERSION_DIR}" ]]; then
  echo "Release destination is occupied by a non-directory: ${RESOLVED_RELEASE_VERSION_DIR}" >&2
  exit 1
fi

echo "[1/10] Validate distribution identity and notarization credentials"
"${RELEASE_DISTRIBUTION_CONTRACT_PATH}"
require_notary_profile
resolve_release_signing_identity
validate_notary_credentials

ASSET_BASENAME="${PACKAGE_BASENAME}.dmg"
CHECKSUM_BASENAME="${PACKAGE_BASENAME}.sha256"
VOLUME_NAME="${PACKAGE_BASENAME}"
DERIVED_DATA_PATH="$(
  flowtab_prepare_direct_child_directory "${ROOT_DIR}" ".build-local"
)"
PACKAGING_PARENT="$(
  flowtab_prepare_direct_child_directory "${DERIVED_DATA_PATH}" "release-packaging"
)"
ROLLBACK_PARENT="$(
  flowtab_prepare_direct_child_directory "${DERIVED_DATA_PATH}" "release-rollback"
)"
CANDIDATE_BUILD_ROOT="$(
  /usr/bin/mktemp -d \
    "${PACKAGING_PARENT%/}/${PACKAGE_BASENAME}-attempt.XXXXXX"
)"
CANDIDATE_OUTPUT_ROOT="$(
  flowtab_prepare_direct_child_directory "${CANDIDATE_BUILD_ROOT}" "final-output"
)"
OUTPUT_DMG_PATH="$(flowtab_resolve_direct_child_path "${CANDIDATE_OUTPUT_ROOT}" "${ASSET_BASENAME}")"
OUTPUT_CHECKSUM_PATH="$(flowtab_resolve_direct_child_path "${CANDIDATE_OUTPUT_ROOT}" "${CHECKSUM_BASENAME}")"
STAGING_DIR="$(flowtab_resolve_direct_child_path "${CANDIDATE_BUILD_ROOT}" "dmg-staging")"
STAGED_APP_PATH="${STAGING_DIR}/${APP_BUNDLE_NAME}"
RW_DMG_PATH="$(flowtab_resolve_direct_child_path "${CANDIDATE_BUILD_ROOT}" "temporary.rw.dmg")"
SYMBOL_ARCHIVE_TEMP=""

cleanup_release_work_files() {
  /bin/rm -rf "${CANDIDATE_BUILD_ROOT}"
  if [[ -n "${SYMBOL_ARCHIVE_TEMP}" ]]; then
    /bin/rm -rf "${SYMBOL_ARCHIVE_TEMP}"
  fi
}
trap cleanup_release_work_files EXIT

if [[ "${SKIP_BUILD}" != "true" ]]; then
  echo "[2/10] Build Release with Hardened Runtime configuration"
  BUILD_DERIVED_DATA_PATH="${CANDIDATE_BUILD_ROOT}/DerivedData"
  cd "${ROOT_DIR}"
  xcodebuild \
    -project FlowTab.xcodeproj \
    -scheme FlowTab \
    -configuration Release \
    -derivedDataPath "${BUILD_DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    build
else
  echo "[2/10] Reuse existing Release build"
  BUILD_DERIVED_DATA_PATH="${DERIVED_DATA_PATH}"
fi

RELEASE_APP_PATH="${BUILD_DERIVED_DATA_PATH}/Build/Products/Release/${APP_BUNDLE_NAME}"
RELEASE_DSYM_PATH="${BUILD_DERIVED_DATA_PATH}/Build/Products/Release/${APP_BUNDLE_NAME}.dSYM"

if [[ ! -d "${RELEASE_APP_PATH}" ]]; then
  echo "Build output not found: ${RELEASE_APP_PATH}" >&2
  exit 1
fi

"${RELEASE_BINARY_VERIFY_PATH}" \
  --dsym "${RELEASE_DSYM_PATH}" \
  "${RELEASE_APP_PATH}"

echo "[3/10] Prepare and explicitly sign nested distribution code"
mkdir -p "${STAGING_DIR}"
/usr/bin/ditto "${RELEASE_APP_PATH}" "${STAGED_APP_PATH}"
"${SIGN_BUNDLE_PATH}" \
  --identity "${RESOLVED_CODE_SIGN_IDENTITY}" \
  --entitlements "${APP_ENTITLEMENTS_PATH}" \
  --timestamp \
  "${STAGED_APP_PATH}"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "[4/10] Create compressed disk image"
/usr/bin/hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDRW \
  "${RW_DMG_PATH}" >/dev/null
/usr/bin/hdiutil convert \
  "${RW_DMG_PATH}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${OUTPUT_DMG_PATH}" >/dev/null

echo "[5/10] Sign disk image with Developer ID and secure timestamp"
/usr/bin/codesign --force --timestamp --sign "${RESOLVED_CODE_SIGN_IDENTITY}" "${OUTPUT_DMG_PATH}"
/usr/bin/codesign --verify --strict --verbose=2 "${OUTPUT_DMG_PATH}"

echo "[6/10] Submit disk image to Apple notary service"
NOTARY_RESULT=""
if ! NOTARY_RESULT="$(
  /usr/bin/xcrun notarytool submit "${OUTPUT_DMG_PATH}" \
    --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" \
    --wait \
    --output-format json
)"; then
  echo "Apple notarization submission failed." >&2
  exit 1
fi
NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - - <<< "${NOTARY_RESULT}")"
if [[ "${NOTARY_STATUS}" != "Accepted" ]]; then
  echo "Apple notarization did not accept the release (status: ${NOTARY_STATUS})." >&2
  exit 1
fi

echo "[7/10] Staple and validate notarization ticket"
/usr/bin/xcrun stapler staple "${OUTPUT_DMG_PATH}"
/usr/bin/xcrun stapler validate "${OUTPUT_DMG_PATH}"

echo "[8/10] Verify app, DMG, and Gatekeeper acceptance"
"${RELEASE_DISTRIBUTION_VERIFY_PATH}" \
  --expected-team-id "${DEVELOPMENT_TEAM}" \
  --expected-bundle-id "${APP_BUNDLE_ID}" \
  --expected-executable "${APP_EXECUTABLE_NAME}" \
  --expected-entitlements "${APP_ENTITLEMENTS_PATH}" \
  "${STAGED_APP_PATH}" \
  "${OUTPUT_DMG_PATH}"

echo "[9/10] Write checksum and archive matching private symbols"
DMG_SHA256="$(LC_ALL=C /usr/bin/shasum -a 256 "${OUTPUT_DMG_PATH}" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s  %s\n' "${DMG_SHA256}" "${ASSET_BASENAME}" > "${OUTPUT_CHECKSUM_PATH}"
(
  cd "${CANDIDATE_OUTPUT_ROOT}"
  LC_ALL=C /usr/bin/shasum -a 256 -c "${CHECKSUM_BASENAME}"
)
flowtab_require_release_artifact_layout \
  "${CANDIDATE_OUTPUT_ROOT}" \
  "${ASSET_BASENAME}" \
  "${CHECKSUM_BASENAME}"
flowtab_require_release_checksum \
  "${CANDIDATE_OUTPUT_ROOT}" \
  "${ASSET_BASENAME}" \
  "${CHECKSUM_BASENAME}"

SYMBOL_ARCHIVE_PARENT="$(
  flowtab_prepare_direct_child_directory "${DERIVED_DATA_PATH}" "release-symbols"
)"
SYMBOL_ARCHIVE_NAME="${PACKAGE_BASENAME}-${DMG_SHA256}"
SYMBOL_ARCHIVE_PATH="$(
  flowtab_resolve_direct_child_path "${SYMBOL_ARCHIVE_PARENT}" "${SYMBOL_ARCHIVE_NAME}"
)"
if [[ -e "${SYMBOL_ARCHIVE_PATH}" ]]; then
  if [[ ! -d "${SYMBOL_ARCHIVE_PATH}" ]]; then
    echo "Private symbol archive is occupied by a non-directory: ${SYMBOL_ARCHIVE_PATH}" >&2
    exit 1
  fi
  "${RELEASE_BINARY_VERIFY_PATH}" \
    --dsym "${SYMBOL_ARCHIVE_PATH}/${APP_BUNDLE_NAME}.dSYM" \
    "${STAGED_APP_PATH}"
else
  SYMBOL_ARCHIVE_TEMP="$(
    /usr/bin/mktemp -d \
      "${SYMBOL_ARCHIVE_PARENT%/}/.${PACKAGE_BASENAME}-symbols.XXXXXX"
  )"
  /usr/bin/ditto \
    "${RELEASE_DSYM_PATH}" \
    "${SYMBOL_ARCHIVE_TEMP}/${APP_BUNDLE_NAME}.dSYM"
  "${RELEASE_BINARY_VERIFY_PATH}" \
    --dsym "${SYMBOL_ARCHIVE_TEMP}/${APP_BUNDLE_NAME}.dSYM" \
    "${STAGED_APP_PATH}"
  /bin/mv "${SYMBOL_ARCHIVE_TEMP}" "${SYMBOL_ARCHIVE_PATH}"
  SYMBOL_ARCHIVE_TEMP=""
fi
/bin/rm -rf "${STAGING_DIR}" "${RW_DMG_PATH}"

echo "[10/10] Promote verified canonical release directory"
flowtab_promote_release_artifact_directory \
  "${CANDIDATE_OUTPUT_ROOT}" \
  "${RELEASE_DIR}" \
  "${PACKAGE_BASENAME}" \
  "${ROLLBACK_PARENT}" \
  "${ASSET_BASENAME}" \
  "${CHECKSUM_BASENAME}"
OUTPUT_DMG_PATH="${RESOLVED_RELEASE_VERSION_DIR}/${ASSET_BASENAME}"
OUTPUT_CHECKSUM_PATH="${RESOLVED_RELEASE_VERSION_DIR}/${CHECKSUM_BASENAME}"

cleanup_release_work_files
trap - EXIT

echo "Done: ${OUTPUT_DMG_PATH}"

echo "Release version: ${VERSION}"
echo "Release tag: ${RELEASE_TAG}"
echo "Release asset: ${ASSET_BASENAME}"
echo "Release checksum: ${CHECKSUM_BASENAME}"
echo "Release directory: ${RESOLVED_RELEASE_VERSION_DIR}"
echo "Private symbols: ${SYMBOL_ARCHIVE_PATH}/${APP_BUNDLE_NAME}.dSYM"
if [[ -n "${FLOWTAB_RELEASE_ROLLBACK_PATH}" ]]; then
  echo "Rollback directory: ${FLOWTAB_RELEASE_ROLLBACK_PATH}/release-directory"
else
  echo "Rollback directory: none (no preceding same-version directory)"
fi
echo "Distribution verification: Developer ID signed, Hardened Runtime, timestamped, notarized, and stapled"
