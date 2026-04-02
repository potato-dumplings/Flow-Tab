#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/.build-local"
APP_BUNDLE_NAME="Flow Tab.app"
RELEASE_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${APP_BUNDLE_NAME}"
RELEASE_DIR="${ROOT_DIR}/release"
PROJECT_PREFIX="flowtab"
APP_EXECUTABLE_PATH="${RELEASE_APP_PATH}/Contents/MacOS/FlowTab"

usage() {
  cat <<'EOF'
Usage: ./scripts/release/release-dmg.sh [--version <version>] [--target <target>] [--skip-build]

Options:
  --version <version>  Set release version for tag output (supports 1.2.3 or v1.2.3).
  --target <target>    Set asset target name (for example aarch64-apple-darwin).
  --skip-build         Reuse existing Release app without rebuilding.
  -h, --help           Show this help message.

When --target is not provided:
- Single-arch app -> produce one DMG for that architecture.
- Universal app (arm64 + x86_64) -> produce one universal DMG.
EOF
}

detect_version() {
  awk -F '= ' '/MARKETING_VERSION = / {gsub(/[ ;]/, "", $2); print $2; exit}' \
    "${ROOT_DIR}/FlowTab.xcodeproj/project.pbxproj"
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

if [[ -z "${VERSION}" ]]; then
  VERSION="$(detect_version)"
fi

if [[ -z "${VERSION}" ]]; then
  VERSION="dev"
fi

VERSION="$(normalize_version "${VERSION}")"
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

if [[ "${SKIP_BUILD}" != "true" ]]; then
  echo "[1/4] Build Release"
  cd "${ROOT_DIR}"
  xcodebuild \
    -project FlowTab.xcodeproj \
    -scheme FlowTab \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    build
fi

if [[ ! -d "${RELEASE_APP_PATH}" ]]; then
  echo "Build output not found: ${RELEASE_APP_PATH}" >&2
  exit 1
fi

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
RW_DMG_PATH="${RELEASE_VERSION_DIR}/.flowtab-${TARGET_NAME}.temp.rw.dmg"

echo "[2/4] Prepare DMG staging (${TARGET_NAME})"
rm -rf "${STAGING_DIR}" "${RW_DMG_PATH}" "${OUTPUT_DMG_PATH}"
mkdir -p "${STAGING_DIR}"
cp -R "${RELEASE_APP_PATH}" "${STAGING_DIR}/${APP_BUNDLE_NAME}"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "[3/4] Create writable image (${TARGET_NAME})"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDRW \
  "${RW_DMG_PATH}" >/dev/null

echo "[4/4] Convert to compressed image (${TARGET_NAME})"
hdiutil convert \
  "${RW_DMG_PATH}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${OUTPUT_DMG_PATH}" >/dev/null

rm -rf "${STAGING_DIR}" "${RW_DMG_PATH}"
echo "Done: ${OUTPUT_DMG_PATH}"

echo "Release tag: ${RELEASE_TAG}"
echo "Release asset: ${ASSET_BASENAME}"
echo "Release directory: ${RELEASE_VERSION_DIR}"
echo "Note: This DMG is unsigned and not notarized."
