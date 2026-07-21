#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/.build-local"
APP_BUNDLE_NAME="Flow Tab.app"
UNINSTALLER_APP_NAME="Uninstall Flow Tab.app"
RELEASE_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${APP_BUNDLE_NAME}"
RELEASE_DIR="${ROOT_DIR}/release"
PROJECT_PREFIX="flowtab"
APP_EXECUTABLE_PATH="${RELEASE_APP_PATH}/Contents/MacOS/FlowTab"
UNINSTALLER_SOURCE_PATH="${ROOT_DIR}/scripts/release/uninstall-flowtab.js"
RELEASE_BINARY_VERIFY_PATH="${ROOT_DIR}/scripts/release/verify-release-binary.sh"
LOCAL_SIGNING_CONFIG_PATH="${ROOT_DIR}/xcconfigs/LocalSigning.xcconfig"
DEVELOPMENT_TEAM="${FLOWTAB_DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY="${FLOWTAB_CODE_SIGN_IDENTITY:-Apple Development}"
RESOLVED_CODE_SIGN_IDENTITY=""

usage() {
  cat <<'EOF'
Usage: ./scripts/release/release-dmg.sh [--version <version>] [--target <target>] [--skip-build]

Options:
  --version <version>  Override release version (supports 1.2.3, v1.2.3, or flowtab-v1.2.3).
  --target <target>    Set asset target name (for example aarch64-apple-darwin).
  --skip-build         Reuse existing Release app without rebuilding.
  -h, --help           Show this help message.

Environment:
  FLOWTAB_DEVELOPMENT_TEAM       Optional team id; falls back to xcconfigs/LocalSigning.xcconfig.
  FLOWTAB_CODE_SIGN_IDENTITY     Optional local identity; defaults to "Apple Development".

Release version resolution:
- Prefer --version when provided.
- Otherwise read the current release tag from GITHUB_REF_NAME or tags pointing at HEAD.
- Supported tag forms: flowtab-v<version> (preferred) and v<version>.
- MARKETING_VERSION is validated against the resolved release version, but is not used as the release source.

When --target is not provided:
- Single-arch app -> produce one DMG for that architecture.
- Universal app (arm64 + x86_64) -> produce one universal DMG.
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

    if [[ -n "${requested}" && "${requested}" != "Apple Development" && "${identity}" != "${requested}" ]]; then
      continue
    fi

    if [[ "${requested}" == "Apple Development" && "${identity}" != Apple\ Development:* ]]; then
      continue
    fi

    printf '%s' "${identity}"
    return 0
  done <<< "${identities}"

  return 1
}

resolve_release_signing_identity() {
  if [[ -z "${DEVELOPMENT_TEAM}" ]]; then
    DEVELOPMENT_TEAM="$(detect_local_development_team)"
  fi

  if RESOLVED_CODE_SIGN_IDENTITY="$(resolve_code_sign_identity "${CODE_SIGN_IDENTITY}" "${DEVELOPMENT_TEAM}")"; then
    echo "Using code-signing identity: ${RESOLVED_CODE_SIGN_IDENTITY}"
    return 0
  fi

  echo "Could not resolve a local code-signing identity for release DMG." >&2
  echo "Requested identity: ${CODE_SIGN_IDENTITY}" >&2
  if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
    echo "Requested team: ${DEVELOPMENT_TEAM}" >&2
  fi
  echo "Available code-signing identities:" >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
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
TARGET=""
SKIP_BUILD="false"

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
    --target)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --target" >&2
        exit 1
      fi
      TARGET="$2"
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

APP_MARKETING_VERSION="$(detect_app_marketing_version)"
if [[ -n "${APP_MARKETING_VERSION}" && "${APP_MARKETING_VERSION}" != "${VERSION#v}" ]]; then
  echo "FlowTab MARKETING_VERSION (${APP_MARKETING_VERSION}) does not match release version (${VERSION#v})." >&2
  echo "Update the app display version before packaging this release." >&2
  exit 1
fi

RELEASE_TAG="${PROJECT_PREFIX}-${VERSION}"
RELEASE_VERSION_DIR="${RELEASE_DIR}/${RELEASE_TAG}"

default_target_for_uname() {
  case "$(uname -m)" in
    arm64)
      echo "aarch64-apple-darwin"
      ;;
    x86_64)
      echo "x86_64-apple-darwin"
      ;;
    *)
      echo "$(uname -m)-apple-darwin"
      ;;
  esac
}

mkdir -p "${RELEASE_DIR}"

echo "[1/5] Resolve local signing identity"
resolve_release_signing_identity

if [[ "${SKIP_BUILD}" != "true" ]]; then
  echo "[2/5] Build Release"
  cd "${ROOT_DIR}"
  xcodebuild \
    -project FlowTab.xcodeproj \
    -scheme FlowTab \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    build
else
  echo "[2/5] Reuse existing Release build"
fi

if [[ ! -d "${RELEASE_APP_PATH}" ]]; then
  echo "Build output not found: ${RELEASE_APP_PATH}" >&2
  exit 1
fi

"${RELEASE_BINARY_VERIFY_PATH}" "${RELEASE_APP_PATH}"

TARGET_NAME=""
if [[ -n "${TARGET}" ]]; then
  TARGET_NAME="${TARGET}"
else
  APP_ARCHS="$(lipo -archs "${APP_EXECUTABLE_PATH}" 2>/dev/null || true)"
  HAS_ARM64="false"
  HAS_X86_64="false"
  for ARCH in ${APP_ARCHS}; do
    case "${ARCH}" in
      arm64|arm64e)
        HAS_ARM64="true"
        ;;
      x86_64)
        HAS_X86_64="true"
        ;;
    esac
  done

  if [[ "${HAS_ARM64}" == "true" && "${HAS_X86_64}" == "true" ]]; then
    TARGET_NAME="universal2-apple-darwin"
  elif [[ "${HAS_ARM64}" == "true" ]]; then
    TARGET_NAME="aarch64-apple-darwin"
  elif [[ "${HAS_X86_64}" == "true" ]]; then
    TARGET_NAME="x86_64-apple-darwin"
  else
    TARGET_NAME="$(default_target_for_uname)"
  fi
fi

mkdir -p "${RELEASE_VERSION_DIR}"

ASSET_BASENAME="${PROJECT_PREFIX}-${TARGET_NAME}.dmg"
OUTPUT_DMG_PATH="${RELEASE_VERSION_DIR}/${ASSET_BASENAME}"
VOLUME_NAME="Flow Tab ${VERSION}"
STAGING_DIR="${RELEASE_VERSION_DIR}/.dmg-staging-${TARGET_NAME}"
STAGED_APP_PATH="${STAGING_DIR}/${APP_BUNDLE_NAME}"
RW_DMG_PATH="${RELEASE_VERSION_DIR}/.flowtab-${TARGET_NAME}.temp.rw.dmg"

echo "[3/5] Prepare and sign DMG staging (${TARGET_NAME})"
rm -rf "${STAGING_DIR}" "${RW_DMG_PATH}" "${OUTPUT_DMG_PATH}"
mkdir -p "${STAGING_DIR}"
/usr/bin/ditto "${RELEASE_APP_PATH}" "${STAGED_APP_PATH}"
/usr/bin/codesign --force --deep --sign "${RESOLVED_CODE_SIGN_IDENTITY}" "${STAGED_APP_PATH}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${STAGED_APP_PATH}"
osacompile -l JavaScript -o "${STAGING_DIR}/${UNINSTALLER_APP_NAME}" "${UNINSTALLER_SOURCE_PATH}" >/dev/null
ln -s /Applications "${STAGING_DIR}/Applications"

echo "[4/5] Create writable image (${TARGET_NAME})"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDRW \
  "${RW_DMG_PATH}" >/dev/null

echo "[5/5] Convert to compressed image (${TARGET_NAME})"
hdiutil convert \
  "${RW_DMG_PATH}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${OUTPUT_DMG_PATH}" >/dev/null

rm -rf "${STAGING_DIR}" "${RW_DMG_PATH}"
echo "Done: ${OUTPUT_DMG_PATH}"

echo "Release version: ${VERSION}"
echo "Release tag: ${RELEASE_TAG}"
echo "Release asset: ${ASSET_BASENAME}"
echo "Release directory: ${RELEASE_VERSION_DIR}"
echo "App signing identity: ${RESOLVED_CODE_SIGN_IDENTITY}"
echo "Note: The app inside this DMG is signed locally. The DMG itself is unsigned and not notarized."
